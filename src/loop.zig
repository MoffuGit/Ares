//This event loop use as refence libxev and tigerbeetle implementations
//Sources:
// - TigerBeetle: https://github.com/tigerbeetle/tigerbeetle/tree/main [TIGERBEETLE]
// - Libxev: https://github.com/mitchellh/libxev [LIBXEV]

const std = @import("std");
const assert = std.debug.assert;
const posix = std.posix;
const system = posix.system;
const testing = std.testing;
const Io = std.Io;
const meta = std.meta;
const panic = std.debug.panic;
const Kevent = std.c.kevent64_s;
const builtin = @import("builtin");

const datastruct = @import("datastruct.zig");
const MultiQueue = datastruct.MultiQueue;
const heap = datastruct.heap;
const Scheduler = @import("scheduler.zig");

const log = std.log.scoped(.loop);

const Queues = MultiQueue(union(enum) {
    timers: Completion,
    canceling: Completion,
    submissions: Completion,
    completions: Completion,
    cancellations: Completion,
});

pub const Loop = @This();

kq: posix.fd_t,

time: Time,

scheduler: *Scheduler,
queues: Queues,
timers: heap.Intrusive(Timer, void, Timer.less),
inflight: usize,
stopped: bool,

io: Io,

pub fn init(self: *Loop, scheduler: *Scheduler, io: Io) !void {
    const kq = posix.system.kqueue();

    switch (posix.errno(kq)) {
        .SUCCESS => {},
        else => |err| return posix.unexpectedErrno(err),
    }

    self.* = .{
        .scheduler = scheduler,
        .io = io,
        .kq = kq,
        .queues = undefined,
        .inflight = 0,
        .stopped = false,
        .timers = .{ .context = {} },
        .time = undefined,
    };
    self.queues.init();
}

pub fn deinit(self: *Loop) void {
    assert(self.kq > -1);

    _ = posix.system.close(self.kq);
    self.kq = -1;
}

pub const RunMode = enum {
    no_wait,
    until_done,
};

pub fn run(self: *Loop, mode: RunMode) !void {
    switch (mode) {
        .no_wait => try self.flush(false),
        .until_done => while (!self.done()) try self.flush(false),
    }
}

pub fn done(self: *Loop) bool {
    return self.stopped or
        (self.queues.empty(.submissions) and
            self.queues.empty(.completions) and
            self.queues.empty(.timers) and
            self.timers.peek() == null and
            self.inflight == 0);
}

pub fn stop(self: *Loop) void {
    self.stopped = true;
}

pub fn flush(self: *Loop, _: bool) !void {
    self.flushCancelations();
    self.flushTimers();

    var events: [256]Kevent = undefined;

    const canceled = self.flushCanceled(&events);
    const active = if (canceled < events.len)
        self.flush_submissions(events[canceled..])
    else
        0;
    const submitted = canceled + active;

    if (submitted > 0 or self.queues.empty(.completions)) {
        var timeout = std.mem.zeroes(posix.timespec);

        const completed = try kevent(
            self.kq,
            events[0..submitted],
            events[0..events.len],
            &timeout,
        );

        self.inflight += active;

        for (events[0..completed]) |ev| {
            if (ev.udata == 0) continue;

            if (ev.flags & std.c.EV.DELETE != 0) continue;

            self.inflight -= 1;

            const c: *Completion = @ptrFromInt(@as(usize, @intCast(ev.udata)));

            self.complete(c);
        }
    }

    self.flushCompletions();
}

pub fn flushTimers(self: *Loop) void {
    while (self.queues.pop(.timers)) |completion| {
        if (completion.state == .completed) {
            continue;
        }

        assert(completion.state == .submitted);
        completion.state = .active;
        self.timers.insert(&completion.operation.timer);
    }

    self.time.update();

    const now_timer: Timer = .{ .next = self.time.now, .ms = 0, .completion = undefined };
    while (self.timers.peek()) |t| {
        if (!Timer.less({}, t, &now_timer)) break;

        assert(self.timers.deleteMin().? == t);

        const completion = t.completion;
        assert(completion.state == .active);

        completion.state = .idle;
        completion.result = .{ .timer = {} };

        if (completion.callback(self, completion)) {
            t.next = self.time.next_tick(t.ms);
            self.queues.push(.timers, completion);
            completion.state = .submitted;
        }
    }
}

pub fn flushCompletions(self: *Loop) void {
    while (self.queues.pop(.completions)) |completion| {
        assert(completion.state == .completed);
        completion.state = .idle;

        if (completion.callback(self, completion)) {
            self.submit(completion);
        }
    }
}

pub fn flushCancelations(self: *Loop) void {
    while (self.queues.pop(.cancellations)) |c| {
        _ = c.callback(self, c);
    }
}

pub fn flushCanceled(self: *Loop, kevents: []Kevent) usize {
    var submitted: usize = 0;

    while (submitted < kevents.len) {
        const event = &kevents[submitted];
        const completion = self.queues.pop(.canceling) orelse break;
        submitted += 1;

        assert(completion.state == .canceled);
        self.inflight -= 1;

        completion.kevent(event);
        event.flags = std.c.EV.DELETE;
        completion.canceled();
        self.queues.push(.completions, completion);
    }

    return submitted;
}

pub fn flush_submissions(self: *Loop, kevents: []Kevent) usize {
    var active: usize = 0;

    while (active < kevents.len) {
        const completion = self.queues.pop(.submissions) orelse break;

        assert(completion.state == .submitted or completion.state == .completed);
        if (completion.state == .completed) {
            self.queues.push(.completions, completion);
            continue;
        }

        const event = &kevents[active];
        completion.kevent(event);
        completion.state = .active;
        active += 1;
    }

    return active;
}

fn kevent(
    kq: posix.fd_t,
    changelist: []const Kevent,
    eventlist: []Kevent,
    timeout: ?*const posix.timespec,
) !usize {
    while (true) {
        const rc = std.c.kevent64(
            kq,
            changelist.ptr,
            @intCast(changelist.len),
            eventlist.ptr,
            @intCast(eventlist.len),
            .{},
            timeout,
        );

        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .ACCES => return error.AccessDenied,
            .NOENT => return error.EventNotFound,
            .NOMEM => return error.SystemResources,
            else => return error.Unexpected,
        }
    }
}

pub fn submit(
    self: *Loop,
    completion: *Completion,
) void {
    assert(completion.operation != .timer);
    completion.state = .submitted;
    self.queues.push(.submissions, completion);
}

pub fn complete(
    self: *Loop,
    completion: *Completion,
) void {
    completion.state = .completed;
    self.queues.push(.completions, completion);
}

pub fn cancel(
    self: *Loop,
    completion: *Completion,
) void {
    completion.state = .submitted;
    self.queues.push(.cancellations, completion);
}

pub fn mach(
    self: *Loop,
    completion: *Completion,
    function: anytype,
    context: anytype,
    data: MachPort,
) void {
    completion.mach(function, context, data);
    self.submit(completion);
}

pub fn await(
    self: *Loop,
    completion: *Completion,
    function: anytype,
    context: anytype,
) !Waker {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn complete(ctx: Context, c: *Completion, res: Loop.Result) bool {
            drain(c.operation.machport.port);

            return @call(.always_inline, function, .{ ctx, res.machport });
        }
        fn drain(port: posix.system.mach_port_name_t) void {
            var message: struct {
                header: system.mach_msg_header_t,
            } = undefined;

            while (true) {
                switch (system.mach_msg(
                    &message.header,
                    .{ .RCV = .{ .TIMEOUT = true } },
                    0,
                    @sizeOf(@TypeOf(message)),
                    port,
                    system.MACH.MSG.TIMEOUT_NONE,
                    system.MACH.PORT.NULL,
                )) {
                    .RCV_TIMED_OUT => return,
                    .SUCCESS => {},
                    .RCV_TOO_LARGE => {},
                    else => |err| {
                        log.warn("mach msg drain err, may duplicate async wakeups err={}", .{err});
                        return;
                    },
                }
            }
        }
    };

    const mach_self = system.mach_task_self();
    var mach_port: system.mach_port_name_t = undefined;
    if (system.mach_port_allocate(
        mach_self,
        system.MACH.PORT.RIGHT.RECEIVE,
        &mach_port,
    ) != 0) {
        return error.MachPortAllocFailed;
    }
    errdefer _ = system.mach_port_deallocate(mach_self, mach_port);

    if (system.mach_port_insert_right(
        mach_self,
        mach_port,
        mach_port,
        system.MACH.MSG.TYPE.MAKE_SEND,
    ) != 0) {
        return error.MachPortAllocFailed;
    }

    const mach_port_limits = extern struct { mpl_qlimit: system.natural_t };
    const MACH_PORT_LIMITS_INFO = 1;

    const Mach = struct {
        const mach_port_flavor_t = c_int;

        extern "c" fn mach_port_set_attributes(
            task: system.ipc_space_t,
            name: system.mach_port_name_t,
            flavor: mach_port_flavor_t,
            info: *anyopaque,
            count: system.mach_msg_type_number_t,
        ) posix.system.kern_return_t;
    };
    var limits: mach_port_limits = .{ .mpl_qlimit = 1 };
    if (Mach.mach_port_set_attributes(
        mach_self,
        mach_port,
        MACH_PORT_LIMITS_INFO,
        &limits,
        @sizeOf(@TypeOf(limits)),
    ) != 0) return error.MachPortAllocFailed;

    self.mach(
        completion,
        TypeErased.complete,
        context,
        .{ .port = mach_port, .buffer = .{ .array = undefined } },
    );

    return .{ .port = mach_port };
}

pub const Waker = struct {
    port: system.mach_port_name_t,

    pub fn wake(self: *const Waker) !void {
        var msg: posix.system.mach_msg_header_t = .{
            .msgh_bits = @intFromEnum(system.MACH.MSG.TYPE.COPY_SEND),
            .msgh_size = @sizeOf(posix.system.mach_msg_header_t),
            .msgh_remote_port = self.port,
            .msgh_local_port = system.MACH.PORT.NULL,
            .msgh_voucher_port = undefined,
            .msgh_id = undefined,
        };

        switch (system.mach_msg(
            &msg,
            .{ .SEND = .{ .TIMEOUT = true, .MSG = true } },
            msg.msgh_size,
            0,
            system.MACH.PORT.NULL,
            @enumFromInt(0),
            system.MACH.PORT.NULL,
        )) {
            .SUCCESS => {},
            .SEND_NO_BUFFER => {},
            .SEND_TIMED_OUT => {},
            .SEND_INVALID_DEST => |e| {
                log.debug("mach msg err={}", .{e});
            },
            else => |e| {
                log.warn("mach msg err={}", .{e});
                return error.MachMsgFailed;
            },
        }
    }

    pub fn close(self: *const Waker) void {
        _ = system.mach_port_deallocate(
            posix.system.mach_task_self(),
            self.port,
        );
    }
};

pub const ReadBuffer = union(enum) {
    slice: []u8,
    array: [32]u8,
};

pub const MachPort = struct {
    port: posix.system.mach_port_name_t,
    buffer: ReadBuffer,
};

pub const Operation = union(OperationType) {
    noop: void,
    machport: MachPort,
    cancel: *Completion,
    timer: Timer,
};

const OperationType = enum {
    noop,
    machport,
    cancel,
    timer,
};

const Canceled = error{Canceled};

pub const Result = union(OperationType) {
    noop: void,
    machport: Canceled!void,
    cancel: void,
    timer: Canceled!void,
};

const State = enum {
    idle,
    submitted,
    canceled,
    active,
    completed,
};

pub const Completion = struct {
    pub const noop: Completion = .{
        .operation = .noop,
        .context = undefined,
        .callback = noopCallback,
        .state = .idle,
    };

    operation: Operation,
    result: ?Result = null,

    context: *anyopaque,
    callback: *const fn (loop: *Loop, completion: *Completion) bool,

    next: ?*Completion = null,

    state: State,

    pub fn noopCallback(_: *Loop, _: *Completion) bool {
        return false;
    }

    pub fn set(
        completion: *Completion,
        callback: anytype,
        context: anytype,
        comptime op_tag: meta.Tag(Operation),
        op_data: @FieldType(Operation, @tagName(op_tag)),
        resolver: anytype,
    ) void {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(_: *Loop, _completion: *Completion) bool {
                if (_completion.result == null) {
                    _completion.result = @call(.always_inline, resolver, .{@field(_completion.operation, @tagName(op_tag))});
                }

                const _context: Context = @ptrCast(@alignCast(_completion.context));
                return @call(.always_inline, callback, .{ _context, _completion, _completion.result.? });
            }
        };

        completion.* = .{
            .state = .idle,
            .operation = @unionInit(Operation, @tagName(op_tag), op_data),
            .context = context,
            .callback = TypeErased.complete,
        };
    }

    pub fn canceled(self: *Completion) void {
        self.state = .completed;
        switch (self.operation) {
            .noop, .cancel => {},
            .machport => self.result = .{ .machport = error.Canceled },
            .timer => self.result = .{ .timer = error.Canceled },
        }
    }

    pub fn kevent(self: *Completion, event: *Kevent) void {
        switch (self.operation) {
            .cancel, .noop, .timer => panic(
                "{s} operation reached the submissions queueu",
                .{@tagName(self.operation)},
            ),
            .machport => |m| {
                const buffer: []u8 = switch (m.buffer) {
                    .slice => |slice| slice,
                    .array => |array| @constCast(&array),
                };
                event.* = .{
                    .ident = @intCast(m.port),
                    .filter = std.c.EVFILT.MACHPORT,
                    .flags = posix.system.EV.ADD | posix.system.EV.ENABLE | posix.system.EV.ONESHOT,
                    .fflags = @bitCast(std.c.MACH.RCV{ .MSG = true }),
                    .data = 0,
                    .udata = @intFromPtr(self),
                    .ext = .{ @intFromPtr(buffer.ptr), buffer.len },
                };
            },
        }
    }

    pub fn cancel(
        self: *Completion,
        target: *Completion,
    ) void {
        const TypeErased = struct {
            fn complete(loop: *Loop, _completion: *Completion) bool {
                const _target = _completion.operation.cancel;

                switch (_target.state) {
                    .canceled => {},
                    .idle => {
                        if (_target.operation == .timer) {
                            _target.canceled();
                        }
                    },
                    .completed, .submitted => _target.canceled(),
                    .active => {
                        switch (_target.operation) {
                            .timer => |*timer_op| {
                                loop.timers.remove(timer_op);
                                _target.canceled();
                                loop.queues.push(.completions, _target);
                            },
                            else => {
                                _target.state = .canceled;
                                loop.queues.push(.canceling, _target);
                            },
                        }
                    },
                }

                _completion.* = .noop;

                return false;
            }
        };

        self.* = .{
            .operation = .{ .cancel = target },
            .context = undefined,
            .callback = TypeErased.complete,
            .state = .idle,
        };
    }

    pub fn mach(
        completion: *Completion,
        function: anytype,
        context: anytype,
        data: MachPort,
    ) void {
        completion.set(
            function,
            context,
            .machport,
            data,
            struct {
                fn machport(_: MachPort) Result {
                    return .{ .machport = {} };
                }
            }.machport,
        );
    }

    pub fn timer(
        completion: *Completion,
        callback: anytype,
        context: anytype,
        ms: u64,
    ) void {
        completion.set(
            callback,
            context,
            .timer,
            .{
                .next = undefined,
                .completion = completion,
                .ms = ms,
            },
            struct {
                fn timer(_: Timer) Result {
                    return .{ .timer = {} };
                }
            }.timer,
        );
    }
};

const Timer = struct {
    next: posix.timespec,
    completion: *Completion,

    heap: heap.IntrusiveField(Timer) = .{},
    ms: u64,

    fn less(_: void, a: *const Timer, b: *const Timer) bool {
        return a.ns() < b.ns();
    }

    fn ns(self: *const Timer) u64 {
        return ns_from_timespec(self.next);
    }

    fn ns_from_timespec(ts: posix.timespec) u64 {
        assert(ts.sec >= 0);
        assert(ts.nsec >= 0);

        const max = std.math.maxInt(u64);
        const s_ns = std.math.mul(
            u64,
            @as(u64, @intCast(ts.sec)),
            std.time.ns_per_s,
        ) catch return max;
        return std.math.add(u64, s_ns, @as(u64, @intCast(ts.nsec))) catch
            return max;
    }
};

pub fn timer(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    context: anytype,
    ms: u64,
) void {
    completion.timer(callback, context, ms);
    self.submit_timer(completion);
}

pub fn submit_timer(self: *Loop, completion: *Completion) void {
    completion.state = .submitted;
    const c_timer = completion.operation.timer;
    completion.operation.timer.next = self.time.next_tick(c_timer.ms);
    self.queues.push(.timers, completion);
}

pub const Time = struct {
    now: posix.timespec,

    pub fn update(self: *Time) void {
        switch (posix.errno(posix.system.clock_gettime(posix.CLOCK.MONOTONIC, &self.now))) {
            .SUCCESS => {},
            else => {},
        }
    }

    pub fn next_tick(self: *Time, next_ms: u64) posix.timespec {
        const max: posix.timespec = .{
            .sec = std.math.maxInt(isize),
            .nsec = std.math.maxInt(isize),
        };

        const next_s = std.math.cast(isize, next_ms / std.time.ms_per_s) orelse
            return max;
        const next_ns = std.math.cast(
            isize,
            (next_ms % std.time.ms_per_s) * std.time.ns_per_ms,
        ) orelse return max;

        self.update();

        return .{
            .sec = std.math.add(isize, self.now.sec, next_s) catch
                return max,
            .nsec = self.now.nsec + next_ns,
        };
    }
};

test "mach port" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    const mach_self = posix.system.mach_task_self();
    var mach_port: posix.system.mach_port_name_t = undefined;
    try testing.expectEqual(posix.system.mach_msg_return_t.SUCCESS, @as(
        posix.system.mach_msg_return_t,
        @enumFromInt(
            posix.system.mach_port_allocate(
                mach_self,
                posix.system.MACH.PORT.RIGHT.RECEIVE,
                &mach_port,
            ),
        ),
    ));
    defer _ = posix.system.mach_port_deallocate(mach_self, mach_port);

    var called = false;
    var buffer: [@sizeOf(posix.system.mach_msg_header_t)]u8 = undefined;
    var completion: Completion = .noop;

    loop.mach(
        &completion,
        struct {
            fn machport(_called: *bool, _: *Completion, res: Result) bool {
                if (res.machport != error.Canceled) {
                    _called.* = true;
                }
                return false;
            }
        }.machport,
        &called,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    // Tick so we submit... should not call since we never sent.
    try loop.run(.no_wait);
    try testing.expect(!called);

    // Send a message to the port
    var msg: posix.system.mach_msg_header_t = .{
        .msgh_bits = @intFromEnum(posix.system.MACH.MSG.TYPE.MAKE_SEND_ONCE),
        .msgh_size = @sizeOf(posix.system.mach_msg_header_t),
        .msgh_remote_port = mach_port,
        .msgh_local_port = posix.system.MACH.PORT.NULL,
        .msgh_voucher_port = undefined,
        .msgh_id = undefined,
    };

    try testing.expectEqual(
        posix.system.mach_msg_return_t.SUCCESS,
        posix.system.mach_msg(
            &msg,
            .{ .SEND = .{} },
            msg.msgh_size,
            0,
            posix.system.MACH.PORT.NULL,
            posix.system.MACH.MSG.TIMEOUT_NONE,
            posix.system.MACH.PORT.NULL,
        ),
    );
    // We should receive now!
    try loop.run(.until_done);
    try testing.expect(called);

    // We should not receive again
    called = false;
    loop.mach(
        &completion,
        struct {
            fn machport(_called: *bool, _: *Completion, res: Result) bool {
                if (res.machport != error.Canceled) {
                    _called.* = true;
                }
                return false;
            }
        }.machport,
        &called,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    // Tick so we submit... should not call since we never sent.
    try loop.run(.no_wait);
    try loop.run(.no_wait);
    try testing.expect(!called);
}

test "cancel mach port" {
    const io = testing.io;
    const c = std.c;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    const mach_self = c.mach_task_self();
    var mach_port: c.mach_port_name_t = undefined;
    try testing.expectEqual(@as(c.kern_return_t, 0), c.mach_port_allocate(
        mach_self,
        c.MACH.PORT.RIGHT.RECEIVE,
        &mach_port,
    ));
    defer _ = c.mach_port_deallocate(mach_self, mach_port);

    var buffer: [@sizeOf(c.mach_msg_header_t)]u8 = undefined;
    var completion: Completion = .noop;
    var called = false;

    loop.mach(
        &completion,
        struct {
            fn machport(_called: *bool, _: *Completion, res: Result) bool {
                if (res.machport != error.Canceled) {
                    _called.* = true;
                }
                return false;
            }
        }.machport,
        &called,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    for (0..10) |_| try loop.run(.no_wait);
    try testing.expect(!called);

    var cancellation: Completion = .noop;

    cancellation.cancel(&completion);
    loop.cancel(&cancellation);

    for (0..10) |_| try loop.run(.no_wait);

    try testing.expect(!called);

    // Send a message to the port
    var msg: posix.system.mach_msg_header_t = .{
        .msgh_bits = @intFromEnum(posix.system.MACH.MSG.TYPE.MAKE_SEND_ONCE),
        .msgh_size = @sizeOf(posix.system.mach_msg_header_t),
        .msgh_remote_port = mach_port,
        .msgh_local_port = posix.system.MACH.PORT.NULL,
        .msgh_voucher_port = undefined,
        .msgh_id = undefined,
    };

    try testing.expectEqual(
        posix.system.mach_msg_return_t.SUCCESS,
        posix.system.mach_msg(
            &msg,
            .{ .SEND = .{} },
            msg.msgh_size,
            0,
            posix.system.MACH.PORT.NULL,
            posix.system.MACH.MSG.TIMEOUT_NONE,
            posix.system.MACH.PORT.NULL,
        ),
    );
    // We should receive now!
    for (0..10) |_| try loop.run(.no_wait);
    try testing.expect(!called);
}

test "timer completes" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    var called = false;
    var completion: Completion = .noop;

    loop.timer(
        &completion,
        struct {
            fn timer(_called: *bool, _: *Completion, res: Result) bool {
                res.timer catch return false;
                _called.* = true;
                return false;
            }
        }.timer,
        &called,
        0,
    );

    try loop.run(.until_done);

    try testing.expect(called);
}

test "timer rearms when callback returns true" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    var calls: u8 = 0;
    var completion: Completion = .noop;

    loop.timer(
        &completion,
        struct {
            fn timer(_calls: *u8, _: *Completion, res: Result) bool {
                res.timer catch return false;
                _calls.* += 1;
                return _calls.* < 2;
            }
        }.timer,
        &calls,
        0,
    );

    try loop.run(.until_done);

    try testing.expectEqual(@as(u8, 2), calls);
}

test "cancel timer" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    var timer_called = false;
    var timer_completion: Completion = .noop;

    loop.timer(
        &timer_completion,
        struct {
            fn timer(_called: *bool, _: *Completion, res: Result) bool {
                if (res.timer == error.Canceled) {
                    return false;
                }

                _called.* = true;
                return false;
            }
        }.timer,
        &timer_called,
        std.time.ms_per_s,
    );

    try loop.run(.no_wait);

    var cancel_completion: Completion = .noop;
    cancel_completion.cancel(
        &timer_completion,
    );
    loop.cancel(&cancel_completion);

    try loop.run(.until_done);

    try testing.expect(!timer_called);
}

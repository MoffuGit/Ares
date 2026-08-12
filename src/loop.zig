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

pub const Loop = @This();

kq: posix.fd_t,

time: Time,

scheduler: *Scheduler,
queues: MultiQueue(union(enum) {
    timers: Completion,
    canceling: Completion,
    submissions: Completion,
    completions: Completion,
    cancellations: Completion,
}),
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
        .inflight = 0,
        .stopped = false,
        .timers = .{ .context = {} },
        .queues = undefined,
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
        .no_wait => try self.flush(),
        .until_done => while (!self.done()) try self.flush(),
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

pub fn flush(self: *Loop) !void {
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

            c.state = .completed;
            self.queues.push(.completions, c);
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
            assert(completion.operation != .timer);
            completion.state = .submitted;
            self.queues.push(.submissions, completion);
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
        .callback = noopCallback,
        .state = .idle,
    };

    operation: Operation,
    result: ?Result = null,

    callback: *const fn (loop: *Loop, completion: *Completion) bool,

    next: ?*Completion = null,

    state: State,

    pub fn noopCallback(_: *Loop, _: *Completion) bool {
        return false;
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

    pub fn canceled(self: *Completion) void {
        self.state = .completed;
        switch (self.operation) {
            .noop, .cancel => {},
            .machport => self.result = .{ .machport = error.Canceled },
            .timer => self.result = .{ .timer = error.Canceled },
        }
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

pub fn submit(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    comptime op_tag: meta.Tag(Operation),
    op_data: @FieldType(Operation, @tagName(op_tag)),
    resolver: anytype,
) void {
    const TypeErased = struct {
        fn complete(loop: *Loop, _completion: *Completion) bool {
            if (_completion.result == null) {
                _completion.result = @call(.always_inline, resolver, .{ @field(_completion.operation, @tagName(op_tag)), loop });
            }

            return @call(.always_inline, callback, .{ _completion, _completion.result.? });
        }
    };

    completion.* = .{
        .state = .idle,
        .operation = @unionInit(Operation, @tagName(op_tag), op_data),
        .callback = TypeErased.complete,
    };

    switch (op_tag) {
        .cancel => {
            completion.state = .submitted;
            self.queues.push(.cancellations, completion);
        },
        .machport => {
            completion.state = .submitted;
            self.queues.push(.submissions, completion);
        },
        .timer => {
            completion.state = .submitted;
            const c_timer = completion.operation.timer;
            completion.operation.timer.next = self.time.next_tick(c_timer.ms);
            self.queues.push(.timers, completion);
        },
        .noop => unreachable,
    }
}

pub fn mach(
    self: *Loop,
    completion: *Completion,
    function: anytype,
    data: MachPort,
) void {
    self.submit(
        completion,
        function,
        .machport,
        data,
        struct {
            fn machport(_: MachPort, _: *Loop) Result {
                return .{ .machport = {} };
            }
        }.machport,
    );
}

pub fn cancel(
    self: *Loop,
    completion: *Completion,
    function: anytype,
    target: *Completion,
) void {
    self.submit(
        completion,
        function,
        .cancel,
        target,
        struct {
            fn resolver(t: *Completion, loop: *Loop) Result {
                switch (t.state) {
                    .canceled => {},
                    .idle => {
                        if (t.operation == .timer) {
                            t.canceled();
                        }
                    },
                    .completed, .submitted => t.canceled(),
                    .active => {
                        switch (t.operation) {
                            .timer => |*timer_op| {
                                loop.timers.remove(timer_op);
                                t.canceled();
                                loop.queues.push(.completions, t);
                            },
                            else => {
                                t.state = .canceled;
                                loop.queues.push(.canceling, t);
                            },
                        }
                    },
                }

                return .cancel;
            }
        }.resolver,
    );
}

pub fn timer(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    ms: u64,
) void {
    self.submit(
        completion,
        callback,
        .timer,
        .{
            .next = undefined,
            .completion = completion,
            .ms = ms,
        },
        struct {
            fn timer(_: Timer, _: *Loop) Result {
                return .{ .timer = {} };
            }
        }.timer,
    );
}

pub fn await(
    self: *Loop,
    completion: *Completion,
    function: anytype,
) !Waker {
    const TypeErased = struct {
        fn complete(c: *Completion, res: Loop.Result) bool {
            drain(c.operation.machport.port);

            return @call(.always_inline, function, .{ c, res.machport });
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

    const MachTest = struct {
        called: bool = false,
        completion: Completion = .noop,

        fn machport(c: *Completion, res: Result) bool {
            const parent: *@This() = @fieldParentPtr("completion", c);
            if (res.machport != error.Canceled) {
                parent.called = true;
            }
            return false;
        }
    };

    var mach_test: MachTest = .{};
    var buffer: [@sizeOf(posix.system.mach_msg_header_t)]u8 = undefined;

    loop.mach(
        &mach_test.completion,
        MachTest.machport,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    try loop.run(.no_wait);
    try testing.expect(!mach_test.called);

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

    try loop.run(.until_done);
    try testing.expect(mach_test.called);

    mach_test.called = false;
    loop.mach(
        &mach_test.completion,
        MachTest.machport,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    try loop.run(.no_wait);
    try loop.run(.no_wait);
    try testing.expect(!mach_test.called);
}

test "cancel mach port" {
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

    const MachTest = struct {
        called: bool = false,
        completion: Completion = .noop,

        fn machport(c: *Completion, res: Result) bool {
            const parent: *@This() = @fieldParentPtr("completion", c);
            if (res.machport != error.Canceled) {
                parent.called = true;
            }
            return false;
        }
    };

    var mach_test: MachTest = .{};
    var buffer: [@sizeOf(posix.system.mach_msg_header_t)]u8 = undefined;

    loop.mach(
        &mach_test.completion,
        MachTest.machport,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    for (0..10) |_| try loop.run(.no_wait);
    try testing.expect(!mach_test.called);

    const Cancelation = struct {
        completion: Completion = .noop,
        called: bool = false,

        pub fn callback(c: *Completion, res: Result) bool {
            assert(res == .cancel);
            const parent: *@This() = @fieldParentPtr("completion", c);
            parent.called = true;
            return false;
        }
    };
    var cancellation: Cancelation = .{};

    loop.cancel(&cancellation.completion, Cancelation.callback, &mach_test.completion);

    for (0..10) |_| try loop.run(.no_wait);

    try testing.expect(!mach_test.called);
    try testing.expect(cancellation.called);

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
    try testing.expect(!mach_test.called);
}

test "timer completes" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    const TimerTest = struct {
        called: bool = false,
        completion: Completion = .noop,

        fn timer(c: *Completion, res: Result) bool {
            res.timer catch return false;
            const parent: *@This() = @fieldParentPtr("completion", c);
            parent.called = true;
            return false;
        }
    };

    var timer_test: TimerTest = .{};

    loop.timer(
        &timer_test.completion,
        TimerTest.timer,
        0,
    );

    try loop.run(.until_done);

    try testing.expect(timer_test.called);
}

test "timer rearms when callback returns true" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    const TimerTest = struct {
        times: u8 = 0,
        completion: Completion = .noop,

        fn timer(c: *Completion, res: Result) bool {
            res.timer catch return false;
            const parent: *@This() = @fieldParentPtr("completion", c);
            parent.times += 1;
            return parent.times < 2;
        }
    };

    var timer_test: TimerTest = .{};

    loop.timer(
        &timer_test.completion,
        TimerTest.timer,
        0,
    );

    try loop.run(.until_done);

    try testing.expectEqual(@as(u8, 2), timer_test.times);
}

test "cancel timer" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(undefined, io);
    defer loop.deinit();

    const TimerTest = struct {
        called: bool = false,
        completion: Completion = .noop,

        fn timer(c: *Completion, res: Result) bool {
            res.timer catch return false;
            const parent: *@This() = @fieldParentPtr("completion", c);
            parent.called = true;
            return false;
        }
    };

    var timer_test: TimerTest = .{};

    loop.timer(
        &timer_test.completion,
        TimerTest.timer,
        std.time.ms_per_s,
    );

    try loop.run(.no_wait);

    const Cancelation = struct {
        completion: Completion = .noop,
        called: bool = false,

        pub fn callback(c: *Completion, res: Result) bool {
            assert(res == .cancel);
            const parent: *@This() = @fieldParentPtr("completion", c);
            parent.called = true;
            return false;
        }
    };
    var cancellation: Cancelation = .{};

    loop.cancel(&cancellation.completion, Cancelation.callback, &timer_test.completion);

    try loop.run(.until_done);

    try testing.expect(!timer_test.called);
    try testing.expect(cancellation.called);
}

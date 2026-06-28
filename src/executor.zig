// const Queues = union(enum) {
//     completions: Task,
//     submissions: Task,
// };
//
// pub const Executor = struct {
//     _await: Await,
//     scheduler: Scheduler,
//     mutex: Io.Mutex,
//     tasks: datastruct.multi_mpsc.MultiIntrusive(Queues),
//
//     future: Io.Future(void),
//     io: Io,
//
//     arena: Allocator,
//     gpa: Allocator,
//
//     pub fn init(self: *@This(), arena: Allocator, gpa: Allocator, io: Io) !void {
//         self.* = .{
//             .gpa = gpa,
//             .scheduler = undefined,
//             ._await = undefined,
//             .mutex = .init,
//             .tasks = undefined,
//             .arena = arena,
//             .io = io,
//             .future = undefined,
//         };
//
//         try self.scheduler.init(arena, io);
//         self.tasks.init();
//         self._await = try self.await(
//             Scheduler.stop,
//             .{&self.scheduler},
//         );
//
//         self.future = try io.concurrent(Executor.run, .{self});
//     }
//
//     pub fn deinit(self: *@This()) void {
//         if (builtin.mode == .Debug) self.io.sleep(.fromMilliseconds(50), .real) catch {};
//
//         self._await.@"1".wake() catch |err| {
//             std.log.err("Error while stopping a worker: {}", .{err});
//         };
//
//         _ = self.future.await(self.io);
//
//         self._await.@"0".cancel();
//
//         self.scheduler.deinit();
//     }
//
//     pub fn @"defer"(
//         self: *@This(),
//         function: anytype,
//         context: anytype,
//     ) Handler {
//         self.mutex.lockUncancelable(self.io);
//         defer self.mutex.unlock(self.io);
//
//         const handler = self.scheduler.@"defer"(function, context);
//         self.tasks.push(.completions, handler.id);
//         return handler;
//     }
//
//     pub fn await(
//         self: *@This(),
//         function: anytype,
//         context: anytype,
//     ) !Await {
//         self.mutex.lockUncancelable(self.io);
//         defer self.mutex.unlock(self.io);
//
//         const result = try self.scheduler.await(function, context);
//         self.tasks.push(.submissions, result.@"0".task);
//         return result;
//     }
//
//     fn run(self: *@This()) void {
//         _ = self;
//         // while (!self.scheduler.loop.done()) {
//         //     while (self.tasks.pop(.completions)) |task| {
//         //         self.scheduler.addCompletion(task);
//         //     }
//         //     while (self.tasks.pop(.submissions)) |task| {
//         //         self.scheduler.addSubmission(task);
//         //     }
//         //     self.scheduler.run(.no_wait);
//         //
//         //     self.io.sleep(.fromNanoseconds(100), .real) catch {};
//         // }
//     }
// };

// pub const Group = struct {
//     const State = enum(u8) { open, closing, drained };
//     const Node = struct {
//         handler: Handler,
//         next: ?*Node = null,
//     };
//
//     executor: *Executor,
//     pending: atomic.Value(usize),
//     state: atomic.Value(State),
//     alloc: heap.ArenaAllocator,
//     handlers: ?*Node,
//     io: Io,
//     mutex: Io.Mutex,
//
//     pub fn init(executor: *Executor) Group {
//         return .{
//             .io = executor.io,
//             .mutex = .init,
//             .executor = executor,
//             .pending = .init(0),
//             .state = .init(.open),
//             .alloc = .init(executor.gpa),
//             .handlers = null,
//         };
//     }
//
//     pub fn arena(self: *Group) Allocator {
//         return self.alloc.allocator();
//     }
//
//     pub fn @"defer"(
//         self: *Group,
//         function: anytype,
//         context: anytype,
//     ) void {
//         const Context = @TypeOf(context);
//         const Wrapper = struct {
//             fn complete(group: *Group, user_context: Context, res: anyerror!void) bool {
//                 const rearm = @call(.auto, function, user_context ++ .{ group, res });
//                 if (!rearm) group.finishTask();
//                 return rearm;
//             }
//         };
//
//         _ = self.pending.fetchAdd(1, .monotonic);
//
//         const handler = self.executor.scheduler.@"defer"(Wrapper.complete, .{ self, context });
//         self.join(handler);
//     }
//
//     pub fn await(
//         self: *Group,
//         function: anytype,
//         context: anytype,
//     ) !Waker {
//         const Context = @TypeOf(context);
//         const Wrapper = struct {
//             group: *Group,
//             user_context: Context,
//
//             fn complete(group: *Group, user_context: Context, result: anyerror!void) bool {
//                 const rearm = @call(.auto, function, user_context ++ .{ group, result });
//                 if (!rearm) group.finishTask();
//                 return rearm;
//             }
//         };
//
//         _ = self.pending.fetchAdd(1, .monotonic);
//
//         const handler, const waker = try self.executor.scheduler.await(Wrapper.complete, .{ self, context });
//         self.join(handler);
//         return waker;
//     }
//
//     pub fn close(self: *Group) void {
//         var node = self.handlers;
//         self.handlers = null;
//         while (node) |current| : (node = current.next) {
//             current.handler.detach();
//         }
//
//         self.state.store(.closing, .release);
//         if (self.pending.load(.acquire) == 0) self.deinit();
//     }
//
//     pub fn cancel(self: *Group) void {
//         var node = self.handlers;
//         self.handlers = null;
//         while (node) |current| : (node = current.next) {
//             current.handler.cancel();
//         }
//
//         self.state.store(.closing, .release);
//         if (self.pending.load(.acquire) == 0) self.deinit();
//     }
//
//     pub fn closing(self: *Group) bool {
//         return self.state.load(.acquire) != .open;
//     }
//
//     fn join(self: *Group, handler: Handler) void {
//         self.mutex.lockUncancelable(self.io);
//         defer self.mutex.unlock(self.io);
//
//         const node = self.alloc.allocator().create(Node) catch {
//             @panic("BackgroundExecutor Group Handlers Overflow");
//         };
//         node.* = .{ .handler = handler, .next = self.handlers };
//         self.handlers = node;
//     }
//
//     fn finishTask(self: *Group) void {
//         const old = self.pending.fetchSub(1, .acq_rel);
//         debug.assert(old > 0);
//
//         if (old == 1 and self.state.load(.acquire) == .closing) {
//             return self.deinit();
//         }
//     }
//
//     fn deinit(self: *Group) void {
//         if (self.state.swap(.drained, .acq_rel) == .drained) return;
//
//         self.alloc.deinit();
//
//         self.executor.reclaimGroup(self);
//     }
// };

// fn testDeferTaskGroup(calls: *u32, _: *Group, result: anyerror!void) bool {
//     result catch return false;
//     calls.* += 1;
//     return false;
// }
//
// test "group defer completes" {
//     const gpa = testing.allocator;
//     const io = testing.io;
//
//     var alloc = heap.ArenaAllocator.init(gpa);
//     defer alloc.deinit();
//
//     const arena = alloc.allocator();
//
//     var executor: Executor = undefined;
//     try executor.init(arena, gpa, io);
//     defer executor.deinit();
//
//     var calls: u32 = 0;
//     const group = executor.group();
//
//     group.@"defer"(testDeferTaskGroup, .{&calls});
//     group.close();
//
//     try io.sleep(.fromMilliseconds(10), .real);
//
//     try testing.expectEqual(@as(u32, 1), calls);
// }

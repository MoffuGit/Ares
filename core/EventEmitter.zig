const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn EventEmitter(comptime Event: type) type {
    if (@typeInfo(Event) != .@"union") {
        @compileError("EventType must be an union");
    }

    return struct {
        const Self = @This();

        pub const Tag = std.meta.Tag(Event);

        pub const Listener = struct {
            ctx: *anyopaque,
            handle: *const fn (ctx: *anyopaque, event: Event) void,
        };

        const ListenerList = struct {
            items: std.ArrayListUnmanaged(Listener) = .{},
            mutex: std.Thread.Mutex = .{},
        };

        allocator: Allocator,
        listeners: std.EnumMap(Tag, ListenerList),

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .listeners = std.EnumMap(Tag, ListenerList).init(.{}),
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.listeners.iterator();
            while (iter.next()) |entry| {
                entry.value.items.deinit(self.allocator);
            }
        }

        pub fn on(self: *Self, event: Tag, listener: Listener) !void {
            const list_ptr = self.listeners.getPtr(event) orelse {
                self.listeners.put(event, .{});
                return self.on(event, listener);
            };

            list_ptr.mutex.lock();
            defer list_ptr.mutex.unlock();

            try list_ptr.items.append(self.allocator, listener);
        }

        pub fn off(self: *Self, event: Tag, listener: Listener) void {
            const list_ptr = self.listeners.getPtr(event) orelse return;

            list_ptr.mutex.lock();
            defer list_ptr.mutex.unlock();

            var i: usize = 0;
            while (i < list_ptr.items.items.len) {
                const item = list_ptr.items.items[i];
                if (item.ctx == listener.ctx and item.handle == listener.handle) {
                    _ = list_ptr.items.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        pub fn emit(self: *Self, event: Event) void {
            const tag = std.meta.activeTag(event);
            const list_ptr = self.listeners.getPtr(tag) orelse return;

            list_ptr.mutex.lock();
            defer list_ptr.mutex.unlock();

            for (list_ptr.items.items) |listener| {
                listener.handle(listener.ctx, event);
            }
        }
    };
}

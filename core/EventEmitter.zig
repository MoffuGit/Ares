const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn EventEmitter(comptime Event: type) type {
    if (@typeInfo(Event) != .@"union") {
        @compileError("EventType must be an union");
    }

    const Tag = std.meta.Tag(Event);

    return struct {
        const Self = @This();

        pub const Listener = struct {
            ctx: *anyopaque,
            handle: *const fn (ctx: *anyopaque) void,
        };

        allocator: Allocator,
        listeners: std.EnumMap(Tag, std.ArrayListUnmanaged(Listener)),

        pub fn init(allocator: Allocator) Self {
            return .{
                .allocator = allocator,
                .listeners = std.EnumMap(Tag, std.ArrayListUnmanaged(Listener)).init(.{}),
            };
        }

        pub fn deinit(self: *Self) void {
            var iter = self.listeners.iterator();
            while (iter.next()) |entry| {
                entry.value.deinit(self.allocator);
            }
        }

        pub fn on(self: *Self, event: Event, listener: Listener) !void {
            const tag = std.meta.activeTag(event);
            const list_ptr = self.listeners.getPtr(tag) orelse {
                self.listeners.put(tag, .{});
                return self.on(event, listener);
            };

            try list_ptr.append(self.allocator, listener);
        }

        pub fn off(self: *Self, event: Event, listener: Listener) void {
            const tag = std.meta.activeTag(event);
            const list_ptr = self.listeners.getPtr(tag) orelse return;

            var i: usize = 0;
            while (i < list_ptr.items.len) {
                const item = list_ptr.items[i];
                if (item.ctx == listener.ctx and item.handle == listener.handle) {
                    _ = list_ptr.swapRemove(i);
                } else {
                    i += 1;
                }
            }
        }

        pub fn emit(self: *Self, event: Event) void {
            const tag = std.meta.activeTag(event);
            const list_ptr = self.listeners.getPtr(tag) orelse return;

            for (list_ptr.items) |listener| {
                listener.handle(listener.ctx);
            }
        }
    };
}

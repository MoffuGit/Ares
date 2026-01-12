const std = @import("std");
const builtin = @import("builtin");

pub var state: GlobalState = undefined;

pub const xev = @import("xev").Dynamic;

pub const GlobalState = struct {
    const GPA = std.heap.GeneralPurposeAllocator(.{});

    gpa: GPA,
    alloc: std.mem.Allocator,
    logging: Logging,

    pub const Logging = union(enum) {
        disabled: void,
        stderr: void,
    };

    pub fn init(self: *GlobalState) !void {
        self.* = .{
            .gpa = GPA{},
            .alloc = undefined,
            .logging = .{ .stderr = {} },
        };
        errdefer self.deinit();

        self.alloc = self.gpa.allocator();

        std.log.info("GlobalState initialized. Allocator in use.", .{});
    }

    pub fn deinit(self: *GlobalState) void {
        if (self.gpa.deinit() == .leak) {
            std.log.info("We have leaks 🔥", .{});
        }
        std.log.info("GlobalState deinitialized.", .{});
    }
};

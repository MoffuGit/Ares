const std = @import("std");
const state = &@import("global.zig").state;

var counter: i32 = 0;

export fn zig_increment_counter() void {
    counter += 1;
    std.debug.print("Zig: Counter incremented to {}\n", .{counter});
}

export fn zig_decrement_counter() void {
    counter -= 1;
    std.debug.print("Zig: Counter decremented to {}\n", .{counter});
}

export fn zig_get_counter() i32 {
    std.debug.print("Zig: Counter requested, returning {}\n", .{counter});
    return counter;
}

export fn zig_init_counter() void {
    counter = 0;
    std.debug.print("Zig: Counter initialized to {}\n", .{counter});
}

export fn zig_deinit_counter() void {
    std.debug.print("Zig: Counter deinitialized.\n", .{});
}

export fn zig_process_file_path(path_c_str: [*c]const u8) void {
    const allocator = std.heap.page_allocator;

    const path_slice = std.mem.span(path_c_str);
    std.debug.print("Zig: Attempting to open file: {s}\n", .{path_slice});

    var file = std.fs.cwd().openFile(path_slice, .{}) catch |err| {
        std.debug.print("Zig: Error opening file '{s}': {any}\n", .{ path_slice, err });
        return;
    };
    defer file.close();

    var buffer: [1024]u8 = undefined;
    var content = std.ArrayList(u8).initCapacity(allocator, 0) catch {
        return;
    };
    defer content.deinit(allocator);

    while (file.read(buffer[0..])) |bytes_read| {
        if (bytes_read == 0) break;
        content.appendSlice(allocator, buffer[0..bytes_read]) catch {
            std.debug.print("Zig: Out of memory while reading file.\n", .{});
            return;
        };
    } else |err| {
        std.debug.print("Zig: Error reading file '{s}': {any}\n", .{ path_slice, err });
        return;
    }

    std.debug.print("Zig: File content from '{s}':\n```\n{s}\n```\n", .{ path_slice, content.items });
}

pub export fn ares_init(argc: usize, argv: [*][*:0]u8) c_int {
    std.os.argv = argv[0..argc];
    state.init() catch |err| {
        std.log.err("failed to initialize ghostty error={}", .{err});
        return 1;
    };

    return 0;
}

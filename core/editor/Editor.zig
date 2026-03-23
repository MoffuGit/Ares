const Editor = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.screen);

alloc: Allocator,

pub fn init(alloc: Allocator) !Editor {
    return .{
        .alloc = alloc,
    };
}

pub fn deinit(self: *Editor) void {
    _ = self;
}

// pub fn resize(self: *Editor, size: sizepkg.Size) void {
//     self.mutex.lock();
//     defer self.mutex.unlock();
//
//     self.screen.resize(size);
//
//     self.renderer_thread.wakeup.notify() catch {};
// }
//
// pub fn openFile(self: *Editor, pwd: []u8) !void {
//     const cwd = std.fs.cwd();
//     const file = try cwd.openFile(pwd, .{});
//     defer file.close();
//
//     const buf = try self.alloc.alloc(u8, 60 * 1024 * 1024);
//     defer self.alloc.free(buf);
//
//     var reader = file.reader(buf);
//
//     self.mutex.lock();
//     defer self.mutex.unlock();
//
//     self.screen.resetCells();
//
//     while (reader.interface.takeDelimiterExclusive('\n')) |line| {
//         self.screen.addNewLine(line) catch |err| {
//             log.err("error when adding anew line: {}", .{err});
//         };
//     } else |err| if (err != error.EndOfStream) return err;
// }

const Editor = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const SharedState = @import("../SharedState.zig");
const sizepkg = @import("../size.zig");
const Project = @import("../Project.zig");

const log = std.log.scoped(.screen);

alloc: Allocator,
shared_state: *SharedState,
project: *Project,

pub fn init(project: *Project, alloc: Allocator, shared_state: *SharedState) !Editor {
    return .{
        .alloc = alloc,
        .shared_state = shared_state,
        .project = project,
    };
}

pub fn deinit(self: *Editor) void {
    _ = self;
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    self.shared_state.mutex.lock();
    defer self.shared_state.mutex.unlock();

    self.shared_state.screen.resize(size);
}

pub fn selectEntry(self: *Editor, id: u64) !void {
    _ = self;
    _ = id;
    // const cwd = std.fs.cwd();
    // const file = try cwd.openFile(pwd, .{});
    // defer file.close();
    //
    // const buf = try self.alloc.alloc(u8, 60 * 1024 * 1024);
    // defer self.alloc.free(buf);
    //
    // var reader = file.reader(buf);
    //
    // self.mutex.lock();
    // defer self.mutex.unlock();
    //
    // self.screen.resetCells();
    //
    // while (reader.interface.takeDelimiterExclusive('\n')) |line| {
    //     self.screen.addNewLine(line) catch |err| {
    //         log.err("error when adding anew line: {}", .{err});
    //     };
    // } else |err| if (err != error.EndOfStream) return err;
}

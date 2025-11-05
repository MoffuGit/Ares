const SharedState = @This();

const std = @import("std");
const Editor = @import("editor/mod.zig");

editor: *Editor,
mutex: std.Thread.Mutex,

pub fn init(editor: *Editor, mutex: std.Thread.Mutex) !SharedState {
    return .{ .editor = editor, .mutex = mutex };
}

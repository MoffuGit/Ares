pub const Window = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;
const SharedState = @import("../SharedState.zig");
const Buffer = @import("../Buffer.zig");

const Root = @import("Root.zig");

const RendererMailbox = @import("../renderer/Thread.zig").Mailbox;

alloc: Allocator,

//NOTE:
//Maybe an improvement over the current draw technique
//can be adding a tick queue, where you can add an element,
//and set an interval, then, you can check if the queue is empty you stop the
//timer watcher, then on the tick callback the component can ask for a render,
//this can be an event that we send to the window thread

render_wakeup: xev.Async,
render_mailbox: *RendererMailbox,
shared_state: *SharedState,
buffer: Buffer,

root: *Root,

size: vaxis.Winsize,

pub fn init(
    alloc: Allocator,
    render_wakeup: xev.Async,
    render_mailbox: *RendererMailbox,
    shared_state: *SharedState,
) !Window {
    var root = try alloc.create(Root);
    errdefer alloc.destroy(root);

    try root.init();

    var buffer = try Buffer.init(alloc, 0, 0);
    errdefer buffer.deinit(alloc);

    return .{
        .root = root,
        .alloc = alloc,
        .buffer = buffer,
        .render_wakeup = render_wakeup,
        .render_mailbox = render_mailbox,
        .shared_state = shared_state,
        .size = .{
            .cols = 0,
            .rows = 0,
            .x_pixel = 0,
            .y_pixel = 0,
        },
    };
}

pub fn deinit(self: *Window) void {
    self.buffer.deinit(self.alloc);
    self.alloc.destroy(self.root);
}

pub fn draw(self: *Window) !void {
    try self.root.element.update();
    try self.root.element.draw(&self.buffer);

    {
        const shared_state = self.shared_state;
        shared_state.mutex.lock();
        defer shared_state.mutex.unlock();

        @memcpy(shared_state.screen.buf, self.buffer.buf);

        shared_state.render = true;
    }

    try self.render_wakeup.notify();
}

pub fn resize(self: *Window, size: vaxis.Winsize) !void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;

    self.buffer.deinit(self.alloc);
    self.buffer = try Buffer.init(self.alloc, self.size.cols, self.size.rows);

    {
        const shared_state = self.shared_state;

        shared_state.mutex.lock();
        defer shared_state.mutex.unlock();

        shared_state.screen.deinit(self.alloc);
        shared_state.screen = try .init(self.alloc, self.size);
    }

    _ = self.render_mailbox.push(.{ .resize = size }, .instant);
    try self.render_wakeup.notify();
}

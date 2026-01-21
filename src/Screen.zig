const std = @import("std");
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Cell = vaxis.Cell;

pub const Screen = @This();

const Method = vaxis.gwidth.Method;

const SwapChain = struct {
    const buf_count = 3;

    buffers: [buf_count]Buffer,
    buffer_index: std.math.IntFittingRange(0, buf_count) = 0,
    buffer_sema: std.Thread.Semaphore = .{ .permits = buf_count },

    defunct: bool = false,

    pub fn init(alloc: Allocator, cols: u16, rows: u16) !SwapChain {
        var result: SwapChain = .{ .buffers = undefined };

        for (&result.buffers) |*buffer| {
            buffer.* = try Buffer.init(alloc, cols, rows);
        }

        return result;
    }

    pub fn deinit(self: *SwapChain, alloc: Allocator) void {
        if (self.defunct) return;
        self.defunct = true;

        for (0..buf_count) |_| self.buffer_sema.wait();
        for (&self.buffers) |*buffer| buffer.deinit(alloc);
    }

    pub fn nextBuffer(self: *SwapChain) error{Defunct}!*Buffer {
        if (self.defunct) return error.Defunct;

        self.buffer_sema.wait();
        errdefer self.buffer_sema.post();
        self.buffer_index = (self.buffer_index + 1) % buf_count;
        return &self.buffers[self.buffer_index];
    }

    pub fn releaseBuffer(self: *SwapChain) void {
        self.buffer_sema.post();
    }
};

swap_chain: SwapChain,

current_buffer: ?*Buffer = null,

cursor_row: u16 = 0,
cursor_col: u16 = 0,
cursor_vis: bool = false,

width_pix: u16 = 0,
height_pix: u16 = 0,

width_method: Method = .wcwidth,

mouse_shape: vaxis.Mouse.Shape = .default,
cursor_shape: Cell.CursorShape = .default,

pub fn init(alloc: Allocator, size: vaxis.Winsize) !Screen {
    return .{
        .swap_chain = try SwapChain.init(alloc, size.cols, size.rows),
        .width_pix = size.x_pixel,
        .height_pix = size.y_pixel,
    };
}

pub fn deinit(self: *Screen, alloc: Allocator) void {
    self.swap_chain.deinit(alloc);
}

pub fn nextBuffer(self: *Screen) !*Buffer {
    const buffer = try self.swap_chain.nextBuffer();
    self.current_buffer = buffer;
    return buffer;
}

pub fn releaseBuffer(self: *Screen) void {
    self.swap_chain.releaseBuffer();
}

pub fn currentBuffer(self: *Screen) ?*Buffer {
    return self.current_buffer;
}

pub fn resizeBuffer(self: *Screen, alloc: Allocator, buffer: *Buffer, size: vaxis.Winsize) !void {
    buffer.deinit(alloc);
    buffer.* = try Buffer.init(alloc, size.cols, size.rows);
    self.width_pix = size.x_pixel;
    self.height_pix = size.y_pixel;
}

pub fn toVaxisScreen(self: *Screen, buffer: *Buffer) vaxis.Screen {
    return .{
        .width = buffer.width,
        .height = buffer.height,
        .width_pix = self.width_pix,
        .height_pix = self.height_pix,
        .buf = buffer.buf,
        .cursor_row = self.cursor_row,
        .cursor_col = self.cursor_col,
        .cursor_vis = self.cursor_vis,
        .width_method = self.width_method,
        .mouse_shape = self.mouse_shape,
        .cursor_shape = self.cursor_shape,
    };
}

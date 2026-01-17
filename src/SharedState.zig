const std = @import("std");
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;

pub const SharedState = @This();

const AtomicU8 = std.atomic.Value(u8);

screens: [3]vaxis.Screen,
write_idx: u8 = 0,
ready_idx: AtomicU8 = .init(3), // 3 = no frame ready yet
read_idx: u8 = 2,

pub fn init(alloc: Allocator, size: vaxis.Winsize) !SharedState {
    return .{
        .screens = .{
            try .init(alloc, size),
            try .init(alloc, size),
            try .init(alloc, size),
        },
    };
}

pub fn deinit(self: *SharedState, alloc: Allocator) void {
    for (&self.screens) |*screen| {
        screen.deinit(alloc);
    }
}

/// Called by window after writing a frame.
/// Publishes the current write buffer and recycles the old ready buffer.
pub fn swapWrite(self: *SharedState) void {
    const old_ready = self.ready_idx.swap(self.write_idx, .acq_rel);
    // Recycle: if old_ready was valid (not 3) and not being read, use it
    // Otherwise cycle to next available buffer
    if (old_ready < 3 and old_ready != self.read_idx) {
        self.write_idx = old_ready;
    } else {
        // Find a buffer that's not being read
        self.write_idx = self.findFreeBuffer();
    }
}

/// Called by renderer before reading.
/// Returns true if a new frame is available.
pub fn swapRead(self: *SharedState) bool {
    const ready = self.ready_idx.load(.acquire);
    if (ready >= 3) return false; // No frame ready yet

    // Swap: take the ready buffer, give back our read buffer
    const old_read = self.read_idx;
    const swapped = self.ready_idx.cmpxchgStrong(ready, old_read, .acq_rel, .acquire);

    if (swapped == null) {
        // Success - we got the ready buffer
        self.read_idx = ready;
        return true;
    }
    return false;
}

/// Get the current write buffer
pub fn writeBuffer(self: *SharedState) *vaxis.Screen {
    return &self.screens[self.write_idx];
}

/// Get the current read buffer
pub fn readBuffer(self: *SharedState) *vaxis.Screen {
    return &self.screens[self.read_idx];
}

fn findFreeBuffer(self: *SharedState) u8 {
    const ready = self.ready_idx.load(.acquire);
    for (0..3) |i| {
        const idx: u8 = @intCast(i);
        if (idx != self.read_idx and (ready >= 3 or idx != ready)) {
            return idx;
        }
    }
    // Fallback (shouldn't happen with 3 buffers)
    return (self.write_idx + 1) % 3;
}

/// Resize only the current write buffer. Called lazily before copying.
pub fn resizeWriteBuffer(self: *SharedState, alloc: Allocator, size: vaxis.Winsize) !void {
    const screen = &self.screens[self.write_idx];
    screen.deinit(alloc);
    screen.* = try .init(alloc, size);
}

const std = @import("std");
const GPA = std.heap.GeneralPurposeAllocator(.{});
const UpdatedEntriesSet = @import("worktree/scanner/mod.zig").UpdatedEntriesSet;
const io_types = @import("io/types.zig");

pub const EventEmitter = @import("EventEmitter.zig").EventEmitter(GlobalEvents);

pub const Callback = *const fn (event: u8, ptr: ?[*]const u8, len: usize) callconv(.c) void;
const BlockingQueue = @import("datastruct").BlockingQueue;
const MailBox = BlockingQueue(Events, 64);

pub const xev = @import("xev").Dynamic;

pub var state: GlobalState = undefined;

pub const GlobalEvents = union(enum) {
    worktreeUpdate: UpdatedEntriesSet,
    bufferUpdate: u64,
    themeUpdate: void,
    ioReadComplete: io_types.ReadResult,
};

pub const ExternSurfaceState = extern struct {
    cell_width: u32,
    cell_height: u32,
    renderer_health: u8,
};

pub const ExternEditorState = extern struct {
    entry_id: u64,
    row_count: u64,
};

pub const ExternModeUpdate = extern struct {
    mode: u8,
};

pub const KeymapMatch = struct {
    sequence: []u8,
    action: []u8,
};

pub const ExternKeymapMatch = extern struct {
    sequence_ptr: usize,
    sequence_len: usize,
    action_ptr: usize,
    action_len: usize,
};

pub const Events = union(enum) {
    settingsUpdate: void,
    themeUpdate: void,
    filetreeUpdate: void,
    surfaceUpdate: ExternSurfaceState,
    bufferUpdate: ExternEditorState,
    modeUpdate: ExternModeUpdate,
    keymapMatch: KeymapMatch,
};

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA = .{},
    alloc: std.mem.Allocator,
    events: EventEmitter,
    mailbox: *MailBox,
    callback: ?Callback = null,

    pub fn init(self: *Self, callback: ?Callback) !void {
        const gpa: GPA = .{};
        const alloc = self.gpa.allocator();
        self.* = .{
            .gpa = gpa,
            .alloc = alloc,
            .events = EventEmitter.init(alloc),
            .callback = callback,
            .mailbox = try MailBox.create(alloc),
        };
    }

    pub fn emitGlobal(self: *Self, event: GlobalEvents) void {
        self.events.emit(event);
    }

    pub fn emit(self: *Self, event: Events, timeout: MailBox.Timeout) u32 {
        return self.mailbox.push(event, timeout);
    }

    pub fn deinit(self: *Self) void {
        self.events.deinit();
        self.mailbox.destroy(self.alloc);
        if (self.gpa.deinit() == .leak) {
            std.log.debug("WE HAVE LEAKS", .{});
        }
    }
};

const std = @import("std");
const mem = std.mem;

pub const BUNDLE_ID = "Hss.Odyssey";
pub const DB_NAME = "odyssey.sqlite";

pub const MAX_ALIGN: mem.Alignment = .@"16";
pub const MAX_SIZE = 128;

pub const MAX_PATH_LEN = 4096;

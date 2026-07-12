const std = @import("std");
const mem = std.mem;

pub const BUNDLE_ID = "Hss.Odyssey";
pub const DB_NAME = "odyssey.sqlite";

pub const MAX_ALIGN: mem.Alignment = .@"16";
pub const MAX_SIZE = 128;

pub const MAX_PATH_LEN = 4096;

pub const SIMD_CHUNK_BYTES = 16;
pub const INLINE_CHUNKS = 4;
pub const MAX_PAH_CHUNKS: comptime_int =
    @ceil(@as(f32, @floatFromInt(MAX_PATH_LEN)) / @as(f32, @floatFromInt(SIMD_CHUNK_BYTES)));

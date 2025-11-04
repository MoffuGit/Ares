const Grid = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atlas = @import("Atlas.zig");
const CodePointResolver = @import("CodePointResolver.zig");
const facepkg = @import("face/mod.zig");
const Face = facepkg.Face;
const embedpkg = @import("embedded/mod.zig");

atlas_grayscale: Atlas,
resolver: CodePointResolver,
// glyphs: void,
// codepoints: void,

pub fn init(alloc: Allocator, opts: facepkg.Options) !Grid {
    var atlas_grayscale = try Atlas.init(alloc, 512, .grayscale);
    errdefer atlas_grayscale.deinit(alloc);

    const grid = Grid{ .atlas_grayscale = atlas_grayscale, .resolver = .{
        .face = try Face.init(embedpkg.JetBrainsMono, opts),
    } };

    return grid;
}

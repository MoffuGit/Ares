const CodePointResolver = @This();

const fontpkg = @import("mod.zig");
const facepkg = fontpkg.facepkg;
const Face = facepkg.Face;
const std = @import("std");
const Collection = @import("Collection.zig");
const Allocator = std.mem.Allocator;
const Style = fontpkg.Style;

collection: Collection,

pub fn deinit(self: *CodePointResolver, alloc: Allocator) void {
    self.collection.deinit(alloc);
}

pub fn getFace(self: *CodePointResolver, style: Style) *Face {
    return self.collection.faces.getPtr(style);
}

const CodePointResolver = @This();

const fontpkg = @import("mod.zig");
const facepkg = fontpkg.facepkg;
const Face = facepkg.Face;

face: Face,
fallback: ?Face = null,

pub fn deinit(self: *CodePointResolver) void {
    if (self.fallback) |*fb| fb.deinit();
    self.face.deinit();
}

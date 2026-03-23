const CodePointResolver = @This();

const fontpkg = @import("mod.zig");
const facepkg = fontpkg.facepkg;
const Face = facepkg.Face;

face: Face,

pub fn deinit(self: *CodePointResolver) void {
    self.face.deinit();
}

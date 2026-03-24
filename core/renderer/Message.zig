pub const SurfaceSize = struct {
    width: u32,
    height: u32,
};

pub const Message = union(enum) {
    resize: SurfaceSize,
    visible: bool,
};

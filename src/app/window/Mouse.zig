const vaxis = @import("vaxis");

pub const Mouse = @This();

pub const Button = vaxis.Mouse.Button;
pub const Modifiers = vaxis.Mouse.Modifiers;
pub const Type = vaxis.Mouse.Type;
pub const Shape = vaxis.Mouse.Shape;

col: u16,
row: u16,
pixel_col: i16,
pixel_row: i16,
xoffset: u16 = 0,
yoffset: u16 = 0,
button: Button,
mods: Modifiers,
type: Type,

pub fn fromVaxis(vaxis_mouse: vaxis.Mouse, winsize: vaxis.Winsize) Mouse {
    const cell_width: f32 = if (winsize.cols > 0 and winsize.x_pixel > 0)
        @as(f32, @floatFromInt(winsize.x_pixel)) / @as(f32, @floatFromInt(winsize.cols))
    else
        1.0;

    const cell_height: f32 = if (winsize.rows > 0 and winsize.y_pixel > 0)
        @as(f32, @floatFromInt(winsize.y_pixel)) / @as(f32, @floatFromInt(winsize.rows))
    else
        1.0;

    const pixel_col: f32 = if (vaxis_mouse.col < 0) 0 else @floatFromInt(vaxis_mouse.col);
    const pixel_row: f32 = if (vaxis_mouse.row < 0) 0 else @floatFromInt(vaxis_mouse.row);

    const col: u16 = @intFromFloat(@floor(pixel_col / cell_width));
    const row: u16 = @intFromFloat(@floor(pixel_row / cell_height));

    return .{
        .col = col,
        .row = row,
        .pixel_col = vaxis_mouse.col,
        .pixel_row = vaxis_mouse.row,
        .xoffset = vaxis_mouse.xoffset,
        .yoffset = vaxis_mouse.yoffset,
        .button = vaxis_mouse.button,
        .mods = vaxis_mouse.mods,
        .type = vaxis_mouse.type,
    };
}

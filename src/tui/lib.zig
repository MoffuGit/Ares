//step 0
//
//making this lib a C ABI library
//
//step 1
//
//update the loop
//
//step 2
//
//event bus for two ways communication
//
//step 3 is on ts, is for latter
pub const App = @import("mod.zig");
pub const Window = @import("window/mod.zig");
pub const Element = @import("window/element/mod.zig");
pub const Style = Element.Style;
pub const Color = Element.Color;
pub const TypedElement = Element.TypedElement;
pub const TypedAnimation = Element.TypedAnimation;
pub const Buffer = @import("Buffer.zig");
pub const HitGrid = @import("window/HitGrid.zig");
pub const EventListeners = @import("events.zig").EventListeners;
pub const Animation = Element.Animation;
pub const Timer = Element.Timer;

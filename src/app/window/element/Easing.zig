const std = @import("std");
const math = std.math;

pub const Easing = @This();

pub const Function = *const fn (f32) f32;

pub const Type = union(enum) {
    linear,

    ease_in_quad,
    ease_out_quad,
    ease_in_out_quad,

    ease_in_cubic,
    ease_out_cubic,
    ease_in_out_cubic,

    ease_in_expo,
    ease_out_expo,
    ease_in_out_expo,

    ease_in_back,
    ease_out_back,
    ease_in_out_back,

    ease_out_elastic,

    ease_out_bounce,

    custom: Function,

    pub fn apply(self: Type, t: f32) f32 {
        return switch (self) {
            .linear => t,

            .ease_in_quad => easeInQuad(t),
            .ease_out_quad => easeOutQuad(t),
            .ease_in_out_quad => easeInOutQuad(t),

            .ease_in_cubic => easeInCubic(t),
            .ease_out_cubic => easeOutCubic(t),
            .ease_in_out_cubic => easeInOutCubic(t),

            .ease_in_expo => easeInExpo(t),
            .ease_out_expo => easeOutExpo(t),
            .ease_in_out_expo => easeInOutExpo(t),

            .ease_in_back => easeInBack(t),
            .ease_out_back => easeOutBack(t),
            .ease_in_out_back => easeInOutBack(t),

            .ease_out_elastic => easeOutElastic(t),

            .ease_out_bounce => easeOutBounce(t),

            .custom => |func| func(t),
        };
    }
};

// Quad (t²)
fn easeInQuad(t: f32) f32 {
    return t * t;
}

fn easeOutQuad(t: f32) f32 {
    return 1.0 - (1.0 - t) * (1.0 - t);
}

fn easeInOutQuad(t: f32) f32 {
    if (t < 0.5) {
        return 2.0 * t * t;
    } else {
        const t2 = -2.0 * t + 2.0;
        return 1.0 - (t2 * t2) / 2.0;
    }
}

// Cubic (t³)
fn easeInCubic(t: f32) f32 {
    return t * t * t;
}

fn easeOutCubic(t: f32) f32 {
    const t2 = 1.0 - t;
    return 1.0 - t2 * t2 * t2;
}

fn easeInOutCubic(t: f32) f32 {
    if (t < 0.5) {
        return 4.0 * t * t * t;
    } else {
        const t2 = -2.0 * t + 2.0;
        return 1.0 - (t2 * t2 * t2) / 2.0;
    }
}

// Exponential
fn easeInExpo(t: f32) f32 {
    if (t == 0.0) return 0.0;
    return math.pow(f32, 2.0, 10.0 * t - 10.0);
}

fn easeOutExpo(t: f32) f32 {
    if (t == 1.0) return 1.0;
    return 1.0 - math.pow(f32, 2.0, -10.0 * t);
}

fn easeInOutExpo(t: f32) f32 {
    if (t == 0.0) return 0.0;
    if (t == 1.0) return 1.0;
    if (t < 0.5) {
        return math.pow(f32, 2.0, 20.0 * t - 10.0) / 2.0;
    } else {
        return (2.0 - math.pow(f32, 2.0, -20.0 * t + 10.0)) / 2.0;
    }
}

// Back (overshoot)
const c1: f32 = 1.70158;
const c2: f32 = c1 * 1.525;
const c3: f32 = c1 + 1.0;

fn easeInBack(t: f32) f32 {
    return c3 * t * t * t - c1 * t * t;
}

fn easeOutBack(t: f32) f32 {
    const t2 = t - 1.0;
    return 1.0 + c3 * t2 * t2 * t2 + c1 * t2 * t2;
}

fn easeInOutBack(t: f32) f32 {
    if (t < 0.5) {
        const t2 = 2.0 * t;
        return (t2 * t2 * ((c2 + 1.0) * t2 - c2)) / 2.0;
    } else {
        const t2 = 2.0 * t - 2.0;
        return (t2 * t2 * ((c2 + 1.0) * t2 + c2) + 2.0) / 2.0;
    }
}

// Elastic (spring)
const c4: f32 = (2.0 * math.pi) / 3.0;

fn easeOutElastic(t: f32) f32 {
    if (t == 0.0) return 0.0;
    if (t == 1.0) return 1.0;
    return math.pow(f32, 2.0, -10.0 * t) * @sin((t * 10.0 - 0.75) * c4) + 1.0;
}

// Bounce
fn easeOutBounce(t: f32) f32 {
    const n1: f32 = 7.5625;
    const d1: f32 = 2.75;

    if (t < 1.0 / d1) {
        return n1 * t * t;
    } else if (t < 2.0 / d1) {
        const t2 = t - 1.5 / d1;
        return n1 * t2 * t2 + 0.75;
    } else if (t < 2.5 / d1) {
        const t2 = t - 2.25 / d1;
        return n1 * t2 * t2 + 0.9375;
    } else {
        const t2 = t - 2.625 / d1;
        return n1 * t2 * t2 + 0.984375;
    }
}

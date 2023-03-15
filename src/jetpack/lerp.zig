const std = @import("std");

pub const LerpStyle = enum {
    Linear,
    EaseIn,
    Smoothstep,
    EaseOutElastic,
    EaseOutExpo,
    EaseInQuad,
    EaseInExpo,
    EaseInBack,
};

pub fn lerp(v0: f32, v1: f32, t_in: f32, lerpStyle: LerpStyle) f32 {
    if (v0 == v1) {
        return v0;
    }

    if (t_in < 0.0) {
        return v0;
    }
    if (t_in > 1.0) {
        return v1;
    }

    var t_out = t_in;

    switch (lerpStyle) {
        .Linear => {},
        .EaseIn => t_out = @sin(t_out * std.math.pi * 0.5),
        .Smoothstep => t_out = t_out * t_out * (3.0 - 2.0 * t_out),
        .EaseOutElastic => {
            const c4 = (2 * std.math.pi) / @as(f32, 3);
            if (t_out == 0) {
                t_out = 0;
            } else if (t_out == 1) {
                t_out = 1;
            } else {
                t_out = std.math.pow(f32, 2, -10 * t_out) * @sin((t_out * 10 - 0.75) * c4) + 1;
            }
        },
        .EaseOutExpo => {
            if (t_out < 1) {
                t_out = 1 - std.math.pow(f32, 2, -10 * t_out);
            }
        },
        .EaseInExpo => {
            if (t_out > 0) {
                t_out = std.math.pow(f32, 2, 10 * t_out - 10);
            }
        },
        .EaseInQuad => t_out = t_out * t_out,
        .EaseInBack => {
            const c1 = 1.70158;
            const c3 = c1 + 1;
            t_out = c3 * t_out * t_out * t_out - c1 * t_out * t_out;
        },
    }

    return (1 - t_out) * v0 + t_out * v1;
}

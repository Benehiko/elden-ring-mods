//! Registry of available mods.

pub const level60 = @import("level60.zig");
pub const class_gear = @import("class_gear.zig");

test {
    _ = level60;
    _ = class_gear;
}

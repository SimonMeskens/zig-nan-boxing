//* Copyright 2025 Simon Meskens
//* Licensed under the MIT License
//*
//* Permission to use, copy, modify, and/or distribute this software for any
//* purpose with or without fee is hereby granted, provided this license is
//* preserved. This software is offered as-is, without any warranty.

const std = @import("std");

comptime {
    std.debug.assert(bits_nan == @as(u64, @bitCast(std.math.nan(f64))));
    std.debug.assert(@alignOf(Dyn64) == @alignOf(u64));
    std.debug.assert(@bitSizeOf(Dyn64) == 64);
}

/// The 3-bit type tag for tagged values.
pub const Tag = enum(u3) {
    nan = 0b0_00,
    false = 0b0_01,
    true = 0b0_10,
    null = 0b0_11,

    pointer = 0b1_00,
    string = 0b1_01,
    uint = 0b1_10,
    sint = 0b1_11,
};

pub const mask_sign: u64 = 0b1 << 63;
pub const mask_exponent: u64 = 0b0_11111111111 << 52;
pub const mask_quiet: u64 = 0b1 << 51;
pub const mask_type: u64 = 0b111 << 48;

pub const mask_nan: u64 = mask_exponent | mask_quiet;
pub const mask_signature: u64 = mask_sign | mask_exponent | mask_quiet | mask_type;

/// The raw bits of a NaN-boxed value.
pub const bits_nan: u64 = (@as(u64, @intFromEnum(Tag.nan)) << 48) | mask_nan;
/// The raw bits of a boxed `false` value.
pub const bits_false: u64 = (@as(u64, @intFromEnum(Tag.false)) << 48) | mask_nan;
/// The raw bits of a boxed `true` value.
pub const bits_true: u64 = (@as(u64, @intFromEnum(Tag.true)) << 48) | mask_nan;
/// The raw bits of a boxed `null` value.
pub const bits_null: u64 = (@as(u64, @intFromEnum(Tag.null)) << 48) | mask_nan;

pub const mask_payload: u64 = ~mask_signature;

pub const signature_nan: u13 = 0b0_11111111111_1;

/// `NaN` as a boxed value.
pub const dyn_nan = Dyn64{ .float = std.math.nan(f64) };
/// `false` as a boxed value.
pub const dyn_false = Dyn64{ .bits = bits_false };
/// `true` as a boxed value.
pub const dyn_true = Dyn64{ .bits = bits_true };
/// `null` as a boxed value.
pub const dyn_null = Dyn64{ .bits = bits_null };

/// A 64-bit dynamic boxed type based on NaN-boxing.
pub const Dyn64 = packed union {
    /// The raw bits of the boxed value.
    bits: u64,
    /// The boxed value as a floating-point number.
    float: f64,
    /// The boxed value as a tagged value.
    tagged: packed struct {
        /// The boxed payload
        payload: packed union {
            /// The raw bits of the payload.
            bits: u48,
            /// Unsigned integer representation.
            uint: packed struct { value: u32, unused: u16 },
            /// Signed integer representation.
            sint: packed struct { value: i32, unused: u16 },
        },
        /// The type of the tagged value.
        type: Tag,
        /// The signature bits of the tagged value. Will always be `0b0_11111111111_1` for boxed values and NaN.
        signature: u13,
    },

    /// Checks if the boxed value is a `NaN`.
    pub fn isNaN(self: Dyn64) bool {
        return self.bits == bits_nan;
    }

    /// Checks if the boxed value is a double.
    pub fn isDouble(self: Dyn64) bool {
        return self.tagged.signature != signature_nan or self.isNaN();
    }

    /// Unboxes the boxed value as a double.
    pub fn asDouble(self: Dyn64) f64 {
        return self.float;
    }

    /// Turns a double into a boxed value.
    pub fn fromDouble(value: f64) Dyn64 {
        return Dyn64{ .float = value };
    }

    /// Checks if the boxed value is a boolean.
    pub fn isBool(self: Dyn64) bool {
        return self.isTrue() or self.isFalse();
    }

    /// Checks if the boxed value is `false`.
    pub fn isFalse(self: Dyn64) bool {
        return self.bits == bits_false;
    }

    /// Checks if the boxed value is `true`.
    pub fn isTrue(self: Dyn64) bool {
        return self.bits == bits_true;
    }

    /// Turns a boolean into a boxed value.
    pub fn fromBool(value: bool) Dyn64 {
        return if (value) dyn_true else dyn_false;
    }

    /// Checks if the boxed value is a pointer.
    pub fn isPointer(self: Dyn64) bool {
        return !self.isDouble() and self.tagged.type == Tag.pointer;
    }

    /// Unboxes the boxed value as a pointer.
    pub fn asPointer(self: Dyn64, T: type) *T {
        return @ptrFromInt(self.bits & mask_payload);
    }

    /// Turns a pointer into a boxed value.
    pub fn fromPointer(value: *const anyopaque) Dyn64 {
        const bits: u64 = @intFromPtr(value);
        // This is just for sanity, pointers should never exceed 48 bits.
        std.debug.assert(bits & mask_signature == 0);
        return Dyn64{
            .tagged = .{
                .payload = .{ .bits = @truncate(bits) },
                .type = Tag.pointer,
                .signature = signature_nan,
            },
        };
    }

    /// Checks if the boxed value is `null`.
    pub fn isNull(self: Dyn64) bool {
        return self.bits == bits_null;
    }

    /// Turns a nullable value into a boxed value.
    pub fn fromOptional(maybe: anytype) Dyn64 {
        return if (maybe) |value| from(value) else dyn_null;
    }

    /// Checks if the boxed value is a string.
    pub fn isString(self: Dyn64) bool {
        return !self.isDouble() and self.tagged.type == Tag.string;
    }

    /// Unboxes the boxed value as a null-terminated string.
    pub fn asString(self: Dyn64) [*:0]const u8 {
        return @ptrFromInt(self.bits & mask_payload);
    }

    /// Turns a string into a boxed value.
    pub fn fromString(value: [*:0]const u8) Dyn64 {
        return Dyn64{
            .tagged = .{
                .payload = .{ .bits = @truncate(@intFromPtr(value)) },
                .type = Tag.string,
                .signature = signature_nan,
            },
        };
    }

    /// Checks if the boxed value is an unsigned integer.
    pub fn isUint(self: Dyn64) bool {
        return !self.isDouble() and self.tagged.type == Tag.uint;
    }

    /// Unboxes the boxed value as an unsigned integer.
    pub fn asUint(self: Dyn64) u32 {
        return self.tagged.payload.uint.value;
    }

    /// Turns an unsigned integer into a boxed value.
    pub fn fromUint(value: u32) Dyn64 {
        return Dyn64{
            .tagged = .{
                .payload = .{
                    .uint = .{ .value = value, .unused = 0 },
                },
                .type = Tag.uint,
                .signature = signature_nan,
            },
        };
    }

    /// Checks if the boxed value is a signed integer.
    pub fn isSint(self: Dyn64) bool {
        return !self.isDouble() and self.tagged.type == Tag.sint;
    }

    /// Unboxes the boxed value as a signed integer.
    pub fn asSint(self: Dyn64) i32 {
        return self.tagged.payload.sint.value;
    }

    /// Turns a signed integer into a boxed value.
    pub fn fromSint(value: i32) Dyn64 {
        return Dyn64{
            .tagged = .{
                .payload = .{
                    .sint = .{ .value = value, .unused = 0 },
                },
                .type = Tag.sint,
                .signature = signature_nan,
            },
        };
    }

    /// Turns a value into a boxed value.
    /// If you want to box a string, use `Box.fromString`.
    pub fn from(value: anytype) Dyn64 {
        const typeInfo: std.builtin.Type = @typeInfo(@TypeOf(value));
        switch (typeInfo) {
            .Float => return Dyn64.fromDouble(value),
            .Int => |info| switch (info.signedness) {
                .unsigned => return Dyn64.fromUint(@as(u32, value)),
                .signed => return Dyn64.fromSint(@as(i32, value)),
            },
            .Bool => return Dyn64.fromBool(value),
            .Null => return dyn_null,
            .Pointer => return Dyn64.fromPointer(value),
            .Optional => return Dyn64.fromOptional(value),
            else => unreachable,
        }
    }

    pub fn format(
        self: Dyn64,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        if (self.isDouble()) {
            try writer.print("{d}", .{self.asDouble()});
        } else switch (self.tagged.type) {
            Tag.true => try writer.print("true", .{}),
            Tag.false => try writer.print("false", .{}),
            Tag.null => try writer.print("null", .{}),
            Tag.pointer => try writer.print("{x}", .{self.asPointer(void)}),
            Tag.string => try writer.print("{s}", .{self.asString()}),
            Tag.uint => try writer.print("{d}", .{self.asUint()}),
            Tag.sint => try writer.print("{d}", .{self.asSint()}),
            else => unreachable,
        }
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "Box - doubles" {
    const doubles = [_]f64{
        0.0,               -0.0,
        0.5,               -0.5,
        1.0,               -1.0,
        1.5,               -1.5,
        std.math.inf(f64), -std.math.inf(f64),
    };

    for (doubles) |value| {
        const box = Dyn64.fromDouble(value);
        try expect(box.isDouble());
        try expectEqual(std.math.isNan(value), box.isNaN());
        try expectEqual(@as(u64, @bitCast(value)), box.bits);
        try expectEqual(value, box.asDouble());

        // try expect(!box.isDouble());
        try expect(!box.isNaN());
        try expect(!box.isBool());
        try expect(!box.isFalse());
        try expect(!box.isTrue());
        try expect(!box.isNull());
        try expect(!box.isPointer());
        try expect(!box.isString());
        try expect(!box.isUint());
        try expect(!box.isSint());
    }

    const nan = std.math.nan(f64);
    const boxed_nan = Dyn64{ .float = nan };
    try expect(boxed_nan.isNaN());
    try expect(boxed_nan.isDouble());
    try expectEqual(@as(u64, @bitCast(nan)), boxed_nan.bits);
    try expectEqual(bits_nan, boxed_nan.bits);
    try expect(std.math.isNan(boxed_nan.asDouble()));

    // try expect(!boxed_nan.isDouble());
    // try expect(!boxed_nan.isNaN());
    try expect(!boxed_nan.isBool());
    try expect(!boxed_nan.isFalse());
    try expect(!boxed_nan.isTrue());
    try expect(!boxed_nan.isNull());
    try expect(!boxed_nan.isPointer());
    try expect(!boxed_nan.isString());
    try expect(!boxed_nan.isUint());
    try expect(!boxed_nan.isSint());
}

test "Box - bools" {
    const bools = [_]bool{ true, false };

    for (bools) |value| {
        const box = Dyn64.fromBool(value);
        try expect(box.isBool());

        try expectEqual(value, box.isTrue());
        try expectEqual(!value, box.isFalse());

        try expect(!box.isDouble());
        try expect(!box.isNaN());
        // try expect(!box.isBool());
        // try expect(!box.isFalse());
        // try expect(!box.isTrue());
        try expect(!box.isNull());
        try expect(!box.isPointer());
        try expect(!box.isString());
        try expect(!box.isUint());
        try expect(!box.isSint());
    }
}

test "Box - pointers" {
    var data: u32 = 0xDEADBEEF;
    const pointer: *u32 = &data;

    const boxed_pointer = Dyn64.fromPointer(pointer);
    try expect(boxed_pointer.isPointer());
    try expectEqual(pointer, boxed_pointer.asPointer(u32));
    try expectEqual(data, boxed_pointer.asPointer(u32).*);

    try expect(!boxed_pointer.isDouble());
    try expect(!boxed_pointer.isNaN());
    try expect(!boxed_pointer.isBool());
    try expect(!boxed_pointer.isFalse());
    try expect(!boxed_pointer.isTrue());
    try expect(!boxed_pointer.isNull());
    // try expect(!boxed_pointer.isPointer());
    try expect(!boxed_pointer.isString());
    try expect(!boxed_pointer.isUint());
    try expect(!boxed_pointer.isSint());
}

test "Box - strings" {
    const strings = [_][*:0]const u8{
        "hello", "world",
        "foo",   "bar",
        "zig",   "zag",
    };

    for (strings) |value| {
        const box = Dyn64.fromString(value);

        try expect(box.isString());
        try expectEqual(value, box.asString());

        try expect(!box.isDouble());
        try expect(!box.isNaN());
        try expect(!box.isBool());
        try expect(!box.isFalse());
        try expect(!box.isTrue());
        try expect(!box.isNull());
        try expect(!box.isPointer());
        // try expect(!box.isString());
        try expect(!box.isUint());
        try expect(!box.isSint());
    }
}

test "Box - integers" {
    const uints = [_]u32{ 0, 1, 10, 1000, 1_000_000, 1_000_000_000, std.math.maxInt(u32) };
    const sints = [_]i32{
        std.math.minInt(i32), std.math.maxInt(i32),
        -1,                   1,
        -10,                  10,
        -1000,                1000,
        -1_000_000,           1_000_000,
        0,
    };

    for (uints) |value| {
        const box = Dyn64.fromUint(value);

        try expect(box.isUint());
        try expectEqual(value, box.asUint());

        try expect(!box.isDouble());
        try expect(!box.isNaN());
        try expect(!box.isBool());
        try expect(!box.isFalse());
        try expect(!box.isTrue());
        try expect(!box.isNull());
        try expect(!box.isPointer());
        try expect(!box.isString());
        // try expect(!box.isUint());
        try expect(!box.isSint());
    }

    for (sints) |value| {
        const box = Dyn64.fromSint(value);

        try expect(box.isSint());
        try expectEqual(value, box.asSint());

        try expect(!box.isDouble());
        try expect(!box.isNaN());
        try expect(!box.isBool());
        try expect(!box.isFalse());
        try expect(!box.isTrue());
        try expect(!box.isNull());
        try expect(!box.isPointer());
        try expect(!box.isString());
        try expect(!box.isUint());
        // try expect(!box.isSint());
    }
}

test "Box - optional" {
    const boxed_null = Dyn64.fromOptional(null);
    try expect(boxed_null.isNull());

    const boxed_uint = Dyn64.fromOptional(@as(?u32, 42));
    try expect(!boxed_uint.isNull());
    try expect(boxed_uint.isUint());
}

test "Box - from" {
    var data: u32 = 0xDEADBEEF;

    try expect(Dyn64.from(null).isNull());
    try expect(Dyn64.from(true).isTrue());
    try expect(Dyn64.from(false).isFalse());
    try expect(Dyn64.from(std.math.nan(f64)).isNaN());
    try expect(Dyn64.from(@as(f64, 0.05)).isDouble());
    try expect(Dyn64.from(@as(u32, 42)).isUint());
    try expect(Dyn64.from(@as(i32, -42)).isSint());
    // `from` turns strings into pointers,
    // use `fromString` instead if you need a boxed string.
    try expect(Dyn64.from(@as([*:0]const u8, "Hello")).isPointer());
    try expect(Dyn64.from(&data).isPointer());
}

test "Box - readme example" {
    const maybe: ?bool = true; // Is this real life?

    var box = Dyn64.from(@as(u32, 42)); // Box an integer
    box = Dyn64.from(maybe); // Now it's a boolean

    if (box.isNull()) unreachable; // Check if it's null
    const truth: bool = box.isTrue(); // Take it back out

    _ = truth;
}

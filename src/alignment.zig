const std = @import("std");
const console = @import("./console.zig");
pub fn asForwardAlignedPtr(comptime T: type, address: usize) T {
    return @as(T, @ptrFromInt(asForwardAligned(address, @typeInfo(T).pointer.alignment)));
}

pub fn asForwardAligned(address: usize, alignment: usize) usize {
    if ((address % alignment) == 0) {
        return address;
    }
    return address + (alignment - (address % alignment));
}

pub fn asBackwardAligned(address: usize, alignment: usize) usize {
    if (address % alignment == 0) {
        return address;
    }
    return address - (address % alignment);
}

const expect = @import("std").testing.expect;

test "asForwardAlignedPtr" {
    try expect(@intFromPtr(asForwardAlignedPtr(*align(8) const u8, 0x6)) == 0x8);
    try expect(@intFromPtr(asForwardAlignedPtr(*align(8) const u8, 0x3)) == 0x8);
    try expect(@intFromPtr(asForwardAlignedPtr(*align(8) const u8, 0x8)) == 0x8);
    try expect(@intFromPtr(asForwardAlignedPtr(*align(8) const u8, 0x842)) == 0x848);
    try expect(@intFromPtr(asForwardAlignedPtr(*align(32) const u8, 0x842)) == 0x860);
    try expect(@intFromPtr(asForwardAlignedPtr(*align(32) const u8, 0x868)) == 0x880);
}

test "asForwardAligned" {
    try expect(asForwardAligned(0x6, 8) == 0x8);
    try expect(asForwardAligned(0x3, 8) == 0x8);
    try expect(asForwardAligned(0x8, 8) == 0x8);
    try expect(asForwardAligned(0x842, 8) == 0x848);
    try expect(asForwardAligned(0x842, 32) == 0x860);
    try expect(asForwardAligned(0x868, 32) == 0x880);
    try expect(asForwardAligned(1234, 4096) == 4096);
}

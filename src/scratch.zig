const std = @import("std");

test "bobby" {
    var x: [16]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    for (&x) |*y| {
        y.* += 1;
    }
    std.debug.print("{any}", .{x});
}

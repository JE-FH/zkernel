const console = @import("console.zig");

pub fn kernel_panicf(comptime reason: []const u8, parameters: anytype) noreturn {
    console.printf("Kernel error: ", .{});
    console.printf(reason, parameters);
    asm volatile ("hlt");
    unreachable;
}

pub fn kernel_panic(reason: []const u8) noreturn {
    console.printf("Kernel error: {s}", .{reason});
    asm volatile ("hlt");
    unreachable;
}

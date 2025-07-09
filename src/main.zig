const console = @import("./console.zig");
const multiboot = @import("./multiboot2.zig");
const gdt = @import("./gdt.zig");
const paging = @import("./paging.zig");
const panic_helper = @import("./panic_helper.zig");
const debug = @import("std").debug;
const PhysicalMemoryManager = @import("./physical_memory_manager.zig").PhysicalMemoryManager;
const Segment = @import("./segment_lib.zig").Segment;
const BootstrapVMM = @import("./virtual_memory_manager.zig").BootstrapVMM;
const VMM = @import("./virtual_memory_manager.zig").VMM;
const alignment = @import("./alignment.zig");
const MAGIC = 0xE85250D6;

const tags = .{
    multiboot.InformationRequestTag.create(0, &.{6}),
    multiboot.SentinelHeaderTag.create(),
};

export var globalMultibootHeader: [multiboot.calculateMultibootSize(tags)]u8 align(4) linksection(".multiboot") = multiboot.createMultiboot2Header(
    multiboot.Multiboot2Architecture.i386ProtectedMode,
    tags,
);

export var multiboot_info_location: *multiboot.MultibootInfo = undefined;

var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;
export var temporary_stack_top = (@as([*]align(16) u8, @ptrCast(&stack_bytes)) + @sizeOf(@TypeOf(stack_bytes)));

comptime {
    asm (
        \\.global _start
        \\.type _start, @function
        \\_start:
        // save multiboot info location
        \\  movl %ebx, (multiboot_info_location)
        // setup the temporary stack
        \\  movl temporary_stack_top, %esp
        \\  movl %esp, %ebp
        // setup long mode
        \\  call kmain
        \\  hlt
    );
}

const kernel_begin = @extern(*u8, .{ .name = "_ZKERNEL_KERNEL_BEGIN" });
const kernel_end = @extern(*u8, .{ .name = "_ZKERNEL_KERNEL_END" });

//extern const _ZKERNEL_KERNEL_BEGIN: u8;
//extern const _ZKERNEL_KERNEL_END: u8;

var reserved_segments: [4]Segment linksection(".data") = undefined;

export fn kmain() callconv(.C) void {
    wrapper_main();
}

fn wrapper_main() void {
    caught_main() catch |err| {
        panic_helper.kernel_panicf("Kernel panic, unexpected error: {}", .{err});
    };
}

fn caught_main() !void {
    console.initialize();
    console.puts("Kernel initializing!\n");
    gdt.enable_flat_gdt();

    reserved_segments[0] = console.get_reserved_segment();
    reserved_segments[1] = multiboot_info_location.get_tags_reserved_segment();
    reserved_segments[2] = Segment.from_begin_end(@intFromPtr(kernel_begin), @intFromPtr(kernel_end));
    reserved_segments[3] = Segment.null_segment();

    var all_tag_iter = multiboot_info_location.enum_all_tags();
    var memory_entry_iterator = while (all_tag_iter.next()) |tag| {
        if (tag.type == multiboot.BootInformationTagType.MemoryMap) {
            var memory_map_tag: *align(8) const multiboot.MemoryMapTag = @ptrCast(tag);
            break memory_map_tag.enum_memory_entries();
        }
    } else {
        panic_helper.kernel_panic("Memory map could not be found");
    };

    var physical_memory_manager = PhysicalMemoryManager.init(&memory_entry_iterator, &reserved_segments);
    _ = physical_memory_manager.reserve_exclusive_page();

    var bootstrap_virtual_memory_manager = BootstrapVMM.init(&physical_memory_manager, 1);

    for (reserved_segments) |reserved_segment| {
        console.printf("bob\n", .{});
        if (reserved_segment.length == 0) {
            continue;
        }

        const aligned_begin = alignment.asBackwardAligned(reserved_segment.start, 4096);
        const aligned_end = alignment.asForwardAligned(reserved_segment.start + reserved_segment.length, 4096);
        console.printf("mapping from {X} to {X}\n", .{ aligned_begin, aligned_end });
        for ((aligned_begin >> 12)..(aligned_end >> 12)) |address| {
            bootstrap_virtual_memory_manager.map(address << 12, address << 12, true, false);
        }
    }

    paging.setPageDirectory(@ptrCast(bootstrap_virtual_memory_manager.get_physical_page_directory().as_ptr())) catch |err| switch (err) {
        error.UnalignedPageDirectoryTable => {
            panic_helper.kernel_panic("Tried to set non aligned page directory");
        },
    };

    paging.enablePaging();

    var virtual_memory_mapper = VMM.init(bootstrap_virtual_memory_manager);
    virtual_memory_mapper.map(0xB8000, 0x10000000, true, false);
    const vga: *volatile [2048]u16 = @ptrFromInt(0x10000000);

    vga.*[0] = 0xFFFF;

    console.printf("Now with paging {X}\n", .{virtual_memory_mapper.get_physical_page_directory().address});
    console.puts("done\n");
    panic_helper.kernel_panic("init exited");
}

pub const panic = debug.FullPanic(myPanic);

fn myPanic(msg: []const u8, _: ?usize) noreturn {
    panic_helper.kernel_panic(msg);
}

const SegmentDescriptor = packed struct {
    segment_limit15to0: u16,
    base_address_23to0: u24,
    type: u4,
    isCodeOrData: u1,
    privilege_level: u2,
    present: u1,
    segment_limit19to16: u4,
    meta: u1,
    IA32e_64_bit_segment: u1,
    default_operation_size: u1,
    granularity: u1,
    base_address31to24: u8,
};

const PsuedoGlobalDescriptorTable = packed struct {
    table_limit: u16,
    gdt_base_address: u32,
};

export var GDT: [3]SegmentDescriptor align(8) linksection(".bss") = undefined;
var psuedoGlobalDescriptorTable: PsuedoGlobalDescriptorTable align(4) linksection(".bss") = undefined;

fn lgdt(register_value: PsuedoGlobalDescriptorTable) void {
    psuedoGlobalDescriptorTable = register_value;
    asm volatile (
        \\ LGDT (%[psuedoGlobalDescriptorTable])
        :
        : [psuedoGlobalDescriptorTable] "r" (&psuedoGlobalDescriptorTable),
        : "memory"
    );
}

pub fn set_flat_segment_registers() void {
    asm volatile (
        \\movw $0b10000, %ax
        //set all data segments to the second gdt
        \\movw %ax, %gs
        \\movw %ax, %fs
        \\movw %ax, %ds
        \\movw %ax, %ss
        \\movw %ax, %es
        //set the code segment by jumping into it
        \\ljmpl $0b1000, $anchor
        \\anchor:
    );
}

pub fn enable_flat_gdt() void {
    GDT[0] = .{
        .segment_limit15to0 = 0,
        .base_address_23to0 = 0,
        .type = 2,
        .isCodeOrData = 1,
        .privilege_level = 0,
        .present = 0,
        .segment_limit19to16 = 0,
        .meta = 0,
        .IA32e_64_bit_segment = 0,
        .default_operation_size = 0,
        .granularity = 0,
        .base_address31to24 = 0,
    };

    //code segment
    GDT[1] = .{
        .segment_limit15to0 = 0xFFFF,
        .base_address_23to0 = 0,
        .type = 0b1010,
        .isCodeOrData = 1,
        .privilege_level = 0,
        .present = 1,
        .segment_limit19to16 = 0xF,
        .meta = 0,
        .IA32e_64_bit_segment = 0,
        .default_operation_size = 1,
        .granularity = 1,
        .base_address31to24 = 0,
    };

    //data segment
    GDT[2] = .{
        .segment_limit15to0 = 0xFFFF,
        .base_address_23to0 = 0,
        .type = 0b0010,
        .isCodeOrData = 1,
        .privilege_level = 0,
        .present = 1,
        .segment_limit19to16 = 0xF,
        .meta = 0,
        .IA32e_64_bit_segment = 0,
        .default_operation_size = 1,
        .granularity = 1,
        .base_address31to24 = 0,
    };

    lgdt(.{ .gdt_base_address = @intFromPtr(&GDT), .table_limit = (@sizeOf(SegmentDescriptor) * 3) - 1 });
    set_flat_segment_registers();
}

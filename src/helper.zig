export fn rdmsr(index: u32, low_out: *u32, high_out: *u32) void {
    asm volatile ("rdmsr"
        : [low_output] "={eax}" (low_out.*),
          [high_output] "={edx}" (high_out.*),
        : [msr_index] "{ecx}" (0xC0000080),
    );
}

export fn cpuid(index: u32, a: *u32, b: *u32, c: *u32, d: *u32) void {
  asm volatile (
      \\movl %[index], %%eax
      \\cpuid
      : [a] "={eax}" (a.*),
        [b] "={ebx}" (b.*),
        [c] "={ecx}" (c.*),
        [d] "={edx}" (d.*),
      : [index] "X" (index)
  );
}
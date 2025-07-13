const multiboot = @import("./multiboot2.zig");
const Segment = @import("./segment_lib.zig").Segment;
const console = @import("./console.zig");
const math = @import("std").math;
const panic_helper = @import("./panic_helper.zig");
const alignment = @import("./alignment.zig");
const sorting = @import("./sorting.zig");
const BootstrapVMM = @import("./virtual_memory_manager.zig").BootstrapVMM;

const MINIMUM_BOOTSTRAP_SECTION = 10000;

pub fn PhysicalPointer(comptime T: type) type {
    return struct {
        address: usize,
        pub fn init(address: usize) PhysicalPointer(T) {
            return .{ .address = address };
        }

        pub fn as_ptr(self: PhysicalPointer(T)) *T {
            return @ptrFromInt(self.address);
        }
    };
}

const SafeMemorySegmentIterator = struct {
    memory_entry_iterator: multiboot.MemoryEntryIterator,
    ordered_reserved_segments: []const Segment,
    iter_location: ?usize,
    current_segment: ?Segment,
    //requires a sorted array of reserved segments with no overlap
    fn init(memory_entry_iterator: multiboot.MemoryEntryIterator, ordered_reserved_segments: []const Segment) SafeMemorySegmentIterator {
        return .{
            .memory_entry_iterator = memory_entry_iterator,
            .ordered_reserved_segments = ordered_reserved_segments,
            .iter_location = 0,
            .current_segment = null,
        };
    }

    fn next(self: *SafeMemorySegmentIterator) ?Segment {
        if (self.current_segment == null) {
            const memory_entry = self.memory_entry_iterator.next();
            if (memory_entry == null) {
                return null;
            }

            if (memory_entry.?.type != multiboot.MemoryEntryType.Available) {
                return self.next();
            }

            if (memory_entry.?.base_address >= math.maxInt(usize)) {
                return self.next();
            }

            const corrected_end = @min(math.maxInt(usize), memory_entry.?.base_address + memory_entry.?.length);

            self.current_segment = Segment.from_begin_end(@intCast(memory_entry.?.base_address), @intCast(corrected_end));
        }

        var current_segment = self.current_segment.?;

        if (self.ordered_reserved_segments.len == 0) {
            self.current_segment = null;
            return current_segment;
        }

        if (self.iter_location == null) {
            self.iter_location = 0;
        } else {
            self.iter_location.? += 1;
            if (self.iter_location.? > self.ordered_reserved_segments.len) {
                self.iter_location = null;
                self.current_segment = null;
                return self.next();
            }
        }

        const upper_reserved_segment: Segment =
            if (self.iter_location.? < self.ordered_reserved_segments.len)
                self.ordered_reserved_segments[self.iter_location.?]
            else
                Segment.init(math.maxInt(usize), 0);

        const lower_reserved_segment: Segment =
            if (self.iter_location.? == 0)
                Segment.init(0, 0)
            else
                self.ordered_reserved_segments[self.iter_location.? - 1];

        current_segment.remove_below(lower_reserved_segment.start + lower_reserved_segment.length);
        current_segment.remove_above(upper_reserved_segment.start);

        if (current_segment.length == 0) {
            return self.next();
        }

        return current_segment;
    }

    fn reset(self: *SafeMemorySegmentIterator) void {
        self.memory_entry_iterator.reset();
        self.current_segment = null;
        self.iter_location = 0;
    }
};

const PageStatusType = enum {
    Free,
    Used,
    PMMDescriptor,
    BoostrapData,
};

const PageStatus = struct {
    status: PageStatusType,
};

const MemorySegmentDescription = struct {
    segment: Segment,
    pageStatuses: []PageStatus,
    pages: [][4096]u8,
    firstPageStatus: [1]PageStatus,
    fn init(self: *MemorySegmentDescription, segment: Segment) void {
        self.segment = segment;

        const pagePtr: [*][4096]u8 = @ptrFromInt(segment.start);
        self.pages = pagePtr[0..(self.segment.length / 4096)];

        const pageStatusesStart = @intFromPtr(&self.firstPageStatus);
        const pageStatusesStartPtr: [*]PageStatus = @ptrFromInt(pageStatusesStart);

        self.pageStatuses = pageStatusesStartPtr[0..self.pages.len];
        for (self.pageStatuses) |*pagestatus| {
            pagestatus.status = PageStatusType.Free;
        }

        const usedBytesForDescription = @sizeOf(MemorySegmentDescription) + self.pageStatuses.len * @sizeOf(PageStatus);

        for (0..(usedBytesForDescription / 4096 + 1)) |pageIndex| {
            self.pageStatuses[pageIndex].status = PageStatusType.BoostrapData;
        }
    }

    fn reservePage(self: *MemorySegmentDescription) ?PhysicalPointer([512]u64) {
        for (self.pageStatuses, 0..) |*pageStatus, index| {
            if (pageStatus.status == PageStatusType.Free) {
                pageStatus.status = PageStatusType.Used;
                return PhysicalPointer([512]u64).init(@intFromPtr(&self.pages[index]));
            }
        }
        return null;
    }

    fn freePage(self: *MemorySegmentDescription, page: PhysicalPointer([512]u64)) void {
        const pageIndex = (page.address - self.segment.start) / 4096;
        if (!self.pageStatuses[pageIndex].status == PageStatusType.Free) {
            panic_helper.kernel_panic("Tried to free non used page");
        }
        self.pageStatuses[pageIndex].status = PageStatusType.Free;
    }
};

fn compare_segment_base_address(segment_a: *const Segment, segment_b: *const Segment) i32 {
    if (segment_a.start > segment_b.start) {
        return 1;
    } else if (segment_a.start == segment_b.start) {
        return 0;
    } else {
        return -1;
    }
}

fn sort_segments_and_consolidate(segments: []Segment) []Segment {
    sorting.bubbleSort(Segment, segments, compare_segment_base_address);
    var segment_i: usize = 0;
    var next_segment_i: usize = 0;
    while (segment_i < segments.len) {
        next_segment_i += 1;
        for (segments[segment_i + 1 .. segments.len]) |*inner_segment| {
            if (segments[segment_i].merge(inner_segment.*)) |merged| {
                next_segment_i += 1;
                segments[segment_i] = merged;
                inner_segment.* = Segment.null_segment();
                continue;
            }
            break;
        }
        segment_i = next_segment_i;
    }

    var correct_length: usize = 0;
    for (0..segments.len) |i| {
        if (segments[i].length == 0) {
            continue;
        }
        segments[correct_length] = segments[i];
        if (correct_length != i) {
            segments[i] = Segment.null_segment();
        }
        correct_length += 1;
    }
    return segments[0..correct_length];
}

pub const PhysicalMemoryManager = struct {
    memory_sections: []*MemorySegmentDescription,
    pub fn init(memory_entry_iterator: *multiboot.MemoryEntryIterator, reserved_segments: []Segment) PhysicalMemoryManager {
        var ordered_reserved_segments = sort_segments_and_consolidate(reserved_segments);
        const bootstrap_memory_section = find_bootstrap_memory_segment(memory_entry_iterator, ordered_reserved_segments);

        reserved_segments[reserved_segments.len - 1] =
            Segment.init(bootstrap_memory_section.start, MINIMUM_BOOTSTRAP_SECTION);

        var memory_sections: [*]*MemorySegmentDescription = @as([*]*MemorySegmentDescription, @ptrFromInt(bootstrap_memory_section.start));

        ordered_reserved_segments = sort_segments_and_consolidate(reserved_segments);

        memory_entry_iterator.reset();
        var safe_segment_iterator = SafeMemorySegmentIterator.init(memory_entry_iterator.*, ordered_reserved_segments);

        var count: usize = 0;
        while (safe_segment_iterator.next()) |segment| {
            var segment_copy = segment;
            segment_copy.align_forward_base(4096);
            segment_copy.align_backward_end(4096);
            if (segment_copy.length > 0) {
                memory_sections[count] = @ptrFromInt(segment_copy.start);
                memory_sections[count].init(segment_copy);
                count += 1;
            }
        }

        for (memory_sections[0..count]) |memory_section| {
            console.printf("start: {X}, length: {X}\n", .{ memory_section.segment.start, memory_section.segment.length });
        }

        return .{
            .memory_sections = memory_sections[0..count],
        };
    }

    fn find_bootstrap_memory_segment(memory_entry_iterator: *multiboot.MemoryEntryIterator, sorted_reserved_segments: []Segment) Segment {
        var safe_segment_iterator = SafeMemorySegmentIterator.init(memory_entry_iterator.*, sorted_reserved_segments);

        safe_segment_iterator.reset();

        while (safe_segment_iterator.next()) |segment| {
            var segment_copy = segment;
            segment_copy.align_forward_base(4096);
            segment_copy.align_backward_end(4096);
            //TODO: calculate the minimum size from the number of entries
            if (segment_copy.length > MINIMUM_BOOTSTRAP_SECTION and segment.start > 100000) {
                return segment_copy;
            }
        }
        panic_helper.kernel_panic("Could not find suitable bootstrap memory segment");
    }

    pub fn reserve_exclusive_page(self: *PhysicalMemoryManager) PhysicalPointer([512]u64) {
        for (self.memory_sections) |memory_section| {
            if (memory_section.reservePage()) |reserved_page| {
                return reserved_page;
            }
        }
        panic_helper.kernel_panic("Could not reserve exclusive page");
    }

    pub fn free_exclusive_page(self: *PhysicalMemoryManager, page: *[4096]u8) void {
        for (self.memory_sections) |memory_section| {
            if (memory_section.segment.contains(@intFromPtr(page))) {
                memory_section.freePage(@ptrCast(page));
                return;
            }
        }
        panic_helper.kernel_panic("Tried to free non reserved page");
    }
};

pub const MemorySectionManager = struct {
    location: Segment,
    next_memory_manager: *?MemorySectionManager,

    fn from_bootstrap(bootstrap_segment: *MemorySegmentDescription) MemorySectionManager {
        return .{
            .location = bootstrap_segment.segment,
        };
    }

    fn set_next(self: *MemorySectionManager, next: *MemorySectionManager) {
        self.next_memory_manager = next;
    }
};

//allocate space for initializing memory segment managers
//copy all the old memory segment usage data
//override all BoostrapData type to Free
pub const PMM = struct {
    memory_sections: *MemorySectionManager,
    fn init(bootstrap: *PhysicalMemoryManager, vmm: BootstrapVMM, virtual_start: usize) void {
        var current_virtual_offset = virtual_start;
        var current_physical_address: usize = bootstrap.reserve_exclusive_page();

        const first_memory_section = PhysicalPointer(MemorySectionManager).init(current_physical_address);
        const virtual_first_memory_section = @as(*MemorySectionManager, @ptrFromInt(current_virtual_offset));
        first_memory_section.as_ptr().* = MemorySectionManager.init();

        var current_memory_section = first_memory_section;
        var virtual_current_memory_section = virtual_first_memory_section;

        for (bootstrap.memory_sections) |memory_section| {
            current_memory_section.as_ptr().set_next(next: *MemorySectionManager)
            
            current_memory_section.as_ptr() = MemorySectionManager.from_bootstrap(memory_section);
            virtual_current_memory_section = 
        }

        return PMM{
            .memory_sections = virtual_memory_sections,
        };
    }
};

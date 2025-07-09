const mem = @import("std").mem;
const alignment = @import("./alignment.zig");
const Segment = @import("./segment_lib.zig").Segment;

pub const MultibootHeader = packed struct {
    magic: u32,
    architecture: u32,
    header_length: u32,
    checksum: u32,
    pub fn create(architecture: Multiboot2Architecture, totalSize: u32) MultibootHeader {
        var header: MultibootHeader = .{
            .magic = 0xE85250D6,
            .architecture = @intFromEnum(architecture),
            .header_length = totalSize,
            .checksum = 0,
        };
        header.checksum = @bitCast(-@as(i32, @bitCast(header.magic + header.architecture + header.header_length)));
        return header;
    }
};

pub const Multiboot2Architecture = enum(u32) {
    i386ProtectedMode = 0,
};

pub const MultibootHeaderTagType = enum(u16) {
    SentinelTag = 0,
    InformationRequest = 1,
};

const GeneralMultibootHeaderTag = packed struct {
    type: MultibootHeaderTagType,
    flags: u16,
    size: u32,
};

pub const InformationRequestTag = struct {
    generalTagHeader: GeneralMultibootHeaderTag,
    mbi_tag_types: []const u32,
    pub fn create(flags: u16, mbi_tag_types: []const u32) InformationRequestTag {
        return .{
            .generalTagHeader = .{
                .type = MultibootHeaderTagType.InformationRequest,
                .flags = flags,
                .size = @sizeOf(GeneralMultibootHeaderTag) + @sizeOf(u32) * mbi_tag_types.len,
            },
            .mbi_tag_types = mbi_tag_types,
        };
    }
};

pub const SentinelHeaderTag = packed struct {
    generalTagHeader: GeneralMultibootHeaderTag,
    pub fn create() SentinelHeaderTag {
        return .{
            .generalTagHeader = .{
                .type = MultibootHeaderTagType.SentinelTag,
                .flags = 0,
                .size = @sizeOf(SentinelHeaderTag),
            },
        };
    }
};

pub fn calculateMultibootSize(comptime tags: anytype) usize {
    var currentSize: usize = 16;
    for (tags) |tag| {
        if (currentSize % 8 != 0) {
            currentSize += 8 - (currentSize % 8);
        }
        currentSize += tag.generalTagHeader.size;
    }
    return currentSize;
}

pub fn createMultiboot2Header(architecture: Multiboot2Architecture, comptime tags: anytype) [calculateMultibootSize(tags)]u8 {
    var buffer: [calculateMultibootSize(tags)]u8 = undefined;
    const header = MultibootHeader.create(architecture, calculateMultibootSize(tags));
    mem.copyForwards(u8, &buffer, mem.asBytes(&header));
    var cursor: usize = @sizeOf(MultibootHeader);
    for (tags) |tag| {
        if (cursor % 8 != 0) {
            cursor += 8 - (cursor % 8);
        }
        if (tag.generalTagHeader.type != MultibootHeaderTagType.InformationRequest) {
            mem.copyForwards(u8, buffer[cursor..], mem.asBytes(&tag));
        } else {
            mem.copyForwards(u8, buffer[cursor..], mem.asBytes(&tag.generalTagHeader));
            mem.copyForwards(u8, buffer[cursor + @sizeOf(GeneralMultibootHeaderTag) ..], mem.sliceAsBytes(tag.mbi_tag_types));
        }
        cursor += tag.generalTagHeader.size;
    }
    return buffer;
}

pub const BootInformationTagType = enum(u32) {
    MemoryMap = 6,
};

const BasicTag = packed struct {
    type: BootInformationTagType,
    size: u32,
};

pub const MemoryEntryType = enum(u32) {
    Available = 1,
    HoldACPIInfo = 3,
    Reserved = 4,
    Defective = 5,
};

pub const MemoryEntry = packed struct {
    base_address: u64,
    length: u64,
    type: MemoryEntryType,
    reserved: u32,
};

pub const MemoryMapTag = packed struct {
    type: u32,
    size: u32,
    entry_size: u32,
    entry_version: u32,
    pub fn enum_memory_entries(self: *align(8) const MemoryMapTag) MemoryEntryIterator {
        return MemoryEntryIterator.from_memory_map_tag(self);
    }
};

pub const MemoryEntryIterator = struct {
    memory_entry_tag: *align(8) const MemoryMapTag,
    current_memory_entry: *align(8) const MemoryEntry,

    fn from_memory_map_tag(basic_tag_ptr: *align(8) const MemoryMapTag) MemoryEntryIterator {
        return .{
            .memory_entry_tag = @ptrCast(basic_tag_ptr),
            .current_memory_entry = @ptrFromInt(@intFromPtr(basic_tag_ptr) + @sizeOf(MemoryMapTag)),
        };
    }

    pub fn next(self: *MemoryEntryIterator) ?*align(8) const MemoryEntry {
        if (@intFromPtr(self.current_memory_entry) < @intFromPtr(self.memory_entry_tag) + self.memory_entry_tag.size) {
            defer self.current_memory_entry = @ptrFromInt(@intFromPtr(self.current_memory_entry) + self.memory_entry_tag.entry_size);
            return self.current_memory_entry;
        }
        return null;
    }

    pub fn reset(self: *MemoryEntryIterator) void {
        self.current_memory_entry = @ptrFromInt(@intFromPtr(self.memory_entry_tag) + @sizeOf(MemoryMapTag));
    }
};

const AlignedBasicTagPtr = *align(8) const BasicTag;

const TagIterator = struct {
    current_tag: *align(8) const BasicTag,
    end: *const void,

    pub fn from_multiboot_info(multiboot_info_ptr: *const MultibootInfo) TagIterator {
        return TagIterator{
            .current_tag = @ptrFromInt(@intFromPtr(multiboot_info_ptr) + @sizeOf(MultibootInfo)),
            .end = @ptrFromInt(@intFromPtr(multiboot_info_ptr) + multiboot_info_ptr.total_size),
        };
    }

    pub fn next(self: *TagIterator) ?AlignedBasicTagPtr {
        while (@intFromPtr(self.current_tag) < @intFromPtr(self.end)) : ({
            self.current_tag = self.next_tag();
        }) {
            defer self.current_tag = self.next_tag();
            return self.current_tag;
        }
        return null;
    }

    fn next_tag(self: *const TagIterator) AlignedBasicTagPtr {
        return alignment.asForwardAlignedPtr(AlignedBasicTagPtr, @intFromPtr(self.current_tag) + self.current_tag.size);
    }
};

pub const MultibootInfo = packed struct {
    total_size: u32,
    reserved: u32,
    pub fn from(initial_ebx: u32) *MultibootInfo {
        return @ptrFromInt(initial_ebx);
    }

    pub fn enum_all_tags(self: *MultibootInfo) TagIterator {
        return TagIterator.from_multiboot_info(self);
    }

    pub fn get_tags_reserved_segment(self: *MultibootInfo) Segment {
        return Segment.init(@intFromPtr(self), self.total_size);
    }
};

const expect = @import("std").testing.expect;

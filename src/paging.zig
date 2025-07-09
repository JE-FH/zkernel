const PhysicalPointer = @import("./physical_memory_manager.zig").PhysicalPointer;

pub const PageDirectoryEntry = packed struct {
    present: u1,
    writeable: u1,
    userModeAccessible: u1,
    pageWriteThrough: u1,
    pageCacheDisable: u1,
    accessed: u1,
    ignore1: u1,
    always1: u1 = 1,
    ignore2: u4,
    pageTableEntryAddress: u20,
    pub fn non_present() PageDirectoryEntry {
        return .{
            .present = 0,
            .writeable = 0,
            .userModeAccessible = 0,
            .pageWriteThrough = 0,
            .pageCacheDisable = 0,
            .accessed = 0,
            .ignore1 = 0,
            .always1 = 0,
            .ignore2 = 0,
            .pageTableEntryAddress = 0,
        };
    }

    pub fn from_page_table_address(address: usize, writeable: bool, userModeAccessible: bool) PageDirectoryEntry {
        return .{
            .present = 1,
            .writeable = if (writeable) 1 else 0,
            .userModeAccessible = if (userModeAccessible) 1 else 0,
            .pageWriteThrough = 0,
            .pageCacheDisable = 0,
            .accessed = 0,
            .ignore1 = 0,
            .ignore2 = 0,
            .pageTableEntryAddress = @intCast((address >> 12) & 0xFFFFF),
        };
    }

    pub fn get_page_table_physical(self: PageDirectoryEntry) PhysicalPointer(PageTable) {
        return PhysicalPointer(PageTable).init(@as(usize, self.pageTableEntryAddress) << 12);
    }
};

pub const PageTableEntry = packed struct {
    present: u1,
    writeable: u1,
    userModeAccessible: u1,
    pageWriteThrough: u1,
    pageCacheDisable: u1,
    accessed: u1,
    dirty: u1,
    pat: u1,
    global: u1,
    ignored: u2,
    udReserved: u1,
    pageAddress: u20,
    pub fn non_present() PageTableEntry {
        return .{
            .present = 0,
            .writeable = 0,
            .userModeAccessible = 0,
            .pageWriteThrough = 0,
            .pageCacheDisable = 0,
            .accessed = 0,
            .dirty = 0,
            .pat = 0,
            .global = 0,
            .ignored = 0,
            .udReserved = 0,
            .pageAddress = 0,
        };
    }

    pub fn from_physical_page_address(address: usize, writeable: bool, userModeAccesible: bool) PageTableEntry {
        return .{
            .present = 1,
            .writeable = if (writeable) 1 else 0,
            .userModeAccessible = if (userModeAccesible) 1 else 0,
            .pageWriteThrough = 0,
            .pageCacheDisable = 0,
            .accessed = 0,
            .dirty = 0,
            .pat = 0,
            .global = 0,
            .ignored = 0,
            .udReserved = 1,
            .pageAddress = @intCast((address >> 12) & 0xFFFFF),
        };
    }
};

pub const PageTable = struct {
    page_table_entries: [1024]PageTableEntry,
    pub fn reset(self: *volatile PageTable) void {
        for (&self.page_table_entries) |*entry| {
            entry.* = PageTableEntry.non_present();
        }
    }
};

pub const PageDirectory = struct {
    entries: [1024]PageDirectoryEntry,
    pub fn reset(self: *volatile PageDirectory) void {
        for (&self.entries) |*entry| {
            entry.* = PageDirectoryEntry.non_present();
        }
    }
};

pub fn setPageDirectory(pageDirectoryEntries: *PageDirectory) !void {
    if (@intFromPtr(pageDirectoryEntries) % 1024 != 0) {
        return error.UnalignedPageDirectoryTable;
    }
    asm volatile (
        \\mov %eax, %cr3
        :
        : [pageDirectoryEntries] "{eax}" (pageDirectoryEntries),
        : "cr3"
    );
}

pub fn enablePaging() void {
    asm volatile (
        \\movl %cr0, %eax
        \\orl $0x80000000, %eax
        \\movl %eax, %cr0
        ::: "cr3", "eax");
}

const PhysicalMemoryManager = @import("./physical_memory_manager.zig").PhysicalMemoryManager;
const PhysicalPointer = @import("./physical_memory_manager.zig").PhysicalPointer;
const math = @import("std").math;
const panic_helper = @import("panic_helper.zig");
const console = @import("console.zig");
const PageDirectoryEntry = @import("paging.zig").PageDirectoryEntry;
const PageDirectory = @import("paging.zig").PageDirectory;
const PageTableEntry = @import("paging.zig").PageTableEntry;
const PageTable = @import("paging.zig").PageTable;

pub const MemorySegmentType = enum { KERNEL_DYNAMIC, KERNEL_STATIC };

const VirtualAddress = packed struct {
    page_offset: u12,
    page_table_index: u10,
    page_directory_index: u10,

    pub fn from_address(address: usize) VirtualAddress {
        return @bitCast(address);
    }

    pub fn from_ptr(ptr: anytype) VirtualAddress {
        return @bitCast(@intFromPtr(ptr));
    }
};

pub const BootstrapVMM = struct {
    physical_memory_manager: *PhysicalMemoryManager,
    page_directory: PhysicalPointer(PageDirectory),
    virtual_page_tables: *volatile [1024]PageTable,
    virtual_page_directory: *volatile PageDirectory,
    pub fn init(physical_memory_manager: *PhysicalMemoryManager, vmm_reserved_directory_entry: usize) BootstrapVMM {
        const page_directory: *PageDirectory = @ptrCast(@alignCast(physical_memory_manager.reserve_exclusive_page().as_ptr()));
        page_directory.reset();

        const reserved_page_table: *PageTable = @ptrCast(@alignCast(physical_memory_manager.reserve_exclusive_page().as_ptr()));
        page_directory.entries[vmm_reserved_directory_entry] = PageDirectoryEntry.from_page_table_address(@intFromPtr(reserved_page_table), true, false);
        reserved_page_table.reset();
        for (&reserved_page_table.page_table_entries) |*entry| {
            entry.*.udReserved = 1;
        }

        const other_page_table: *PageTable = @ptrCast(@alignCast(physical_memory_manager.reserve_exclusive_page().as_ptr()));
        other_page_table.reset();
        page_directory.entries[vmm_reserved_directory_entry + 1] = PageDirectoryEntry.from_page_table_address(@intFromPtr(other_page_table), true, false);
        other_page_table.page_table_entries[0] = PageTableEntry.from_physical_page_address(@intFromPtr(page_directory), true, false);

        return BootstrapVMM{
            .physical_memory_manager = physical_memory_manager,
            .page_directory = PhysicalPointer(PageDirectory).init(@intFromPtr(page_directory)),
            .virtual_page_tables = @ptrFromInt(vmm_reserved_directory_entry << 22),
            .virtual_page_directory = @ptrFromInt((vmm_reserved_directory_entry + 1) << 22),
        };
    }

    pub fn get_physical_page_directory(self: BootstrapVMM) PhysicalPointer(PageDirectory) {
        return self.page_directory;
    }

    pub fn map(self: *BootstrapVMM, physical: usize, virtual: usize, writeable: bool, user_mode_access: bool) void {
        self._map(VirtualAddress.from_address(virtual), PageTableEntry.from_physical_page_address(physical, writeable, user_mode_access));
    }

    fn _map(self: *BootstrapVMM, virtual: VirtualAddress, new_pte: PageTableEntry) void {
        if (self.page_directory.as_ptr().entries[virtual.page_directory_index].present == 0) {
            const table = PhysicalPointer(PageTable).init(self.physical_memory_manager.reserve_exclusive_page().address);
            table.as_ptr().reset();
            self.page_directory.as_ptr().entries[virtual.page_directory_index] = PageDirectoryEntry.from_page_table_address(table.address, true, false);

            const something: PhysicalPointer(PageTable) = self.page_directory.as_ptr().entries[self._get_reserved_table_index()].get_page_table_physical();
            something.as_ptr().page_table_entries[virtual.page_directory_index] = PageTableEntry.from_physical_page_address(table.address, true, false);
        }

        const target_page_table = self.page_directory.as_ptr().entries[virtual.page_directory_index];
        const page_table: PhysicalPointer(PageTable) = target_page_table.get_page_table_physical();
        page_table.as_ptr().page_table_entries[virtual.page_table_index] = new_pte;
    }

    fn _get_reserved_table_index(self: *BootstrapVMM) usize {
        return @intFromPtr(self.virtual_page_tables) >> 22;
    }
};

pub const VMM = struct {
    physical_memory_manager: *PhysicalMemoryManager,
    page_directory: *volatile PageDirectory,
    page_tables: *volatile [1024]PageTable,
    page_directory_physical_address: PhysicalPointer(PageDirectory),
    pub fn init(bootstrap_virtual_memory_manager: BootstrapVMM) VMM {
        return VMM{
            .physical_memory_manager = bootstrap_virtual_memory_manager.physical_memory_manager,
            .page_directory = bootstrap_virtual_memory_manager.virtual_page_directory,
            .page_tables = bootstrap_virtual_memory_manager.virtual_page_tables,
            .page_directory_physical_address = bootstrap_virtual_memory_manager.page_directory,
        };
    }

    pub fn get_physical_page_directory(self: VMM) PhysicalPointer(PageDirectory) {
        return self.page_directory_physical_address;
    }

    pub fn map(self: *VMM, physical: usize, virtual: usize, writeable: bool, user_mode_access: bool) void {
        return self._map(PhysicalPointer([512]u64).init(physical), VirtualAddress.from_address(virtual), writeable, user_mode_access);
    }

    fn _map(self: *VMM, physical: PhysicalPointer([512]u64), virtual: VirtualAddress, writeable: bool, user_mode_access: bool) void {
        if (self.page_directory.entries[virtual.page_directory_index].present == 0) {
            const allocated = self.physical_memory_manager.reserve_exclusive_page();
            self.page_tables[self._get_reserved_table_index()].page_table_entries[virtual.page_directory_index] = PageTableEntry.from_physical_page_address(allocated.address, true, false);
            self.page_directory.entries[virtual.page_directory_index] = PageDirectoryEntry.from_page_table_address(allocated.address, true, false);
            self.page_tables[virtual.page_directory_index].reset();
        }
        self.page_tables[virtual.page_directory_index].page_table_entries[virtual.page_table_index] = PageTableEntry.from_physical_page_address(physical.address, writeable, user_mode_access);
    }

    fn _get_reserved_table_index(self: *VMM) usize {
        return @intFromPtr(self.page_tables) >> 22;
    }
};

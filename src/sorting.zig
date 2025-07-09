pub fn bubbleSort(comptime T: type, data: []T, comparer: fn (a: *const T, b: *const T) i32) void {
    if (data.len < 2) {
        return;
    }
    while (true) {
        var swapped = false;
        for (1..data.len) |i| {
            const comparison = comparer(&data[i - 1], &data[i]);
            if (comparison > 0) {
                const temp = data[i];
                data[i] = data[i - 1];
                data[i - 1] = temp;
                swapped = true;
            }
        }
        if (!swapped) break;
    }
}

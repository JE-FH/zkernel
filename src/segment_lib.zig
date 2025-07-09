const alignment = @import("./alignment.zig");

pub const Segment = struct {
    start: usize,
    length: usize,
    pub fn init(start: usize, length: usize) Segment {
        return .{ .start = start, .length = length };
    }

    pub fn from_begin_end(begin: usize, end: usize) Segment {
        return .{ .start = begin, .length = end - begin };
    }

    pub fn null_segment() Segment {
        return .{ .start = 0, .length = 0 };
    }

    pub fn remove_below(self: *Segment, lower_limit: usize) void {
        if (self.start >= lower_limit) {
            return;
        }

        if (self.start + self.length <= lower_limit) {
            self.start = 0;
            self.length = 0;
            return;
        }

        self.length = self.length - (lower_limit - self.start);
        self.start = lower_limit;
    }

    pub fn remove_above(self: *Segment, upper_limit: usize) void {
        if (self.start + self.length <= upper_limit) {
            return;
        }

        if (self.start >= upper_limit) {
            self.start = 0;
            self.length = 0;
            return;
        }

        self.length = self.length - ((self.start + self.length) - upper_limit);
    }

    pub fn align_forward_base(self: *Segment, align_by: usize) void {
        const aligned = alignment.asForwardAligned(self.start, align_by);
        self.remove_below(aligned);
    }

    pub fn align_backward_end(self: *Segment, align_by: usize) void {
        const aligned_end = alignment.asBackwardAligned(self.start + self.length, align_by);
        self.remove_above(aligned_end);
    }

    pub fn intersects(self: Segment, other: Segment) bool {
        return (self.start < other.start + other.length and self.start + self.length > other.start);
    }

    pub fn merge(self: Segment, other: Segment) ?Segment {
        if (!self.intersects(other)) {
            return null;
        }
        const new_lower = @min(self.start, other.start);
        const new_upper = @max(self.start + self.length, other.start + other.length);
        return Segment.from_begin_end(new_lower, new_upper);
    }

    pub fn contains(self: Segment, address: usize) bool {
        return self.start <= address and self.start + self.length > address;
    }
};

const expect = @import("std").testing.expect;

test "Segment remove below" {
    var segment = Segment.init(0, 320);
    segment.remove_below(234);
    try expect(segment.start == 234);
    try expect(segment.length == 86);

    segment = Segment.init(304, 42023);
    segment.remove_below(5034);
    try expect(segment.start == 5034);
    try expect(segment.length == 37293);

    segment = Segment.init(20402, 30);
    segment.remove_below(20433);
    try expect(segment.length == 0);
}

test "Segment remove above" {
    var segment = Segment.init(1234, 1000);
    segment.remove_above(2000);
    try expect(segment.start == 1234);
    try expect(segment.length == 766);

    segment = Segment.init(2134, 120);
    segment.remove_above(2000);
    try expect(segment.length == 0);
}

test "Segment align forward base" {
    var segment = Segment.init(1234, 10000);
    segment.align_forward_base(4096);
    try expect(segment.start == 4096);
    try expect(segment.length == 7138);

    segment = Segment.init(4096, 3000);
    segment.align_forward_base(4096);
    try expect(segment.start == 4096);
    try expect(segment.length == 3000);
}

test "Intersect test" {
    var segment_a = Segment.init(4000, 1000);
    var segment_b = Segment.init(5000, 1000);
    try expect(!segment_a.intersects(segment_b));
    try expect(!segment_b.intersects(segment_a));

    segment_a = Segment.init(4000, 1001);
    segment_b = Segment.init(5000, 1000);
    try expect(segment_a.intersects(segment_b));
    try expect(segment_b.intersects(segment_a));

    segment_a = Segment.init(4000, 1000);
    segment_b = Segment.init(4000, 1000);
    try expect(segment_a.intersects(segment_b));
    try expect(segment_b.intersects(segment_a));

    segment_a = Segment.init(3999, 1002);
    segment_b = Segment.init(4000, 1000);
    try expect(segment_a.intersects(segment_b));
    try expect(segment_b.intersects(segment_a));
}

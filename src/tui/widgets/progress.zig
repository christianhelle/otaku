const std = @import("std");

pub const ProgressBar = struct {
    label: []const u8 = "",
    current: u32 = 0,
    total: u32 = 100,
    width: u16 = 40,

    pub fn render(self: ProgressBar, writer: anytype) !void {
        const bar_width: usize = if (self.width > 10) self.width - 10 else 4;
        const filled: usize = if (self.total > 0)
            @intCast(@min(@as(u64, self.current) * bar_width / self.total, bar_width))
        else
            0;
        const empty: usize = if (bar_width > filled) bar_width - filled else 0;

        try writer.writeAll("[");
        var i: usize = 0;
        while (i < filled) : (i += 1) try writer.writeAll("█");
        i = 0;
        while (i < empty) : (i += 1) try writer.writeAll("░");
        try writer.print("] {d}/{d}", .{ self.current, self.total });
        if (self.label.len > 0) {
            try writer.writeByte(' ');
            try writer.writeByte('"');
            try writer.writeAll(self.label);
            try writer.writeByte('"');
        }
    }
};

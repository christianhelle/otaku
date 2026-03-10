const std = @import("std");
const layout = @import("../layout.zig");
const Rect = layout.Rect;

pub const TableWidget = struct {
    headers: []const []const u8 = &.{},
    rows: []const []const []const u8 = &.{},
    selected: usize = 0,
    rect: Rect,

    pub fn init(rect: Rect) TableWidget {
        return .{ .rect = rect };
    }

    pub fn render(self: TableWidget, writer: anytype) !void {
        if (self.rect.width < 2 or self.rect.height < 2) return;
        // Minimal: just draw a border
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y, self.rect.x });
        const iw: usize = self.rect.width - 2;
        try writer.writeAll("┌");
        var i: usize = 0;
        while (i < iw) : (i += 1) try writer.writeAll("─");
        try writer.writeAll("┐");
        var row: usize = 1;
        while (row < self.rect.height - 1) : (row += 1) {
            try writer.print("\x1b[{d};{d}H", .{ self.rect.y + row, self.rect.x });
            try writer.writeAll("│");
            i = 0;
            while (i < iw) : (i += 1) try writer.writeByte(' ');
            try writer.writeAll("│");
        }
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y + self.rect.height - 1, self.rect.x });
        try writer.writeAll("└");
        i = 0;
        while (i < iw) : (i += 1) try writer.writeAll("─");
        try writer.writeAll("┘");
    }
};

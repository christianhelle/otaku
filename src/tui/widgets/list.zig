const std = @import("std");
const layout = @import("../layout.zig");
const Rect = layout.Rect;

fn truncateUtf8(s: []const u8, max_bytes: usize) []const u8 {
    if (s.len <= max_bytes) return s;
    var i: usize = max_bytes;
    while (i > 0 and (s[i] & 0xC0) == 0x80) : (i -= 1) {}
    return s[0..i];
}

pub const ListWidget = struct {
    items: []const []const u8,
    selected: usize = 0,
    scroll_offset: usize = 0,
    rect: Rect,
    title: ?[]const u8 = null,

    pub fn init(items: []const []const u8, rect: Rect) ListWidget {
        return .{ .items = items, .rect = rect };
    }

    pub fn moveUp(self: *ListWidget) void {
        if (self.selected > 0) {
            self.selected -= 1;
            if (self.selected < self.scroll_offset) {
                self.scroll_offset = self.selected;
            }
        }
    }

    pub fn moveDown(self: *ListWidget) void {
        if (self.selected + 1 < self.items.len) {
            self.selected += 1;
            const visible = visibleRows(self.rect);
            if (self.selected >= self.scroll_offset + visible) {
                self.scroll_offset = self.selected - visible + 1;
            }
        }
    }

    pub fn getSelected(self: ListWidget) ?[]const u8 {
        if (self.items.len == 0) return null;
        return self.items[self.selected];
    }

    pub fn render(self: ListWidget, writer: anytype) !void {
        if (self.rect.width < 2 or self.rect.height < 2) return;
        const iw: usize = self.rect.width - 2;
        const ih: usize = visibleRows(self.rect);

        // Top border
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y, self.rect.x });
        try writer.writeAll("┌");
        if (self.title) |t| {
            const td = truncateUtf8(t, if (iw > 4) iw - 4 else 0);
            try writer.writeAll("─ ");
            try writer.writeAll(td);
            try writer.writeAll(" ");
            var filled: usize = td.len + 3;
            while (filled < iw) : (filled += 1) try writer.writeAll("─");
        } else {
            var i: usize = 0;
            while (i < iw) : (i += 1) try writer.writeAll("─");
        }
        try writer.writeAll("┐");

        // Content rows
        var row: usize = 0;
        while (row < ih) : (row += 1) {
            try writer.print("\x1b[{d};{d}H", .{ self.rect.y + 1 + row, self.rect.x });
            try writer.writeAll("│");
            const idx = self.scroll_offset + row;
            if (idx < self.items.len) {
                const item = self.items[idx];
                const sel = idx == self.selected;
                if (sel) try writer.writeAll("\x1b[7m");
                try writer.writeAll(if (sel) "> " else "  ");
                const max_len: usize = if (iw >= 2) iw - 2 else 0;
                const disp = truncateUtf8(item, max_len);
                try writer.writeAll(disp);
                var pad: usize = disp.len + 2;
                while (pad < iw) : (pad += 1) try writer.writeByte(' ');
                if (sel) try writer.writeAll("\x1b[0m");
            } else {
                var i: usize = 0;
                while (i < iw) : (i += 1) try writer.writeByte(' ');
            }
            try writer.writeAll("│");
        }

        // Bottom border
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y + self.rect.height - 1, self.rect.x });
        try writer.writeAll("└");
        var i: usize = 0;
        while (i < iw) : (i += 1) try writer.writeAll("─");
        try writer.writeAll("┘");
    }
};

fn visibleRows(rect: Rect) usize {
    return if (rect.height >= 2) rect.height - 2 else 0;
}

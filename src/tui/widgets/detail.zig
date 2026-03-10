const std = @import("std");
const layout = @import("../../tui/layout.zig");
const Rect = layout.Rect;
const manga = @import("../../domain/manga.zig");
const MangaTitle = manga.MangaTitle;

fn truncateUtf8(s: []const u8, max_bytes: usize) []const u8 {
    if (s.len <= max_bytes) return s;
    var i: usize = max_bytes;
    while (i > 0 and (s[i] & 0xC0) == 0x80) : (i -= 1) {}
    return s[0..i];
}

pub const DetailWidget = struct {
    manga: ?*const MangaTitle = null,
    rect: Rect,

    pub fn init(rect: Rect) DetailWidget {
        return .{ .rect = rect };
    }

    pub fn setManga(self: *DetailWidget, m: *const MangaTitle) void {
        self.manga = m;
    }

    pub fn clear(self: *DetailWidget) void {
        self.manga = null;
    }

    pub fn render(self: DetailWidget, writer: anytype) !void {
        if (self.rect.width < 2 or self.rect.height < 2) return;
        const iw: usize = self.rect.width - 2;

        // Top border
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y, self.rect.x });
        try writer.writeAll("┌");
        var bi: usize = 0;
        while (bi < iw) : (bi += 1) try writer.writeAll("─");
        try writer.writeAll("┐");

        var row: usize = 1;
        const max_row = self.rect.height - 1;

        if (self.manga) |m| {
            row = try renderLine(writer, self.rect, row, max_row, iw, "Title:", m.title);
            if (m.author) |a| row = try renderLine(writer, self.rect, row, max_row, iw, "Author:", a);
            row = try renderLine(writer, self.rect, row, max_row, iw, "Status:", m.status.label());
            if (m.chapter_count) |cc| {
                var cbuf: [32]u8 = undefined;
                const cstr = std.fmt.bufPrint(&cbuf, "{d} chapters", .{cc}) catch "?";
                row = try renderLine(writer, self.rect, row, max_row, iw, "Chapters:", cstr);
            }
            if (m.genres.len > 0) {
                var gbuf: [128]u8 = undefined;
                var gfbs = std.io.fixedBufferStream(&gbuf);
                const gw = gfbs.writer();
                for (m.genres, 0..) |g, gi| {
                    if (gi > 0) gw.writeAll(", ") catch {};
                    gw.writeAll(g) catch {};
                }
                row = try renderLine(writer, self.rect, row, max_row, iw, "Genres:", gfbs.getWritten());
            }
            if (row < max_row) {
                // Blank separator
                try writer.print("\x1b[{d};{d}H", .{ self.rect.y + row, self.rect.x });
                try writer.writeAll("│");
                var pi: usize = 0;
                while (pi < iw) : (pi += 1) try writer.writeByte(' ');
                try writer.writeAll("│");
                row += 1;
            }
            if (m.summary) |summary| {
                row = try renderWrapped(writer, self.rect, row, max_row, iw, summary);
            }
        } else {
            row = try renderLine(writer, self.rect, row, max_row, iw, "", "No title selected");
        }

        // Fill remaining rows
        while (row < max_row) : (row += 1) {
            try writer.print("\x1b[{d};{d}H", .{ self.rect.y + row, self.rect.x });
            try writer.writeAll("│");
            var pi: usize = 0;
            while (pi < iw) : (pi += 1) try writer.writeByte(' ');
            try writer.writeAll("│");
        }

        // Bottom border
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y + self.rect.height - 1, self.rect.x });
        try writer.writeAll("└");
        var ei: usize = 0;
        while (ei < iw) : (ei += 1) try writer.writeAll("─");
        try writer.writeAll("┘");
    }
};

fn renderLine(
    writer: anytype,
    rect: Rect,
    row: usize,
    max_row: usize,
    iw: usize,
    label: []const u8,
    value: []const u8,
) !usize {
    if (row >= max_row) return row;
    try writer.print("\x1b[{d};{d}H", .{ rect.y + row, rect.x });
    try writer.writeAll("│");
    var col: usize = 0;
    if (label.len > 0) {
        const ld = truncateUtf8(label, iw);
        try writer.writeAll("\x1b[1m");
        try writer.writeAll(ld);
        try writer.writeAll("\x1b[0m ");
        col = ld.len + 1;
    }
    const remaining = if (iw > col) iw - col else 0;
    const vd = truncateUtf8(value, remaining);
    try writer.writeAll(vd);
    var pad: usize = col + vd.len;
    while (pad < iw) : (pad += 1) try writer.writeByte(' ');
    try writer.writeAll("│");
    return row + 1;
}

fn renderWrapped(
    writer: anytype,
    rect: Rect,
    start_row: usize,
    max_row: usize,
    iw: usize,
    text: []const u8,
) !usize {
    var row = start_row;
    var pos: usize = 0;
    while (pos < text.len and row < max_row) {
        const line_len = @min(iw, text.len - pos);
        const raw = text[pos .. pos + line_len];
        // Break at last space if possible
        var break_at: usize = raw.len;
        if (pos + line_len < text.len) {
            var si: usize = raw.len;
            while (si > 0) : (si -= 1) {
                if (raw[si - 1] == ' ') {
                    break_at = si;
                    break;
                }
            }
        }
        const line = raw[0..break_at];
        try writer.print("\x1b[{d};{d}H", .{ rect.y + row, rect.x });
        try writer.writeAll("│ ");
        const disp = truncateUtf8(line, if (iw >= 2) iw - 2 else 0);
        try writer.writeAll(disp);
        var pad: usize = disp.len + 2;
        while (pad < iw) : (pad += 1) try writer.writeByte(' ');
        try writer.writeAll("│");
        pos += break_at;
        if (pos < text.len and text[pos] == ' ') pos += 1;
        row += 1;
    }
    return row;
}

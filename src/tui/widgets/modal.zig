const std = @import("std");
const layout = @import("../layout.zig");
const Rect = layout.Rect;

pub const ModalWidget = struct {
    title: []const u8 = "",
    message: []const u8 = "",
    rect: Rect,

    pub fn init(rect: Rect) ModalWidget {
        return .{ .rect = rect };
    }

    pub fn render(self: ModalWidget, writer: anytype) !void {
        if (self.rect.width < 4 or self.rect.height < 4) return;
        const iw: usize = self.rect.width - 2;
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y, self.rect.x });
        try writer.writeAll("╔");
        var i: usize = 0;
        while (i < iw) : (i += 1) try writer.writeAll("═");
        try writer.writeAll("╗");
        var row: usize = 1;
        while (row < self.rect.height - 1) : (row += 1) {
            try writer.print("\x1b[{d};{d}H", .{ self.rect.y + row, self.rect.x });
            try writer.writeAll("║");
            i = 0;
            while (i < iw) : (i += 1) try writer.writeByte(' ');
            try writer.writeAll("║");
        }
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y + self.rect.height - 1, self.rect.x });
        try writer.writeAll("╚");
        i = 0;
        while (i < iw) : (i += 1) try writer.writeAll("═");
        try writer.writeAll("╝");
        // Title
        if (self.title.len > 0 and self.rect.height > 2) {
            try writer.print("\x1b[{d};{d}H", .{ self.rect.y + 1, self.rect.x + 2 });
            const td = if (self.title.len < iw) self.title else self.title[0..iw];
            try writer.writeAll("\x1b[1m");
            try writer.writeAll(td);
            try writer.writeAll("\x1b[0m");
        }
        // Message
        if (self.message.len > 0 and self.rect.height > 3) {
            try writer.print("\x1b[{d};{d}H", .{ self.rect.y + 2, self.rect.x + 2 });
            const md = if (self.message.len < iw) self.message else self.message[0..iw];
            try writer.writeAll(md);
        }
    }
};

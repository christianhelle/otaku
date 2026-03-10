const std = @import("std");
const layout = @import("../layout.zig");
const Rect = layout.Rect;

pub const StatusBar = struct {
    screen_name: []const u8 = "",
    item_count: u32 = 0,
    selected_item: u32 = 0,
    hint: []const u8 = "",
    loading: bool = false,
    rect: Rect,

    pub fn render(self: StatusBar, writer: anytype) !void {
        try writer.print("\x1b[{d};{d}H", .{ self.rect.y, self.rect.x });
        try writer.writeAll("\x1b[44m\x1b[97m"); // blue bg, bright white
        var col: usize = 0;
        const w: usize = self.rect.width;

        var buf: [256]u8 = undefined;
        const content = std.fmt.bufPrint(&buf, " [{s}] {d} items | #{d} | {s}{s}", .{
            self.screen_name,
            self.item_count,
            self.selected_item,
            self.hint,
            if (self.loading) " [loading...]" else "",
        }) catch " ";

        const disp = if (content.len <= w) content else content[0..w];
        try writer.writeAll(disp);
        col = disp.len;
        while (col < w) : (col += 1) try writer.writeByte(' ');
        try writer.writeAll("\x1b[0m");
    }
};

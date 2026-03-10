const std = @import("std");

pub const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,

    pub fn inner(self: Rect, margin: u16) Rect {
        const m2 = margin * 2;
        return .{
            .x = self.x + margin,
            .y = self.y + margin,
            .width = if (self.width > m2) self.width - m2 else 0,
            .height = if (self.height > m2) self.height - m2 else 0,
        };
    }

    pub fn splitHorizontal(self: Rect, left_width: u16) struct { left: Rect, right: Rect } {
        const lw = @min(left_width, self.width);
        const rw = if (self.width > lw) self.width - lw else 0;
        return .{
            .left = .{ .x = self.x, .y = self.y, .width = lw, .height = self.height },
            .right = .{ .x = self.x + lw, .y = self.y, .width = rw, .height = self.height },
        };
    }

    pub fn splitVertical(self: Rect, top_height: u16) struct { top: Rect, bottom: Rect } {
        const th = @min(top_height, self.height);
        const bh = if (self.height > th) self.height - th else 0;
        return .{
            .top = .{ .x = self.x, .y = self.y, .width = self.width, .height = th },
            .bottom = .{ .x = self.x, .y = self.y + th, .width = self.width, .height = bh },
        };
    }

    pub fn splitThreePane(self: Rect, left_pct: u8, right_pct: u8) struct { left: Rect, center: Rect, right: Rect } {
        const lw: u16 = @intCast(@as(u32, self.width) * left_pct / 100);
        const rw: u16 = @intCast(@as(u32, self.width) * right_pct / 100);
        const cw = if (self.width > lw + rw) self.width - lw - rw else 0;
        return .{
            .left = .{ .x = self.x, .y = self.y, .width = lw, .height = self.height },
            .center = .{ .x = self.x + lw, .y = self.y, .width = cw, .height = self.height },
            .right = .{ .x = self.x + lw + cw, .y = self.y, .width = rw, .height = self.height },
        };
    }
};

pub fn threePane(width: u16, height: u16) struct { left: Rect, center: Rect, right: Rect, statusbar: Rect } {
    const main_height: u16 = if (height > 1) height - 1 else height;
    const lw: u16 = @max(@as(u16, @intCast(@as(u32, width) * 20 / 100)), 16);
    const rw: u16 = @max(@as(u16, @intCast(@as(u32, width) * 30 / 100)), 20);
    const cw: u16 = if (width > lw + rw) width - lw - rw else 0;
    return .{
        .left = .{ .x = 1, .y = 1, .width = lw, .height = main_height },
        .center = .{ .x = 1 + lw, .y = 1, .width = cw, .height = main_height },
        .right = .{ .x = 1 + lw + cw, .y = 1, .width = rw, .height = main_height },
        .statusbar = .{ .x = 1, .y = height, .width = width, .height = 1 },
    };
}

pub fn twoPane(width: u16, height: u16) struct { main: Rect, statusbar: Rect } {
    const main_height: u16 = if (height > 1) height - 1 else height;
    return .{
        .main = .{ .x = 1, .y = 1, .width = width, .height = main_height },
        .statusbar = .{ .x = 1, .y = height, .width = width, .height = 1 },
    };
}

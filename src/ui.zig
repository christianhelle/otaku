const std = @import("std");
const manga = @import("manga.zig");
const database = @import("database.zig");

/// Application view state
pub const View = enum {
    library,
    search,
    chapter_list,
    reader,
};

/// UI state for the manga reader application.
/// Uses raylib for immediate-mode rendering when available.
pub const UI = struct {
    view: View = .library,
    search_buf: [256]u8 = [_]u8{0} ** 256,
    search_len: usize = 0,
    scroll_offset: f32 = 0,
    selected_manga_id: u64 = 0,
    selected_chapter_id: u64 = 0,
    current_page: u32 = 0,
    screen_width: i32 = 1280,
    screen_height: i32 = 720,

    pub fn navigateTo(self: *UI, view: View) void {
        self.view = view;
        self.scroll_offset = 0;
    }

    pub fn navigateBack(self: *UI) void {
        switch (self.view) {
            .library => {},
            .search => self.view = .library,
            .chapter_list => self.view = .library,
            .reader => self.view = .chapter_list,
        }
    }

    pub fn scroll(self: *UI, delta: f32) void {
        self.scroll_offset -= delta * 40;
        if (self.scroll_offset < 0) self.scroll_offset = 0;
    }

    pub fn setSearch(self: *UI, text: []const u8) void {
        const len = @min(text.len, self.search_buf.len - 1);
        @memcpy(self.search_buf[0..len], text[0..len]);
        self.search_buf[len] = 0;
        self.search_len = len;
    }

    pub fn getSearchQuery(self: *const UI) []const u8 {
        return self.search_buf[0..self.search_len];
    }

    pub fn selectManga(self: *UI, id: u64) void {
        self.selected_manga_id = id;
        self.view = .chapter_list;
        self.scroll_offset = 0;
    }

    pub fn selectChapter(self: *UI, id: u64) void {
        self.selected_chapter_id = id;
        self.current_page = 0;
        self.view = .reader;
    }

    pub fn nextPage(self: *UI, max_pages: u32) void {
        if (self.current_page + 1 < max_pages) {
            self.current_page += 1;
        }
    }

    pub fn prevPage(self: *UI) void {
        if (self.current_page > 0) {
            self.current_page -= 1;
        }
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "View enum values" {
    try std.testing.expectEqual(@as(u2, 0), @intFromEnum(View.library));
    try std.testing.expectEqual(@as(u2, 1), @intFromEnum(View.search));
    try std.testing.expectEqual(@as(u2, 2), @intFromEnum(View.chapter_list));
    try std.testing.expectEqual(@as(u2, 3), @intFromEnum(View.reader));
}

test "UI navigation" {
    var ui = UI{};
    try std.testing.expectEqual(View.library, ui.view);

    ui.navigateTo(.search);
    try std.testing.expectEqual(View.search, ui.view);

    ui.navigateBack();
    try std.testing.expectEqual(View.library, ui.view);

    ui.navigateTo(.chapter_list);
    ui.navigateBack();
    try std.testing.expectEqual(View.library, ui.view);

    ui.navigateTo(.reader);
    ui.navigateBack();
    try std.testing.expectEqual(View.chapter_list, ui.view);
}

test "UI search" {
    var ui = UI{};
    ui.setSearch("One Piece");
    try std.testing.expectEqualStrings("One Piece", ui.getSearchQuery());

    ui.setSearch("");
    try std.testing.expectEqual(@as(usize, 0), ui.getSearchQuery().len);
}

test "UI page navigation" {
    var ui = UI{};
    ui.current_page = 0;

    ui.nextPage(5);
    try std.testing.expectEqual(@as(u32, 1), ui.current_page);

    ui.nextPage(5);
    ui.nextPage(5);
    ui.nextPage(5);
    try std.testing.expectEqual(@as(u32, 4), ui.current_page);

    // Should not go past max
    ui.nextPage(5);
    try std.testing.expectEqual(@as(u32, 4), ui.current_page);

    ui.prevPage();
    try std.testing.expectEqual(@as(u32, 3), ui.current_page);

    // Should not go below 0
    ui.current_page = 0;
    ui.prevPage();
    try std.testing.expectEqual(@as(u32, 0), ui.current_page);
}

test "UI scroll" {
    var ui = UI{};
    ui.scroll(-1);
    try std.testing.expect(ui.scroll_offset > 0);

    // Scroll up should not go negative
    ui.scroll_offset = 10;
    ui.scroll(100);
    try std.testing.expectEqual(@as(f32, 0), ui.scroll_offset);
}

test "UI select manga and chapter" {
    var ui = UI{};
    ui.selectManga(42);
    try std.testing.expectEqual(@as(u64, 42), ui.selected_manga_id);
    try std.testing.expectEqual(View.chapter_list, ui.view);

    ui.selectChapter(7);
    try std.testing.expectEqual(@as(u64, 7), ui.selected_chapter_id);
    try std.testing.expectEqual(@as(u32, 0), ui.current_page);
    try std.testing.expectEqual(View.reader, ui.view);
}

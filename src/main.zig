/// Otaku – Desktop Manga Reader
/// Entry point and application game loop.
const std = @import("std");
const manga = @import("manga.zig");
const database = @import("database.zig");
const crawler = @import("crawler.zig");
const ui = @import("ui.zig");

// ---- Application state ----

const AppTab = enum(i32) { library = 0, search = 1, reading = 2, settings = 3 };

const SearchState = struct {
    query_buf: std.ArrayList(u8),
    query_cursor: usize = 0,
    results: []manga.Manga = &[_]manga.Manga{},
    searching: bool = false,
    scroll: i32 = 0,
    selected: i32 = -1,

    fn init(allocator: std.mem.Allocator) SearchState {
        _ = allocator;
        return .{ .query_buf = .empty };
    }

    fn deinit(self: *SearchState, allocator: std.mem.Allocator) void {
        self.query_buf.deinit(allocator);
        for (self.results) |*m| {
            var mutable = m.*;
            mutable.free(allocator);
        }
        allocator.free(self.results);
    }
};

const LibraryState = struct {
    manga_list: []manga.Manga = &[_]manga.Manga{},
    selected: i32 = -1,
    scroll: i32 = 0,
    chapters: []manga.Chapter = &[_]manga.Chapter{},
    chapter_selected: i32 = -1,
    chapter_scroll: i32 = 0,
    pages: []manga.Page = &[_]manga.Page{},
    page_index: i32 = 0,
};

const App = struct {
    allocator: std.mem.Allocator,
    gui: ui.Ui,
    db: database.Database,
    active_tab: i32 = 0,
    library: LibraryState,
    search: SearchState,
    notification_buf: [256]u8 = undefined,
    status_msg: []const u8 = "",
    status_timer: u32 = 0,

    fn init(allocator: std.mem.Allocator) !App {
        const home = std.posix.getenv("HOME") orelse "/tmp";
        const db_dir = try std.fmt.allocPrint(allocator, "{s}/.config/otaku", .{home});
        defer allocator.free(db_dir);
        std.fs.makeDirAbsolute(db_dir) catch {};

        const db_path_s = try std.fmt.allocPrint(allocator, "{s}/.config/otaku/otaku.db\x00", .{home});
        defer allocator.free(db_path_s);
        const db_path: [:0]const u8 = db_path_s[0 .. db_path_s.len - 1 :0];

        const db = try database.Database.open(allocator, db_path);
        const gui = try ui.Ui.init(allocator, "Otaku - Manga Reader", 1280, 780);

        return App{
            .allocator = allocator,
            .gui = gui,
            .db = db,
            .library = .{},
            .search = SearchState.init(allocator),
        };
    }

    fn loadSystemFont(self: *App) void {
        const font_paths = [_][*:0]const u8{
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
            "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
            "/usr/share/fonts/opentype/noto/NotoSans-Regular.ttf",
            "/usr/share/fonts/truetype/ubuntu/Ubuntu-R.ttf",
        };
        for (font_paths) |path| {
            self.gui.loadFonts(path) catch continue;
            return;
        }
    }

    fn deinit(self: *App) void {
        self.freeLibraryData();
        self.search.deinit(self.allocator);
        self.db.close();
        self.gui.deinit();
    }

    fn freeLibraryData(self: *App) void {
        for (self.library.manga_list) |*m| {
            var mutable = m.*;
            mutable.free(self.allocator);
        }
        self.allocator.free(self.library.manga_list);
        self.library.manga_list = &[_]manga.Manga{};

        for (self.library.chapters) |*ch| {
            var mutable = ch.*;
            mutable.free(self.allocator);
        }
        self.allocator.free(self.library.chapters);
        self.library.chapters = &[_]manga.Chapter{};

        for (self.library.pages) |*pg| {
            var mutable = pg.*;
            mutable.free(self.allocator);
        }
        self.allocator.free(self.library.pages);
        self.library.pages = &[_]manga.Page{};
    }

    fn reloadLibrary(self: *App) void {
        self.freeLibraryData();
        self.library.manga_list = self.db.listManga() catch &[_]manga.Manga{};
        self.library.selected = -1;
    }

    fn setStatus(self: *App, comptime fmt: []const u8, args: anytype) void {
        self.status_msg = std.fmt.bufPrint(&self.notification_buf, fmt, args) catch "...";
        self.status_timer = 3000;
    }

    fn run(self: *App) !void {
        self.loadSystemFont();
        self.reloadLibrary();

        const TARGET_FPS: u32 = 60;
        const FRAME_MS: u32 = 1000 / TARGET_FPS;
        const c_sdl = @cImport(@cInclude("SDL2/SDL.h"));

        while (self.gui.pollEvents()) {
            const frame_start = c_sdl.SDL_GetTicks();
            self.gui.beginFrame();
            try self.renderFrame();
            self.gui.endFrame();

            const elapsed = c_sdl.SDL_GetTicks() - frame_start;
            if (elapsed < FRAME_MS) c_sdl.SDL_Delay(FRAME_MS - elapsed);

            if (self.status_timer > 0) {
                self.status_timer -= @min(self.status_timer, FRAME_MS);
            }
        }
    }

    fn renderFrame(self: *App) !void {
        const W = self.gui.width;
        const H = self.gui.height;
        const SIDEBAR_W: i32 = 180;
        const TOPBAR_H: i32 = 50;
        const STATUSBAR_H: i32 = 28;

        // Top bar
        self.gui.drawRect(ui.Rect{ .x = 0, .y = 0, .w = W, .h = TOPBAR_H }, ui.Color{ .r = 20, .g = 20, .b = 20 });
        _ = self.gui.drawText("OTAKU", 16, 12, self.gui.theme.primary, .title);
        _ = self.gui.drawText("Desktop Manga Reader", 100, 18, self.gui.theme.text_muted, .small);
        self.gui.separator(0, TOPBAR_H - 1, W);

        // Sidebar navigation
        self.gui.drawRect(ui.Rect{ .x = 0, .y = TOPBAR_H, .w = SIDEBAR_W, .h = H - TOPBAR_H - STATUSBAR_H }, self.gui.theme.surface);

        const nav_items = [_][]const u8{ "Library", "Search", "Reading", "Settings" };
        for (nav_items, 0..) |item, i| {
            const nav_rect = ui.Rect{ .x = 0, .y = TOPBAR_H + @as(i32, @intCast(i)) * 48, .w = SIDEBAR_W - 1, .h = 47 };
            const is_active = self.active_tab == @as(i32, @intCast(i));
            if (is_active) {
                self.gui.drawRect(nav_rect, ui.Color{ .r = 40, .g = 20, .b = 20 });
                self.gui.drawLine(nav_rect.x, nav_rect.y, nav_rect.x, nav_rect.y + nav_rect.h, self.gui.theme.primary);
            }
            const color = if (is_active) self.gui.theme.accent else self.gui.theme.text;
            if (self.gui.flatButton(nav_rect, item, color)) {
                self.active_tab = @intCast(i);
            }
        }

        // Stats in sidebar bottom
        const stats_y = H - STATUSBAR_H - 60;
        self.gui.separator(0, stats_y, SIDEBAR_W);
        var count_buf: [64]u8 = undefined;
        const count_text = std.fmt.bufPrint(&count_buf, "{} titles", .{self.library.manga_list.len}) catch "...";
        _ = self.gui.drawText(count_text, 12, stats_y + 8, self.gui.theme.text_muted, .small);

        // Main content area
        const content_x = SIDEBAR_W;
        const content_y = TOPBAR_H;
        const content_w = W - SIDEBAR_W;
        const content_h = H - TOPBAR_H - STATUSBAR_H;

        switch (@as(AppTab, @enumFromInt(self.active_tab))) {
            .library => try self.renderLibrary(content_x, content_y, content_w, content_h),
            .search => try self.renderSearch(content_x, content_y, content_w, content_h),
            .reading => self.renderReading(content_x, content_y, content_w, content_h),
            .settings => self.renderSettings(content_x, content_y, content_w, content_h),
        }

        // Status bar
        self.gui.drawRect(ui.Rect{ .x = 0, .y = H - STATUSBAR_H, .w = W, .h = STATUSBAR_H }, ui.Color{ .r = 15, .g = 15, .b = 15 });
        self.gui.separator(0, H - STATUSBAR_H, W);
        if (self.status_timer > 0) {
            _ = self.gui.drawText(self.status_msg, 12, H - STATUSBAR_H + 6, self.gui.theme.accent, .small);
        } else {
            const tab_name = nav_items[@intCast(self.active_tab)];
            _ = self.gui.drawText(tab_name, 12, H - STATUSBAR_H + 6, self.gui.theme.text_muted, .small);
        }
    }

    fn renderLibrary(self: *App, cx: i32, cy: i32, cw: i32, ch: i32) !void {
        const PANEL_W = @divTrunc(cw, 3);

        _ = self.gui.drawText("Library", cx + 12, cy + 12, self.gui.theme.text, .large);

        if (self.gui.button(ui.Rect{ .x = cx + cw - 120, .y = cy + 10, .w = 110, .h = 30 }, "Refresh")) {
            self.reloadLibrary();
            self.setStatus("Library refreshed ({} titles)", .{self.library.manga_list.len});
        }

        self.gui.separator(cx, cy + 48, cw);

        var title_list: std.ArrayList([]const u8) = .empty;
        defer title_list.deinit(self.allocator);
        for (self.library.manga_list) |m| {
            try title_list.append(self.allocator, m.title);
        }

        const list_rect = ui.Rect{ .x = cx + 4, .y = cy + 52, .w = PANEL_W - 8, .h = ch - 56 };
        const clicked = self.gui.scrollableList(list_rect, title_list.items, self.library.selected, &self.library.scroll, 36);
        if (clicked >= 0 and clicked != self.library.selected) {
            self.library.selected = clicked;
            for (self.library.chapters) |*c2| {
                var mutable = c2.*;
                mutable.free(self.allocator);
            }
            self.allocator.free(self.library.chapters);
            const manga_id = self.library.manga_list[@intCast(clicked)].id;
            self.library.chapters = self.db.listChaptersByManga(manga_id) catch &[_]manga.Chapter{};
            self.library.chapter_selected = -1;
        }

        if (self.library.selected >= 0) {
            const selected_manga = &self.library.manga_list[@intCast(self.library.selected)];
            const mid_x = cx + PANEL_W;

            self.gui.drawTextClipped(selected_manga.title, ui.Rect{ .x = mid_x + 8, .y = cy + 54, .w = PANEL_W - 16, .h = 32 }, self.gui.theme.text, .large);

            const status_colors = [_]ui.Color{
                ui.Color{ .r = 100, .g = 100, .b = 100 },
                ui.Color{ .r = 80, .g = 160, .b = 80 },
                ui.Color{ .r = 80, .g = 100, .b = 200 },
                ui.Color{ .r = 200, .g = 160, .b = 50 },
                ui.Color{ .r = 180, .g = 60, .b = 60 },
            };
            const status_idx = @intFromEnum(selected_manga.status);
            self.gui.badge(mid_x + 8, cy + 90, selected_manga.status.toString(), status_colors[status_idx]);

            self.gui.separator(mid_x, cy + 112, PANEL_W);

            var ch_titles: std.ArrayList([]const u8) = .empty;
            defer ch_titles.deinit(self.allocator);
            for (self.library.chapters) |chapter_item| {
                try ch_titles.append(self.allocator, chapter_item.title);
            }
            const ch_list_rect = ui.Rect{ .x = mid_x + 4, .y = cy + 116, .w = PANEL_W - 8, .h = ch - 120 };
            const ch_clicked = self.gui.scrollableList(ch_list_rect, ch_titles.items, self.library.chapter_selected, &self.library.chapter_scroll, 32);
            if (ch_clicked >= 0) {
                self.library.chapter_selected = ch_clicked;
                self.active_tab = @intFromEnum(AppTab.reading);
                self.setStatus("Opening chapter {d:.1}", .{self.library.chapters[@intCast(ch_clicked)].number});
            }
        }

        if (self.library.manga_list.len == 0) {
            _ = self.gui.drawText("Your library is empty. Use Search to add manga.", cx + @divTrunc(cw, 2) - 180, cy + @divTrunc(ch, 2), self.gui.theme.text_muted, .normal);
        }
    }

    fn renderSearch(self: *App, cx: i32, cy: i32, cw: i32, ch: i32) !void {
        _ = self.gui.drawText("Search Manga", cx + 12, cy + 12, self.gui.theme.text, .large);
        self.gui.separator(cx, cy + 48, cw);

        const search_rect = ui.Rect{ .x = cx + 8, .y = cy + 56, .w = cw - 140, .h = 34 };
        const submitted = self.gui.textInputWithPlaceholder(search_rect, 1, &self.search.query_buf, &self.search.query_cursor, "Search for manga title...");

        const search_btn = ui.Rect{ .x = cx + cw - 128, .y = cy + 56, .w = 120, .h = 34 };
        const do_search = self.gui.button(search_btn, "Search") or submitted;

        if (do_search and self.search.query_buf.items.len > 0 and !self.search.searching) {
            self.search.searching = true;
            for (self.search.results) |*m| {
                var mutable = m.*;
                mutable.free(self.allocator);
            }
            self.allocator.free(self.search.results);
            self.search.results = &[_]manga.Manga{};
            self.search.selected = -1;
            self.search.scroll = 0;

            var c2 = crawler.Crawler.init(self.allocator);
            defer c2.deinit();
            const query = self.search.query_buf.items;
            self.search.results = c2.searchMangaDex(query) catch |err| blk: {
                const msg = switch (err) {
                    crawler.CrawlerError.NetworkError => "Network error - check your internet connection",
                    crawler.CrawlerError.ParseError => "Failed to parse response",
                    else => "Search failed",
                };
                self.setStatus("{s}", .{msg});
                break :blk &[_]manga.Manga{};
            };
            self.search.searching = false;
            self.setStatus("Found {} results for '{s}'", .{ self.search.results.len, query });
        }

        if (self.search.searching) {
            _ = self.gui.drawText("Searching...", cx + 12, cy + 100, self.gui.theme.text_muted, .normal);
            return;
        }

        self.gui.separator(cx, cy + 98, cw);

        if (self.search.results.len == 0) {
            _ = self.gui.drawText("No results. Enter a title and press Search.", cx + 12, cy + 110, self.gui.theme.text_muted, .normal);
            return;
        }

        const PANEL_W = @divTrunc(cw, 2);
        var result_titles: std.ArrayList([]const u8) = .empty;
        defer result_titles.deinit(self.allocator);
        for (self.search.results) |m| {
            try result_titles.append(self.allocator, m.title);
        }

        const list_rect = ui.Rect{ .x = cx + 4, .y = cy + 102, .w = PANEL_W - 8, .h = ch - 106 };
        const clicked = self.gui.scrollableList(list_rect, result_titles.items, self.search.selected, &self.search.scroll, 40);
        if (clicked >= 0) self.search.selected = clicked;

        if (self.search.selected >= 0 and self.search.selected < @as(i32, @intCast(self.search.results.len))) {
            const sel_manga = &self.search.results[@intCast(self.search.selected)];
            const det_x = cx + PANEL_W + 8;

            self.gui.drawTextClipped(sel_manga.title, ui.Rect{ .x = det_x, .y = cy + 106, .w = PANEL_W - 16, .h = 28 }, self.gui.theme.text, .large);

            _ = self.gui.drawText("Status:", det_x, cy + 142, self.gui.theme.text_muted, .small);
            _ = self.gui.drawText(sel_manga.status.toString(), det_x + 60, cy + 142, self.gui.theme.accent, .small);

            _ = self.gui.drawText("Source:", det_x, cy + 162, self.gui.theme.text_muted, .small);
            _ = self.gui.drawText(sel_manga.site, det_x + 60, cy + 162, self.gui.theme.text, .small);

            _ = self.gui.drawText("Description:", det_x, cy + 190, self.gui.theme.text_muted, .small);
            const desc_rect = ui.Rect{ .x = det_x, .y = cy + 208, .w = PANEL_W - 16, .h = ch - 320 };
            self.renderWrappedText(sel_manga.description, desc_rect, self.gui.theme.text, .small);

            if (self.gui.button(ui.Rect{ .x = det_x, .y = cy + ch - 50, .w = 160, .h = 36 }, "Add to Library")) {
                const id = self.db.insertManga(sel_manga.*) catch 0;
                if (id > 0) {
                    self.setStatus("Added '{s}' to library", .{sel_manga.title});
                    self.reloadLibrary();
                } else {
                    self.setStatus("Manga already in library or error adding", .{});
                }
            }
        }
    }

    fn renderReading(self: *App, cx: i32, cy: i32, cw: i32, ch: i32) void {
        _ = self.gui.drawText("Reading", cx + 12, cy + 12, self.gui.theme.text, .large);
        self.gui.separator(cx, cy + 48, cw);

        if (self.library.chapter_selected < 0 or self.library.chapters.len == 0) {
            _ = self.gui.drawText("Select a chapter from the Library tab to start reading.", cx + 12, cy + 80, self.gui.theme.text_muted, .normal);
            return;
        }

        const chapter = &self.library.chapters[@intCast(self.library.chapter_selected)];
        var ch_title_buf: [128]u8 = undefined;
        const ch_title = std.fmt.bufPrint(&ch_title_buf, "Chapter {d:.1}: {s}", .{ chapter.number, chapter.title }) catch "Chapter";
        _ = self.gui.drawText(ch_title, cx + 12, cy + 56, self.gui.theme.text, .large);

        if (self.library.chapter_selected > 0) {
            if (self.gui.button(ui.Rect{ .x = cx + 8, .y = cy + ch - 50, .w = 130, .h = 36 }, "< Previous")) {
                self.library.chapter_selected -= 1;
                self.library.page_index = 0;
            }
        }
        if (self.library.chapter_selected < @as(i32, @intCast(self.library.chapters.len)) - 1) {
            if (self.gui.button(ui.Rect{ .x = cx + cw - 148, .y = cy + ch - 50, .w = 130, .h = 36 }, "Next >")) {
                self.library.chapter_selected += 1;
                self.library.page_index = 0;
            }
        }

        if (self.library.pages.len == 0) {
            _ = self.gui.drawText("No pages loaded. Pages are fetched when online.", cx + 12, cy + 100, self.gui.theme.text_muted, .small);
            self.gui.drawTextClipped(chapter.url, ui.Rect{ .x = cx + 12, .y = cy + 124, .w = cw - 20, .h = 20 }, self.gui.theme.accent, .small);
            return;
        }

        var page_info_buf: [64]u8 = undefined;
        const page_info = std.fmt.bufPrint(&page_info_buf, "Page {} / {}", .{ self.library.page_index + 1, self.library.pages.len }) catch "Page";
        _ = self.gui.drawText(page_info, cx + @divTrunc(cw, 2) - 40, cy + ch - 50, self.gui.theme.text_muted, .normal);

        const progress = @as(f32, @floatFromInt(self.library.page_index + 1)) / @as(f32, @floatFromInt(self.library.pages.len));
        self.gui.progressBar(ui.Rect{ .x = cx + 8, .y = cy + ch - 14, .w = cw - 16, .h = 8 }, progress, self.gui.theme.primary);
    }

    fn renderSettings(self: *App, cx: i32, cy: i32, cw: i32, ch: i32) void {
        _ = ch;
        _ = self.gui.drawText("Settings", cx + 12, cy + 12, self.gui.theme.text, .large);
        self.gui.separator(cx, cy + 48, cw);

        _ = self.gui.drawText("Supported Manga Sources", cx + 12, cy + 60, self.gui.theme.text, .normal);
        self.gui.separator(cx + 8, cy + 86, @divTrunc(cw, 2) - 16);

        for (manga.known_sites, 0..) |site, i| {
            const y = cy + 96 + @as(i32, @intCast(i)) * 64;
            self.gui.drawRect(ui.Rect{ .x = cx + 8, .y = y, .w = @divTrunc(cw, 2) - 16, .h = 56 }, self.gui.theme.surface);
            _ = self.gui.drawText(site.name, cx + 16, y + 8, self.gui.theme.text, .normal);
            self.gui.drawTextClipped(site.base_url, ui.Rect{ .x = cx + 16, .y = y + 30, .w = @divTrunc(cw, 2) - 32, .h = 20 }, self.gui.theme.text_muted, .small);
        }

        const rx = cx + @divTrunc(cw, 2) + 12;
        _ = self.gui.drawText("About Otaku", rx, cy + 60, self.gui.theme.text, .normal);
        self.gui.separator(rx, cy + 86, @divTrunc(cw, 2) - 20);
        _ = self.gui.drawText("Otaku Desktop Manga Reader", rx, cy + 96, self.gui.theme.text, .normal);
        _ = self.gui.drawText("Version 0.1.0", rx, cy + 120, self.gui.theme.text_muted, .small);
        _ = self.gui.drawText("Built with Zig 0.15 + SDL2 + SQLite", rx, cy + 140, self.gui.theme.text_muted, .small);
        _ = self.gui.drawText("github.com/christianhelle/otaku", rx, cy + 160, self.gui.theme.accent, .small);
    }

    fn renderWrappedText(self: *App, text: []const u8, rect: ui.Rect, color: ui.Color, size: ui.FontSize) void {
        if (text.len == 0) return;
        const line_h: i32 = 18;
        var y = rect.y;
        var start: usize = 0;

        while (start < text.len and y < rect.y + rect.h) {
            var end = start;
            var last_space = start;

            while (end < text.len) {
                if (text[end] == '\n') break;
                if (text[end] == ' ') last_space = end;
                const ts = self.gui.textSize(text[start .. end + 1], size);
                if (ts.w > rect.w) {
                    end = if (last_space > start) last_space else end;
                    break;
                }
                end += 1;
            }
            if (end == start and end < text.len) end += 1;

            const line = text[start..end];
            self.gui.drawTextClipped(line, ui.Rect{ .x = rect.x, .y = y, .w = rect.w, .h = line_h }, color, size);
            y += line_h;
            start = end;
            if (start < text.len and (text[start] == ' ' or text[start] == '\n')) start += 1;
        }
    }
};

// ---- Entry point ----

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    try app.run();
}

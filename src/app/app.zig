const std = @import("std");
const terminal_mod = @import("../tui/terminal.zig");
const Terminal = terminal_mod.Terminal;
const readKey = terminal_mod.readKey;
const layout_mod = @import("../tui/layout.zig");
const list_mod = @import("../tui/widgets/list.zig");
const detail_mod = @import("../tui/widgets/detail.zig");
const statusbar_mod = @import("../tui/widgets/statusbar.zig");
const progress_mod = @import("../tui/widgets/progress.zig");
const state_mod = @import("state.zig");
const AppState = state_mod.AppState;
const Screen = state_mod.Screen;
const router = @import("router.zig");
const actions_mod = @import("actions.zig");
const fanfox_client_mod = @import("../fanfox/client.zig");
const config_mod = @import("../storage/config.zig");

const HOME_LABELS = [_][]const u8{
    "Hot Manga Releases",
    "Being Read Right Now",
    "Recommended",
    "New Manga Release",
    "Last Updates",
    "Trending",
    "Browse by Genre",
    "Search",
    "Downloads",
    "Library",
    "Settings",
    "Help",
    "Exit",
};

pub const App = struct {
    allocator: std.mem.Allocator,
    terminal: Terminal,
    state: AppState,
    client: fanfox_client_mod.FanfoxClient,
    running: bool = true,

    pub fn init(allocator: std.mem.Allocator) !App {
        return .{
            .allocator = allocator,
            .terminal = try Terminal.init(),
            .state = AppState.init(allocator),
            .client = fanfox_client_mod.FanfoxClient.init(allocator, config_mod.Config.defaults),
        };
    }

    pub fn deinit(self: *App) void {
        self.state.deinit(self.allocator);
        self.client.deinit();
        self.terminal.deinit();
    }

    pub fn run(self: *App) !void {
        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode() catch {};
        try self.terminal.hideCursor();
        defer self.terminal.showCursor() catch {};

        while (self.running) {
            try self.render();
            const key = try readKey(self.terminal.stdin);
            const action = try router.handleKey(&self.state, key);
            try actions_mod.executeAction(self, action);
        }

        try self.terminal.clearScreen();
    }

    fn render(self: *App) !void {
        var buf: [65536]u8 = undefined;
        const fw = self.terminal.stdout.writer(&buf);
        var w = fw.interface;

        try w.writeAll("\x1b[2J\x1b[H");

        const size = self.terminal.getSize() catch .{ .width = 80, .height = 24 };

        switch (self.state.screen) {
            .home => try self.renderHome(&w, size.width, size.height),
            .category_list => try self.renderCategoryList(&w, size.width, size.height),
            .title_detail => try self.renderTitleDetail(&w, size.width, size.height),
            .chapter_list => try self.renderChapterList(&w, size.width, size.height),
            .download_queue => try self.renderDownloadQueue(&w, size.width, size.height),
            .search_results => try self.renderSearchResults(&w, size.width, size.height),
            .genre_browser => try self.renderGenreBrowser(&w, size.width, size.height),
            .library => try self.renderLibrary(&w, size.width, size.height),
            .help => try self.renderHelp(&w, size.width, size.height),
        }

        try w.flush();
    }

    fn renderHome(self: *App, w: anytype, width: u16, height: u16) !void {
        const layout = layout_mod.twoPane(width, height);

        var list = list_mod.ListWidget.init(&HOME_LABELS, layout.main);
        list.title = "otaku — manga browser";
        list.selected = self.state.home_selected;
        try list.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Home",
            .item_count = HOME_LABELS.len,
            .selected_item = @intCast(self.state.home_selected + 1),
            .hint = "↑↓/jk: move | Enter: select | ?: help | q: quit",
            .rect = layout.statusbar,
        };
        try sb.render(w);
    }

    fn renderCategoryList(self: *App, w: anytype, width: u16, height: u16) !void {
        const panes = layout_mod.threePane(width, height);

        // Left: nav categories
        const cat_labels = [_][]const u8{
            "Hot", "Reading Now", "Recommended",
            "New Releases", "Last Updates", "Trending",
        };
        var nav_list = list_mod.ListWidget.init(&cat_labels, panes.left);
        nav_list.title = "Categories";
        try nav_list.render(w);

        // Center: titles
        var title_items_buf: [256][]const u8 = undefined;
        var count: usize = 0;
        for (self.state.category_titles) |*t| {
            if (count >= title_items_buf.len) break;
            title_items_buf[count] = t.title;
            count += 1;
        }
        var center_list = list_mod.ListWidget.init(title_items_buf[0..count], panes.center);
        center_list.selected = self.state.category_selected;
        if (self.state.current_category) |cat| {
            center_list.title = cat.label();
        } else {
            center_list.title = "Titles";
        }
        try center_list.render(w);

        // Right: detail
        var detail = detail_mod.DetailWidget.init(panes.right);
        if (self.state.category_titles.len > 0 and
            self.state.category_selected < self.state.category_titles.len)
        {
            detail.setManga(&self.state.category_titles[self.state.category_selected]);
        }
        try detail.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Browse",
            .item_count = @intCast(count),
            .selected_item = @intCast(self.state.category_selected + 1),
            .hint = "↑↓/jk: move | Enter: chapters | q: back | r: refresh",
            .loading = self.state.loading,
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }

    fn renderTitleDetail(self: *App, w: anytype, width: u16, height: u16) !void {
        const panes = layout_mod.twoPane(width, height);

        var detail = detail_mod.DetailWidget.init(panes.main);
        if (self.state.current_title) |*t| detail.setManga(t);
        try detail.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Title",
            .item_count = 0,
            .selected_item = 0,
            .hint = "Enter: chapters | d: download | a: all | q: back",
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }

    fn renderChapterList(self: *App, w: anytype, width: u16, height: u16) !void {
        const panes = layout_mod.twoPane(width, height);

        var items_buf: [512][]const u8 = undefined;
        var count: usize = 0;
        for (self.state.current_chapters) |*ch| {
            if (count >= items_buf.len) break;
            items_buf[count] = ch.number;
            count += 1;
        }
        var list = list_mod.ListWidget.init(items_buf[0..count], panes.main);
        list.selected = self.state.chapter_selected;
        list.title = "Chapters";
        try list.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Chapters",
            .item_count = @intCast(count),
            .selected_item = @intCast(self.state.chapter_selected + 1),
            .hint = "↑↓/jk: move | Space: select | d: download | a: all | q: back",
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }

    fn renderDownloadQueue(self: *App, w: anytype, width: u16, height: u16) !void {
        const panes = layout_mod.twoPane(width, height);

        var label_buf: [512][]const u8 = undefined;
        var count: usize = 0;
        for (self.state.download_jobs.items) |*job| {
            if (count >= label_buf.len) break;
            label_buf[count] = job.manga_slug;
            count += 1;
        }
        var list = list_mod.ListWidget.init(label_buf[0..count], panes.main);
        list.title = "Download Queue";
        try list.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Downloads",
            .item_count = @intCast(count),
            .selected_item = 0,
            .hint = "q: back",
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }

    fn renderSearchResults(self: *App, w: anytype, width: u16, height: u16) !void {
        const panes = layout_mod.twoPane(width, height);

        var items_buf: [256][]const u8 = undefined;
        var count: usize = 0;
        for (self.state.search_results) |*t| {
            if (count >= items_buf.len) break;
            items_buf[count] = t.title;
            count += 1;
        }
        var list = list_mod.ListWidget.init(items_buf[0..count], panes.main);
        list.selected = self.state.category_selected;
        list.title = "Search Results";
        try list.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Search",
            .item_count = @intCast(count),
            .selected_item = if (count > 0) @intCast(self.state.category_selected + 1) else 0,
            .hint = "↑↓/jk: move | Enter: select | q: back",
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }

    fn renderGenreBrowser(self: *App, w: anytype, width: u16, height: u16) !void {
        _ = self;
        const panes = layout_mod.twoPane(width, height);
        const genres = [_][]const u8{
            "Action", "Adventure", "Comedy", "Drama", "Fantasy",
            "Horror", "Mystery", "Romance", "Sci-fi", "Slice of Life",
            "Sports", "Supernatural", "Thriller",
        };
        var list = list_mod.ListWidget.init(&genres, panes.main);
        list.title = "Browse by Genre";
        try list.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Genre",
            .item_count = genres.len,
            .selected_item = 0,
            .hint = "↑↓/jk: move | Enter: browse | q: back",
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }

    fn renderLibrary(self: *App, w: anytype, width: u16, height: u16) !void {
        _ = self;
        const panes = layout_mod.twoPane(width, height);
        const items = [_][]const u8{"No library entries"};
        var list = list_mod.ListWidget.init(&items, panes.main);
        list.title = "Local Library";
        try list.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Library",
            .item_count = 0,
            .selected_item = 0,
            .hint = "b: build library | q: back",
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }

    fn renderHelp(self: *App, w: anytype, width: u16, height: u16) !void {
        _ = self;
        const panes = layout_mod.twoPane(width, height);
        const lines = [_][]const u8{
            "Keyboard shortcuts:",
            "",
            "  j / ↓      Move down",
            "  k / ↑      Move up",
            "  Enter      Open / select",
            "  Tab        Switch pane",
            "  /          Search",
            "  g          Genre filter",
            "  s          Status filter",
            "  d          Download selected",
            "  a          Download all",
            "  Space      Toggle selection",
            "  A          Select all",
            "  r          Refresh",
            "  b          Build library",
            "  q          Back / quit",
            "  ?          This help screen",
        };
        var list = list_mod.ListWidget.init(&lines, panes.main);
        list.title = "Help";
        try list.render(w);

        const sb = statusbar_mod.StatusBar{
            .screen_name = "Help",
            .item_count = 0,
            .selected_item = 0,
            .hint = "q / Enter: back",
            .rect = panes.statusbar,
        };
        try sb.render(w);
    }
};

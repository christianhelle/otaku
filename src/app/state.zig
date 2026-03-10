const std = @import("std");
const manga = @import("../domain/manga.zig");
const MangaTitle = manga.MangaTitle;
const Chapter = manga.Chapter;
const CategoryKind = manga.CategoryKind;
const DownloadJob = manga.DownloadJob;

pub const Screen = enum {
    home,
    category_list,
    title_detail,
    chapter_list,
    download_queue,
    search_results,
    genre_browser,
    library,
    help,
};

const HISTORY_MAX = 16;

pub const AppState = struct {
    screen: Screen = .home,

    screen_history: [HISTORY_MAX]Screen = undefined,
    history_len: usize = 0,

    // Home screen
    home_selected: usize = 0,

    // Category browsing
    current_category: ?CategoryKind = null,
    category_titles: []MangaTitle = &.{},
    category_selected: usize = 0,
    category_loading: bool = false,

    // Title detail
    current_title: ?MangaTitle = null,

    // Chapter list
    current_chapters: []Chapter = &.{},
    chapter_selected: usize = 0,
    chapter_selections: std.ArrayListUnmanaged(bool) = .{},

    // Search
    search_query: [256]u8 = undefined,
    search_query_len: usize = 0,
    search_results: []MangaTitle = &.{},

    // Download queue
    download_jobs: std.ArrayListUnmanaged(DownloadJob) = .{},

    // Status
    status_message: [256]u8 = undefined,
    status_message_len: usize = 0,
    loading: bool = false,
    error_message: ?[]const u8 = null,

    pub fn init(_: std.mem.Allocator) AppState {
        return .{};
    }

    pub fn deinit(self: *AppState, allocator: std.mem.Allocator) void {
        self.chapter_selections.deinit(allocator);
        self.download_jobs.deinit(allocator);
    }

    pub fn setStatus(self: *AppState, msg: []const u8) void {
        const len = @min(msg.len, self.status_message.len);
        @memcpy(self.status_message[0..len], msg[0..len]);
        self.status_message_len = len;
    }

    pub fn getStatus(self: AppState) []const u8 {
        return self.status_message[0..self.status_message_len];
    }

    pub fn setError(self: *AppState, msg: []const u8) void {
        self.error_message = msg;
    }

    pub fn clearError(self: *AppState) void {
        self.error_message = null;
    }

    pub fn navigate(self: *AppState, screen: Screen) void {
        if (self.history_len < HISTORY_MAX) {
            self.screen_history[self.history_len] = self.screen;
            self.history_len += 1;
        }
        self.screen = screen;
    }

    pub fn back(self: *AppState) void {
        if (self.history_len > 0) {
            self.history_len -= 1;
            self.screen = self.screen_history[self.history_len];
        } else {
            self.screen = .home;
        }
    }
};

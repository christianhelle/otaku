const std = @import("std");
const state_mod = @import("state.zig");
const AppState = state_mod.AppState;
const Screen = state_mod.Screen;
const terminal = @import("../tui/terminal.zig");
const Key = terminal.Key;
const manga = @import("../domain/manga.zig");
const CategoryKind = manga.CategoryKind;

pub const Action = union(enum) {
    none,
    navigate_to: Screen,
    back,
    quit,
    load_category: CategoryKind,
    load_title: []const u8,
    load_chapters: []const u8,
    download_selected,
    download_all,
    start_search: []const u8,
    build_library,
    refresh,
};

pub fn handleKey(app_state: *AppState, key: Key) !Action {
    return switch (app_state.screen) {
        .home => handleKeyOnHome(app_state, key),
        .category_list => handleKeyOnCategoryList(app_state, key),
        .title_detail => handleKeyOnTitleDetail(app_state, key),
        .chapter_list => handleKeyOnChapterList(app_state, key),
        .download_queue => handleKeyOnDownloadQueue(app_state, key),
        .search_results => handleKeyOnSearchResults(app_state, key),
        .genre_browser => handleKeyOnGenreBrowser(app_state, key),
        .library => handleKeyOnLibrary(app_state, key),
        .help => handleKeyOnHelp(app_state, key),
    };
}

const HOME_ITEMS = 13;

fn handleKeyOnHome(s: *AppState, key: Key) Action {
    switch (key) {
        .char_k, .up => {
            if (s.home_selected > 0) s.home_selected -= 1;
            return .none;
        },
        .char_j, .down => {
            if (s.home_selected + 1 < HOME_ITEMS) s.home_selected += 1;
            return .none;
        },
        .enter => return homeSelect(s),
        .char_q, .escape => return .quit,
        .char_slash => return .{ .navigate_to = .search_results },
        .char_question => return .{ .navigate_to = .help },
        else => return .none,
    }
}

fn homeSelect(s: *AppState) Action {
    return switch (s.home_selected) {
        0 => .{ .load_category = .hot },
        1 => .{ .load_category = .reading_now },
        2 => .{ .load_category = .recommended },
        3 => .{ .load_category = .new_release },
        4 => .{ .load_category = .last_updates },
        5 => .{ .load_category = .trending },
        6 => .{ .navigate_to = .genre_browser },
        7 => .{ .navigate_to = .search_results },
        8 => .{ .navigate_to = .download_queue },
        9 => .{ .navigate_to = .library },
        10 => .none, // settings (stub)
        11 => .{ .navigate_to = .help },
        12 => .quit,
        else => .none,
    };
}

fn handleKeyOnCategoryList(s: *AppState, key: Key) Action {
    switch (key) {
        .char_k, .up => {
            if (s.category_selected > 0) s.category_selected -= 1;
            return .none;
        },
        .char_j, .down => {
            if (s.category_selected + 1 < s.category_titles.len)
                s.category_selected += 1;
            return .none;
        },
        .enter => {
            if (s.category_titles.len > 0 and s.category_selected < s.category_titles.len) {
                const title = &s.category_titles[s.category_selected];
                return .{ .load_chapters = title.slug };
            }
            return .none;
        },
        .char_q, .escape => return .back,
        .char_r => return .refresh,
        .char_slash => return .{ .navigate_to = .search_results },
        else => return .none,
    }
}

fn handleKeyOnTitleDetail(s: *AppState, key: Key) Action {
    _ = s;
    switch (key) {
        .char_q, .escape => return .back,
        .char_d => return .download_selected,
        .char_a => return .download_all,
        .enter => return .{ .navigate_to = .chapter_list },
        else => return .none,
    }
}

fn handleKeyOnChapterList(s: *AppState, key: Key) Action {
    switch (key) {
        .char_k, .up => {
            if (s.chapter_selected > 0) s.chapter_selected -= 1;
            return .none;
        },
        .char_j, .down => {
            if (s.chapter_selected + 1 < s.current_chapters.len)
                s.chapter_selected += 1;
            return .none;
        },
        .char_space => {
            // toggle selection
            return .none;
        },
        .char_A => return .none, // select all (stub)
        .char_d => return .download_selected,
        .char_a => return .download_all,
        .char_q, .escape => return .back,
        else => return .none,
    }
}

fn handleKeyOnDownloadQueue(s: *AppState, key: Key) Action {
    _ = s;
    switch (key) {
        .char_q, .escape => return .back,
        else => return .none,
    }
}

fn handleKeyOnSearchResults(s: *AppState, key: Key) Action {
    switch (key) {
        .char_k, .up => {
            if (s.category_selected > 0) s.category_selected -= 1;
            return .none;
        },
        .char_j, .down => {
            if (s.category_selected + 1 < s.search_results.len)
                s.category_selected += 1;
            return .none;
        },
        .enter => {
            if (s.search_results.len > 0 and s.category_selected < s.search_results.len) {
                return .{ .load_chapters = s.search_results[s.category_selected].slug };
            }
            return .none;
        },
        .char_q, .escape => return .back,
        else => return .none,
    }
}

fn handleKeyOnGenreBrowser(s: *AppState, key: Key) Action {
    _ = s;
    switch (key) {
        .char_q, .escape => return .back,
        else => return .none,
    }
}

fn handleKeyOnLibrary(s: *AppState, key: Key) Action {
    _ = s;
    switch (key) {
        .char_q, .escape => return .back,
        .char_b => return .build_library,
        else => return .none,
    }
}

fn handleKeyOnHelp(s: *AppState, key: Key) Action {
    _ = s;
    switch (key) {
        .char_q, .escape, .enter => return .back,
        else => return .none,
    }
}

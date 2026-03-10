const std = @import("std");

pub const base_url = "https://fanfox.net";

pub const Endpoints = struct {
    pub const hot = base_url ++ "/";
    pub const trending = base_url ++ "/trending/";
    pub const new_release = base_url ++ "/directory/?news";
    pub const last_updates = base_url ++ "/releases/";
    pub const directory = base_url ++ "/directory/";
    pub const search = base_url ++ "/search";
};

/// Build a search URL for the given query.
pub fn buildSearchUrl(query: []const u8, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}/search?title={s}", .{ base_url, query });
}

/// Build a manga detail URL from a slug.
pub fn buildMangaUrl(slug: []const u8, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "{s}/manga/{s}/", .{ base_url, slug });
}

/// Build a directory URL for browsing with optional genre, status, and page filters.
pub fn buildDirectoryUrl(genre: ?[]const u8, status: ?[]const u8, page: u32, buf: []u8) ![]const u8 {
    if (genre) |g| {
        if (status) |s| {
            return std.fmt.bufPrint(buf, "{s}/directory/{s}/{s}/{d}.html", .{ base_url, g, s, page });
        }
        return std.fmt.bufPrint(buf, "{s}/directory/{s}/{d}.html", .{ base_url, g, page });
    }
    if (page <= 1) {
        return std.fmt.bufPrint(buf, "{s}/directory/", .{base_url});
    }
    return std.fmt.bufPrint(buf, "{s}/directory/{d}.html", .{ base_url, page });
}

// ── Tests ──────────────────────────────────────────────────────────────

test "buildSearchUrl" {
    var buf: [256]u8 = undefined;
    const url = try buildSearchUrl("naruto", &buf);
    try std.testing.expectEqualStrings("https://fanfox.net/search?title=naruto", url);
}

test "buildMangaUrl" {
    var buf: [256]u8 = undefined;
    const url = try buildMangaUrl("naruto", &buf);
    try std.testing.expectEqualStrings("https://fanfox.net/manga/naruto/", url);
}

test "buildDirectoryUrl default" {
    var buf: [256]u8 = undefined;
    const url = try buildDirectoryUrl(null, null, 1, &buf);
    try std.testing.expectEqualStrings("https://fanfox.net/directory/", url);
}

test "Endpoints constants" {
    try std.testing.expectEqualStrings("https://fanfox.net/", Endpoints.hot);
    try std.testing.expectEqualStrings("https://fanfox.net/trending/", Endpoints.trending);
}

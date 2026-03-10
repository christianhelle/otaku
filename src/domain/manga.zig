const std = @import("std");

pub const version = "0.1.0";

// ── Status enums ──────────────────────────────────────────────────────

pub const MangaStatus = enum {
    unknown,
    ongoing,
    completed,
    hiatus,
    cancelled,

    pub fn label(self: MangaStatus) []const u8 {
        return switch (self) {
            .unknown => "Unknown",
            .ongoing => "Ongoing",
            .completed => "Completed",
            .hiatus => "Hiatus",
            .cancelled => "Cancelled",
        };
    }
};

pub const CategoryKind = enum {
    hot,
    reading_now,
    recommended,
    new_release,
    last_updates,
    trending,
    genre,
    search,

    pub fn slug(self: CategoryKind) []const u8 {
        return switch (self) {
            .hot => "hot",
            .reading_now => "reading-now",
            .recommended => "recommended",
            .new_release => "new",
            .last_updates => "updates",
            .trending => "trending",
            .genre => "genre",
            .search => "search",
        };
    }

    pub fn label(self: CategoryKind) []const u8 {
        return switch (self) {
            .hot => "Hot",
            .reading_now => "Reading Now",
            .recommended => "Recommended",
            .new_release => "New Releases",
            .last_updates => "Last Updates",
            .trending => "Trending",
            .genre => "Genre",
            .search => "Search Results",
        };
    }
};

pub const LocalChapterStatus = enum {
    not_downloaded,
    partial,
    complete,
};

pub const DownloadStatus = enum {
    pending,
    in_progress,
    completed,
    failed,
    cancelled,
};

// ── Core domain types ─────────────────────────────────────────────────

pub const MangaTitle = struct {
    slug: []const u8,
    title: []const u8,
    url: []const u8,
    cover_url: ?[]const u8 = null,
    author: ?[]const u8 = null,
    status: MangaStatus = .unknown,
    genres: []const []const u8 = &.{},
    summary: ?[]const u8 = null,
    last_updated: ?[]const u8 = null,
    chapter_count: ?u32 = null,

    pub fn deinit(self: *MangaTitle, allocator: std.mem.Allocator) void {
        allocator.free(self.slug);
        allocator.free(self.title);
        allocator.free(self.url);
        if (self.cover_url) |v| allocator.free(v);
        if (self.author) |v| allocator.free(v);
        for (self.genres) |g| allocator.free(g);
        if (self.genres.len > 0) allocator.free(self.genres);
        if (self.summary) |v| allocator.free(v);
        if (self.last_updated) |v| allocator.free(v);
    }
};

pub const Chapter = struct {
    number: []const u8,
    title: ?[]const u8 = null,
    url: []const u8,
    date: ?[]const u8 = null,

    pub fn deinit(self: *Chapter, allocator: std.mem.Allocator) void {
        allocator.free(self.number);
        if (self.title) |v| allocator.free(v);
        allocator.free(self.url);
        if (self.date) |v| allocator.free(v);
    }
};

pub const CategoryFeed = struct {
    kind: CategoryKind,
    genre: ?[]const u8 = null,
    query: ?[]const u8 = null,
    page: u32 = 1,
    titles: []MangaTitle = &.{},

    pub fn deinit(self: *CategoryFeed, allocator: std.mem.Allocator) void {
        for (self.titles) |*t| {
            @constCast(t).deinit(allocator);
        }
        if (self.titles.len > 0) allocator.free(self.titles);
        if (self.genre) |v| allocator.free(v);
        if (self.query) |v| allocator.free(v);
    }
};

pub const DownloadJob = struct {
    manga_slug: []const u8,
    chapter_number: []const u8,
    url: []const u8,
    output_dir: []const u8,
    status: DownloadStatus = .pending,
    pages_total: ?u32 = null,
    pages_done: u32 = 0,
    error_message: ?[]const u8 = null,
};

pub const LocalChapter = struct {
    number: []const u8,
    path: []const u8,
    page_count: u32 = 0,
    status: LocalChapterStatus = .not_downloaded,
};

pub const LocalLibraryEntry = struct {
    slug: []const u8,
    title: []const u8,
    path: []const u8,
    chapters: []LocalChapter = &.{},
    cover_path: ?[]const u8 = null,
};

// ── Tests ─────────────────────────────────────────────────────────────

test "MangaStatus labels" {
    try std.testing.expectEqualStrings("Ongoing", MangaStatus.ongoing.label());
    try std.testing.expectEqualStrings("Unknown", MangaStatus.unknown.label());
}

test "CategoryKind slugs" {
    try std.testing.expectEqualStrings("hot", CategoryKind.hot.slug());
    try std.testing.expectEqualStrings("reading-now", CategoryKind.reading_now.slug());
    try std.testing.expectEqualStrings("updates", CategoryKind.last_updates.slug());
}

test "DownloadStatus default" {
    const job = DownloadJob{
        .manga_slug = "test",
        .chapter_number = "1",
        .url = "http://example.com",
        .output_dir = "./out",
    };
    try std.testing.expectEqual(DownloadStatus.pending, job.status);
}

test "MangaTitle deinit with null optionals" {
    const allocator = std.testing.allocator;
    var title = MangaTitle{
        .slug = try allocator.dupe(u8, "naruto"),
        .title = try allocator.dupe(u8, "Naruto"),
        .url = try allocator.dupe(u8, "https://fanfox.net/manga/naruto/"),
        // cover_url, author, summary intentionally null
        // genres intentionally empty
    };
    title.deinit(allocator);
    // If we reach here without crashing, null optionals are handled correctly
}

test "MangaTitle deinit with all fields" {
    const allocator = std.testing.allocator;
    const genres = try allocator.alloc([]const u8, 2);
    genres[0] = try allocator.dupe(u8, "Action");
    genres[1] = try allocator.dupe(u8, "Adventure");
    var title = MangaTitle{
        .slug = try allocator.dupe(u8, "naruto"),
        .title = try allocator.dupe(u8, "Naruto"),
        .url = try allocator.dupe(u8, "https://fanfox.net/manga/naruto/"),
        .cover_url = try allocator.dupe(u8, "https://img.fanfox.net/covers/naruto/cover.jpg"),
        .author = try allocator.dupe(u8, "Masashi Kishimoto"),
        .summary = try allocator.dupe(u8, "Naruto is a young shinobi..."),
        .genres = genres,
    };
    title.deinit(allocator);
}

test "CategoryFeed deinit empty" {
    const allocator = std.testing.allocator;
    var feed = CategoryFeed{ .kind = .hot };
    feed.deinit(allocator);
}

test "MangaStatus all labels" {
    try std.testing.expectEqualStrings("Completed", MangaStatus.completed.label());
    try std.testing.expectEqualStrings("Hiatus", MangaStatus.hiatus.label());
    try std.testing.expectEqualStrings("Cancelled", MangaStatus.cancelled.label());
}

test "CategoryKind all slugs and labels" {
    try std.testing.expectEqualStrings("recommended", CategoryKind.recommended.slug());
    try std.testing.expectEqualStrings("new", CategoryKind.new_release.slug());
    try std.testing.expectEqualStrings("trending", CategoryKind.trending.slug());
    try std.testing.expectEqualStrings("genre", CategoryKind.genre.slug());
    try std.testing.expectEqualStrings("search", CategoryKind.search.slug());
    try std.testing.expectEqualStrings("Search Results", CategoryKind.search.label());
    try std.testing.expectEqualStrings("New Releases", CategoryKind.new_release.label());
}

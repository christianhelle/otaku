/// Core data types for the Otaku manga reader.
const std = @import("std");

/// Status of a manga series.
pub const MangaStatus = enum(u8) {
    unknown = 0,
    ongoing = 1,
    completed = 2,
    hiatus = 3,
    cancelled = 4,

    pub fn fromString(s: []const u8) MangaStatus {
        if (std.mem.eql(u8, s, "ongoing")) return .ongoing;
        if (std.mem.eql(u8, s, "completed")) return .completed;
        if (std.mem.eql(u8, s, "hiatus")) return .hiatus;
        if (std.mem.eql(u8, s, "cancelled")) return .cancelled;
        return .unknown;
    }

    pub fn toString(self: MangaStatus) []const u8 {
        return switch (self) {
            .ongoing => "ongoing",
            .completed => "completed",
            .hiatus => "hiatus",
            .cancelled => "cancelled",
            .unknown => "unknown",
        };
    }
};

/// A manga title with metadata.
pub const Manga = struct {
    id: i64 = 0,
    title: []const u8,
    url: []const u8,
    cover_url: []const u8 = "",
    description: []const u8 = "",
    status: MangaStatus = .unknown,
    site: []const u8,
    chapter_count: i64 = 0,
    created_at: i64 = 0,
    updated_at: i64 = 0,

    /// Duplicate the Manga, allocating owned copies of all string fields.
    pub fn dupe(self: Manga, allocator: std.mem.Allocator) !Manga {
        return Manga{
            .id = self.id,
            .title = try allocator.dupe(u8, self.title),
            .url = try allocator.dupe(u8, self.url),
            .cover_url = try allocator.dupe(u8, self.cover_url),
            .description = try allocator.dupe(u8, self.description),
            .status = self.status,
            .site = try allocator.dupe(u8, self.site),
            .chapter_count = self.chapter_count,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
        };
    }

    /// Free all string fields allocated by dupe().
    pub fn free(self: *Manga, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.url);
        allocator.free(self.cover_url);
        allocator.free(self.description);
        allocator.free(self.site);
    }
};

/// A single chapter of a manga.
pub const Chapter = struct {
    id: i64 = 0,
    manga_id: i64,
    number: f64,
    title: []const u8 = "",
    url: []const u8,
    read: bool = false,
    downloaded: bool = false,
    page_count: i64 = 0,
    created_at: i64 = 0,

    pub fn dupe(self: Chapter, allocator: std.mem.Allocator) !Chapter {
        return Chapter{
            .id = self.id,
            .manga_id = self.manga_id,
            .number = self.number,
            .title = try allocator.dupe(u8, self.title),
            .url = try allocator.dupe(u8, self.url),
            .read = self.read,
            .downloaded = self.downloaded,
            .page_count = self.page_count,
            .created_at = self.created_at,
        };
    }

    pub fn free(self: *Chapter, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.url);
    }
};

/// A single page within a chapter.
pub const Page = struct {
    id: i64 = 0,
    chapter_id: i64,
    page_number: i32,
    url: []const u8,
    local_path: []const u8 = "",

    pub fn dupe(self: Page, allocator: std.mem.Allocator) !Page {
        return Page{
            .id = self.id,
            .chapter_id = self.chapter_id,
            .page_number = self.page_number,
            .url = try allocator.dupe(u8, self.url),
            .local_path = try allocator.dupe(u8, self.local_path),
        };
    }

    pub fn free(self: *Page, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.local_path);
    }
};

/// A supported manga source site configuration.
pub const MangaSite = struct {
    name: []const u8,
    base_url: []const u8,
    search_url_template: []const u8,
    chapter_list_selector: []const u8 = "",
    page_image_selector: []const u8 = "",
};

/// Well-known manga sites that Otaku can crawl.
pub const known_sites = [_]MangaSite{
    .{
        .name = "MangaDex",
        .base_url = "https://api.mangadex.org",
        .search_url_template = "https://api.mangadex.org/manga?title={s}&limit=20",
        .chapter_list_selector = "data[].id",
        .page_image_selector = "chapter.data[]",
    },
    .{
        .name = "MangaKakalot",
        .base_url = "https://mangakakalot.com",
        .search_url_template = "https://mangakakalot.com/search/story/{s}",
        .chapter_list_selector = "div.chapter-list a",
        .page_image_selector = "div.container-chapter-reader img",
    },
    .{
        .name = "MangaSee",
        .base_url = "https://mangasee123.com",
        .search_url_template = "https://mangasee123.com/search/?q={s}",
        .chapter_list_selector = "a.ChapterLink",
        .page_image_selector = "img.img-fluid",
    },
};

/// Result of a manga search or crawl operation.
pub const CrawlResult = struct {
    manga_list: []Manga,
    error_message: ?[]const u8 = null,

    pub fn deinit(self: *CrawlResult, allocator: std.mem.Allocator) void {
        for (self.manga_list) |*m| {
            var manga = m.*;
            manga.free(allocator);
        }
        allocator.free(self.manga_list);
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

// ---------- Unit Tests ----------

test "MangaStatus fromString" {
    try std.testing.expectEqual(MangaStatus.ongoing, MangaStatus.fromString("ongoing"));
    try std.testing.expectEqual(MangaStatus.completed, MangaStatus.fromString("completed"));
    try std.testing.expectEqual(MangaStatus.hiatus, MangaStatus.fromString("hiatus"));
    try std.testing.expectEqual(MangaStatus.cancelled, MangaStatus.fromString("cancelled"));
    try std.testing.expectEqual(MangaStatus.unknown, MangaStatus.fromString("foobar"));
}

test "MangaStatus toString" {
    try std.testing.expectEqualStrings("ongoing", MangaStatus.ongoing.toString());
    try std.testing.expectEqualStrings("completed", MangaStatus.completed.toString());
    try std.testing.expectEqualStrings("hiatus", MangaStatus.hiatus.toString());
    try std.testing.expectEqualStrings("cancelled", MangaStatus.cancelled.toString());
    try std.testing.expectEqualStrings("unknown", MangaStatus.unknown.toString());
}

test "MangaStatus round-trip" {
    const statuses = [_]MangaStatus{ .ongoing, .completed, .hiatus, .cancelled, .unknown };
    for (statuses) |s| {
        try std.testing.expectEqual(s, MangaStatus.fromString(s.toString()));
    }
}

test "Manga dupe and free" {
    const allocator = std.testing.allocator;
    const original = Manga{
        .title = "Naruto",
        .url = "https://example.com/naruto",
        .cover_url = "https://example.com/naruto.jpg",
        .description = "A ninja story",
        .status = .completed,
        .site = "MangaDex",
    };
    var duped = try original.dupe(allocator);
    defer duped.free(allocator);
    try std.testing.expectEqualStrings(original.title, duped.title);
    try std.testing.expectEqualStrings(original.url, duped.url);
    try std.testing.expectEqualStrings(original.cover_url, duped.cover_url);
    try std.testing.expectEqualStrings(original.description, duped.description);
    try std.testing.expectEqual(original.status, duped.status);
    try std.testing.expectEqualStrings(original.site, duped.site);
    // Ensure dupe is independent (different pointer)
    try std.testing.expect(original.title.ptr != duped.title.ptr);
}

test "Chapter dupe and free" {
    const allocator = std.testing.allocator;
    const original = Chapter{
        .manga_id = 1,
        .number = 1.5,
        .title = "The Beginning",
        .url = "https://example.com/ch1",
        .read = true,
    };
    var duped = try original.dupe(allocator);
    defer duped.free(allocator);
    try std.testing.expectEqual(original.manga_id, duped.manga_id);
    try std.testing.expectEqual(original.number, duped.number);
    try std.testing.expectEqualStrings(original.title, duped.title);
    try std.testing.expectEqualStrings(original.url, duped.url);
    try std.testing.expectEqual(original.read, duped.read);
}

test "Page dupe and free" {
    const allocator = std.testing.allocator;
    const original = Page{
        .chapter_id = 5,
        .page_number = 1,
        .url = "https://cdn.example.com/page1.jpg",
        .local_path = "/home/user/.otaku/ch5/page1.jpg",
    };
    var duped = try original.dupe(allocator);
    defer duped.free(allocator);
    try std.testing.expectEqual(original.chapter_id, duped.chapter_id);
    try std.testing.expectEqual(original.page_number, duped.page_number);
    try std.testing.expectEqualStrings(original.url, duped.url);
    try std.testing.expectEqualStrings(original.local_path, duped.local_path);
}

test "known_sites not empty" {
    try std.testing.expect(known_sites.len > 0);
    for (known_sites) |site| {
        try std.testing.expect(site.name.len > 0);
        try std.testing.expect(site.base_url.len > 0);
        try std.testing.expect(site.search_url_template.len > 0);
    }
}

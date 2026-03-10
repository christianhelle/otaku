const std = @import("std");
const manga = @import("../../domain/manga.zig");
const categories = @import("categories.zig");

/// Parse a directory/browse page. Same structure as category pages.
pub fn parseDirectoryPage(
    allocator: std.mem.Allocator,
    html: []const u8,
    base_url: []const u8,
) ![]manga.MangaTitle {
    return categories.parseMangaList(allocator, html, base_url);
}

// ── Tests ──────────────────────────────────────────────────────────────

test "parseDirectoryPage extracts titles" {
    const html =
        \\<ul>
        \\  <li><a href="/manga/bleach/">Bleach</a></li>
        \\  <li><a href="/manga/dragon-ball/">Dragon Ball</a></li>
        \\</ul>
    ;
    const titles = try parseDirectoryPage(std.testing.allocator, html, "https://fanfox.net");
    defer {
        for (titles) |*t| @constCast(t).deinit(std.testing.allocator);
        std.testing.allocator.free(titles);
    }
    try std.testing.expect(titles.len == 2);
}

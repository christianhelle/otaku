const std = @import("std");
const manga = @import("../../domain/manga.zig");

/// Parse the chapter list HTML for a given manga slug.
/// Looks for anchor hrefs matching /manga/{slug}/[v.../]c{number}/
/// Returns an owned slice of Chapter; caller frees with deinit on each item.
pub fn parseChapterList(
    allocator: std.mem.Allocator,
    html: []const u8,
    slug: []const u8,
    base_url: []const u8,
) ![]manga.Chapter {
    var chapters: std.ArrayListUnmanaged(manga.Chapter) = .empty;
    errdefer {
        for (chapters.items) |*ch| ch.deinit(allocator);
        chapters.deinit(allocator);
    }

    var prefix_buf: [512]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "/manga/{s}/", .{slug}) catch return error.SlugTooLong;

    var pos: usize = 0;
    while (pos < html.len) {
        const href_start = blk: {
            const dq = std.mem.indexOfPos(u8, html, pos, "href=\"") orelse html.len;
            const sq = std.mem.indexOfPos(u8, html, pos, "href='") orelse html.len;
            if (dq == html.len and sq == html.len) break :blk html.len;
            break :blk @min(dq, sq);
        };
        if (href_start >= html.len) break;

        const quote_char = html[href_start + 5];
        const val_start = href_start + 6;
        pos = val_start;

        const val_end = std.mem.indexOfScalarPos(u8, html, val_start, quote_char) orelse {
            pos = val_start + 1;
            continue;
        };
        const href = html[val_start..val_end];
        pos = val_end + 1;

        if (std.mem.indexOf(u8, href, prefix) == null) continue;

        // Find /c{digit} pattern
        const c_needle = "/c";
        const c_pos = std.mem.indexOf(u8, href, c_needle) orelse continue;
        const after_c = c_pos + c_needle.len;
        if (after_c >= href.len or href[after_c] < '0' or href[after_c] > '9') continue;

        const rest = href[after_c..];
        const sep_end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;

        var num_end = sep_end;
        if (sep_end >= 5 and std.mem.endsWith(u8, rest[0..sep_end], ".html")) {
            num_end = sep_end - 5;
        }
        if (num_end == 0) continue;

        const number_str = rest[0..num_end];
        if (!looksLikeNumber(number_str)) continue;

        // Build absolute URL
        const abs_url = if (std.mem.startsWith(u8, href, "http://") or
            std.mem.startsWith(u8, href, "https://"))
            try allocator.dupe(u8, href)
        else blk: {
            const origin = getOrigin(base_url);
            if (std.mem.endsWith(u8, href, ".html")) {
                break :blk try std.fmt.allocPrint(allocator, "{s}{s}", .{ origin, href });
            } else {
                break :blk try std.fmt.allocPrint(allocator, "{s}{s}1.html", .{ origin, href });
            }
        };
        errdefer allocator.free(abs_url);

        const number_copy = try allocator.dupe(u8, number_str);
        errdefer allocator.free(number_copy);

        // Deduplicate by chapter number (keep first occurrence)
        var dup = false;
        for (chapters.items) |existing| {
            if (std.mem.eql(u8, existing.number, number_copy)) {
                dup = true;
                break;
            }
        }
        if (dup) {
            allocator.free(abs_url);
            allocator.free(number_copy);
            continue;
        }

        try chapters.append(allocator, manga.Chapter{
            .number = number_copy,
            .url = abs_url,
        });
    }

    return chapters.toOwnedSlice(allocator);
}

fn looksLikeNumber(s: []const u8) bool {
    if (s.len == 0) return false;
    var dots: usize = 0;
    for (s) |c| {
        if (c == '.') {
            dots += 1;
            if (dots > 1) return false;
        } else if (c < '0' or c > '9') {
            return false;
        }
    }
    return true;
}

fn getOrigin(url_str: []const u8) []const u8 {
    if (std.mem.indexOf(u8, url_str, "://")) |after_scheme| {
        const start = after_scheme + 3;
        const rest = url_str[start..];
        const slash = std.mem.indexOf(u8, rest, "/") orelse rest.len;
        return url_str[0 .. start + slash];
    }
    return url_str;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "parseChapterList basic" {
    const html =
        \\<a href="/manga/naruto/v1/c1/">Chapter 1</a>
        \\<a href="/manga/naruto/c2/">Chapter 2</a>
        \\<a href="/manga/naruto/c10/">Chapter 10</a>
    ;
    const chapters = try parseChapterList(std.testing.allocator, html, "naruto", "https://fanfox.net");
    defer {
        for (chapters) |*ch| @constCast(ch).deinit(std.testing.allocator);
        std.testing.allocator.free(chapters);
    }
    try std.testing.expect(chapters.len == 3);
}

test "parseChapterList deduplication" {
    const html =
        \\<a href="/manga/naruto/c1/">Chapter 1</a>
        \\<a href="/manga/naruto/v1/c1/">Chapter 1 alt</a>
    ;
    const chapters = try parseChapterList(std.testing.allocator, html, "naruto", "https://fanfox.net");
    defer {
        for (chapters) |*ch| @constCast(ch).deinit(std.testing.allocator);
        std.testing.allocator.free(chapters);
    }
    try std.testing.expect(chapters.len == 1);
}

test "looksLikeNumber" {
    try std.testing.expect(looksLikeNumber("1"));
    try std.testing.expect(looksLikeNumber("10"));
    try std.testing.expect(looksLikeNumber("5.5"));
    try std.testing.expect(!looksLikeNumber(""));
    try std.testing.expect(!looksLikeNumber("abc"));
    try std.testing.expect(!looksLikeNumber("1.2.3"));
}

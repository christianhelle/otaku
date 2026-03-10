const std = @import("std");
const manga = @import("../../domain/manga.zig");
const html_util = @import("../../util/html.zig");
const urls_util = @import("../../util/urls.zig");
const strings_util = @import("../../util/strings.zig");

/// Parse a manga's detail page HTML into a MangaTitle.
/// Never returns error on partial parse — missing fields fall back to defaults.
pub fn parseTitleDetail(
    allocator: std.mem.Allocator,
    html: []const u8,
    url: []const u8,
) !manga.MangaTitle {
    const slug = urls_util.extractSlug(url) orelse "";
    const slug_copy = try allocator.dupe(u8, slug);
    errdefer allocator.free(slug_copy);

    const url_copy = try allocator.dupe(u8, url);
    errdefer allocator.free(url_copy);

    // Title: look for <h1> or <title>
    const title_str = extractTitle(html) orelse slug;
    const title_copy = try allocator.dupe(u8, strings_util.trimWhitespace(title_str));
    errdefer allocator.free(title_copy);

    // Cover URL
    const cover = extractCoverUrl(html);
    const cover_copy: ?[]const u8 = if (cover) |c|
        try allocator.dupe(u8, c)
    else
        null;
    errdefer if (cover_copy) |c| allocator.free(c);

    // Author
    const author = extractLabelValue(html, "Author");
    const author_copy: ?[]const u8 = if (author) |a|
        try allocator.dupe(u8, strings_util.trimWhitespace(a))
    else
        null;
    errdefer if (author_copy) |a| allocator.free(a);

    // Status
    const status = parseStatus(html);

    // Genres
    var genres_list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer {
        for (genres_list.items) |g| allocator.free(g);
        genres_list.deinit(allocator);
    }
    try extractGenres(allocator, html, &genres_list);
    const genres_slice = try genres_list.toOwnedSlice(allocator);
    errdefer {
        for (genres_slice) |g| allocator.free(g);
        allocator.free(genres_slice);
    }

    // Summary
    const summary = extractSummary(html);
    const summary_copy: ?[]const u8 = if (summary) |s|
        try allocator.dupe(u8, strings_util.trimWhitespace(s))
    else
        null;

    return manga.MangaTitle{
        .slug = slug_copy,
        .title = title_copy,
        .url = url_copy,
        .cover_url = cover_copy,
        .author = author_copy,
        .status = status,
        .genres = genres_slice,
        .summary = summary_copy,
    };
}

fn extractTitle(html: []const u8) ?[]const u8 {
    // Try <h1 class="...">
    if (std.mem.indexOf(u8, html, "<h1")) |h1_start| {
        const gt = std.mem.indexOfPos(u8, html, h1_start, ">") orelse return null;
        const end = std.mem.indexOfPos(u8, html, gt, "</h1>") orelse return null;
        const text = html[gt + 1 .. end];
        if (text.len > 0 and text.len < 256) return text;
    }
    // Try <title>
    if (std.mem.indexOf(u8, html, "<title>")) |ts| {
        const start = ts + 7;
        const end = std.mem.indexOfPos(u8, html, start, "</title>") orelse return null;
        const text = html[start..end];
        if (text.len > 0 and text.len < 256) return text;
    }
    return null;
}

fn extractCoverUrl(html: []const u8) ?[]const u8 {
    // Look for detail-info cover img
    const cover_patterns = [_][]const u8{
        "detail-info-cover-img",
        "manga-cover",
        "cover-img",
    };
    for (cover_patterns) |pat| {
        if (std.mem.indexOf(u8, html, pat)) |idx| {
            // Scan back to find the <img tag start
            var scan = idx;
            while (scan > 0 and html[scan] != '<') scan -= 1;
            if (scan == 0) continue;
            const tag_end = std.mem.indexOfPos(u8, html, scan, ">") orelse continue;
            const tag_content = html[scan + 1 .. tag_end];
            if (findAttr(tag_content, "src")) |src| return src;
            if (findAttr(tag_content, "data-src")) |src| return src;
        }
    }
    return null;
}

fn extractLabelValue(html: []const u8, label: []const u8) ?[]const u8 {
    var search_buf: [64]u8 = undefined;
    const needle = std.fmt.bufPrint(&search_buf, "{s}:", .{label}) catch return null;
    const idx = std.mem.indexOf(u8, html, needle) orelse return null;
    var pos = idx + needle.len;
    // Skip whitespace and any tags
    while (pos < html.len and (html[pos] == ' ' or html[pos] == '\t')) pos += 1;
    // Skip any HTML tag
    if (pos < html.len and html[pos] == '<') {
        const gt = std.mem.indexOfPos(u8, html, pos, ">") orelse return null;
        pos = gt + 1;
        while (pos < html.len and (html[pos] == ' ' or html[pos] == '\t')) pos += 1;
    }
    // Read until next < or newline
    const start = pos;
    while (pos < html.len and html[pos] != '<' and html[pos] != '\n' and html[pos] != '\r') pos += 1;
    if (pos <= start) return null;
    const val = html[start..pos];
    if (val.len == 0 or val.len > 128) return null;
    return val;
}

fn parseStatus(html: []const u8) manga.MangaStatus {
    const status_val = extractLabelValue(html, "Status") orelse return .unknown;
    const trimmed = strings_util.trimWhitespace(status_val);
    if (strings_util.containsIgnoreCase(trimmed, "ongoing")) return .ongoing;
    if (strings_util.containsIgnoreCase(trimmed, "completed")) return .completed;
    if (strings_util.containsIgnoreCase(trimmed, "hiatus")) return .hiatus;
    if (strings_util.containsIgnoreCase(trimmed, "cancelled")) return .cancelled;
    if (strings_util.containsIgnoreCase(trimmed, "canceled")) return .cancelled;
    return .unknown;
}

fn extractGenres(allocator: std.mem.Allocator, html: []const u8, list: *std.ArrayListUnmanaged([]const u8)) !void {
    // Look for genre links: <a href="/directory/genre-name/">Genre Name</a>
    var pos: usize = 0;
    while (pos < html.len) {
        const href_start = std.mem.indexOfPos(u8, html, pos, "href=\"/directory/") orelse break;
        const val_start = href_start + 6;
        const val_end = std.mem.indexOfScalarPos(u8, html, val_start, '"') orelse break;
        pos = val_end + 1;

        // Get the link text
        const gt = std.mem.indexOfPos(u8, html, val_end, ">") orelse continue;
        const text_end = std.mem.indexOfPos(u8, html, gt, "</a>") orelse continue;
        const text = strings_util.trimWhitespace(html[gt + 1 .. text_end]);
        if (text.len > 0 and text.len < 64) {
            const copy = try allocator.dupe(u8, text);
            try list.append(allocator, copy);
        }
    }
}

fn extractSummary(html: []const u8) ?[]const u8 {
    const summary_patterns = [_][]const u8{
        "detail-info-right-content",
        "manga-synopsis",
        "synopsis",
        "summary",
    };
    for (summary_patterns) |pat| {
        if (std.mem.indexOf(u8, html, pat)) |idx| {
            const gt = std.mem.indexOfPos(u8, html, idx, ">") orelse continue;
            const end_candidates = [_][]const u8{ "</div>", "</p>", "</section>" };
            var best_end: usize = html.len;
            for (end_candidates) |ec| {
                if (std.mem.indexOfPos(u8, html, gt, ec)) |e| {
                    if (e < best_end) best_end = e;
                }
            }
            if (best_end == html.len) continue;
            const raw = html[gt + 1 .. best_end];
            if (raw.len > 0 and raw.len < 4096) return raw;
        }
    }
    return null;
}

fn findAttr(tag_content: []const u8, attr: []const u8) ?[]const u8 {
    var search_buf: [64]u8 = undefined;
    const needle_dq = std.fmt.bufPrint(&search_buf, "{s}=\"", .{attr}) catch return null;
    if (std.mem.indexOf(u8, tag_content, needle_dq)) |idx| {
        const start = idx + needle_dq.len;
        const end = std.mem.indexOfScalarPos(u8, tag_content, start, '"') orelse return null;
        return tag_content[start..end];
    }
    var search_buf2: [64]u8 = undefined;
    const needle_sq = std.fmt.bufPrint(&search_buf2, "{s}='", .{attr}) catch return null;
    if (std.mem.indexOf(u8, tag_content, needle_sq)) |idx| {
        const start = idx + needle_sq.len;
        const end = std.mem.indexOfScalarPos(u8, tag_content, start, '\'') orelse return null;
        return tag_content[start..end];
    }
    return null;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "parseTitleDetail minimal" {
    const html =
        \\<html><head><title>Naruto</title></head>
        \\<body><h1>Naruto</h1></body></html>
    ;
    var title = try parseTitleDetail(std.testing.allocator, html, "https://fanfox.net/manga/naruto/");
    defer title.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("naruto", title.slug);
    try std.testing.expect(title.title.len > 0);
}

test "parseTitleDetail status ongoing" {
    const html = "<div>Status: <span>Ongoing</span></div>";
    var title = try parseTitleDetail(std.testing.allocator, html, "https://fanfox.net/manga/test/");
    defer title.deinit(std.testing.allocator);
    try std.testing.expectEqual(manga.MangaStatus.ongoing, title.status);
}

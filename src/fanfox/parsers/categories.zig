const std = @import("std");
const manga = @import("../../domain/manga.zig");
const strings_util = @import("../../util/strings.zig");
const urls_util = @import("../../util/urls.zig");

/// Parse a category/listing page to extract MangaTitle items.
/// Resilient to layout variations; returns as many titles as found.
pub fn parseCategoryPage(
    allocator: std.mem.Allocator,
    html: []const u8,
    base_url: []const u8,
) ![]manga.MangaTitle {
    return parseMangaList(allocator, html, base_url);
}

/// Shared manga listing parser used by both categories and directory.
pub fn parseMangaList(
    allocator: std.mem.Allocator,
    html: []const u8,
    base_url: []const u8,
) ![]manga.MangaTitle {
    var titles: std.ArrayListUnmanaged(manga.MangaTitle) = .empty;
    errdefer {
        for (titles.items) |*t| t.deinit(allocator);
        titles.deinit(allocator);
    }

    var pos: usize = 0;
    while (pos < html.len) {
        // Find anchor hrefs pointing to /manga/{slug}/
        const href_pos = std.mem.indexOfPos(u8, html, pos, "href=\"/manga/") orelse break;
        const val_start = href_pos + 6;
        const val_end = std.mem.indexOfScalarPos(u8, html, val_start, '"') orelse {
            pos = val_start + 1;
            continue;
        };
        pos = val_end + 1;

        const href = html[val_start..val_end];
        const slug = urls_util.extractSlug(href) orelse continue;
        if (!urls_util.isValidSlug(slug)) continue;

        // Build absolute URL
        var url_buf: [512]u8 = undefined;
        const full_url = std.fmt.bufPrint(&url_buf, "{s}{s}", .{ base_url, href }) catch continue;

        // Get link text as title (scan forward to >text</a>)
        const gt = std.mem.indexOfPos(u8, html, val_end, ">") orelse continue;
        const a_end = std.mem.indexOfPos(u8, html, gt, "</a>") orelse continue;
        const raw_title = strings_util.trimWhitespace(html[gt + 1 .. a_end]);
        // Skip empty or overly long titles
        if (raw_title.len == 0 or raw_title.len > 256) continue;
        // Skip if the "title" is just an img tag
        if (std.mem.startsWith(u8, raw_title, "<img")) continue;

        // Look for a nearby cover image (within 200 chars before href)
        const scan_start = if (href_pos > 500) href_pos - 500 else 0;
        const cover = findNearbyCover(html[scan_start..href_pos]);

        const slug_copy = try allocator.dupe(u8, slug);
        errdefer allocator.free(slug_copy);

        const title_copy = try allocator.dupe(u8, raw_title);
        errdefer allocator.free(title_copy);

        const url_copy = try allocator.dupe(u8, full_url);
        errdefer allocator.free(url_copy);

        const cover_copy: ?[]const u8 = if (cover) |c|
            allocator.dupe(u8, c) catch null
        else
            null;

        // Avoid duplicates by slug
        var dup = false;
        for (titles.items) |existing| {
            if (std.mem.eql(u8, existing.slug, slug_copy)) {
                dup = true;
                break;
            }
        }
        if (dup) {
            allocator.free(slug_copy);
            allocator.free(title_copy);
            allocator.free(url_copy);
            if (cover_copy) |c| allocator.free(c);
            continue;
        }

        try titles.append(allocator, manga.MangaTitle{
            .slug = slug_copy,
            .title = title_copy,
            .url = url_copy,
            .cover_url = cover_copy,
        });
    }

    return titles.toOwnedSlice(allocator);
}

fn findNearbyCover(fragment: []const u8) ?[]const u8 {
    // Look for an img src that looks like a cover image
    var pos: usize = 0;
    while (pos < fragment.len) {
        const img_pos = std.mem.indexOfPos(u8, fragment, pos, "<img") orelse break;
        const tag_end = std.mem.indexOfPos(u8, fragment, img_pos, ">") orelse break;
        const tag_content = fragment[img_pos + 4 .. tag_end];

        // Try src= and data-src=
        for ([_][]const u8{ "src=\"", "data-src=\"" }) |needle| {
            if (std.mem.indexOf(u8, tag_content, needle)) |idx| {
                const start = idx + needle.len;
                const end = std.mem.indexOfScalarPos(u8, tag_content, start, '"') orelse continue;
                const src = tag_content[start..end];
                if (src.len > 0 and !std.mem.startsWith(u8, src, "data:")) return src;
            }
        }
        pos = tag_end + 1;
    }
    return null;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "parseCategoryPage extracts titles" {
    const html =
        \\<ul>
        \\  <li><a href="/manga/naruto/">Naruto</a></li>
        \\  <li><a href="/manga/one-piece/">One Piece</a></li>
        \\</ul>
    ;
    const titles = try parseCategoryPage(std.testing.allocator, html, "https://fanfox.net");
    defer {
        for (titles) |*t| @constCast(t).deinit(std.testing.allocator);
        std.testing.allocator.free(titles);
    }
    try std.testing.expect(titles.len == 2);
}

test "parseCategoryPage deduplicates slugs" {
    const html =
        \\<a href="/manga/naruto/">Naruto</a>
        \\<a href="/manga/naruto/">Naruto duplicate</a>
    ;
    const titles = try parseCategoryPage(std.testing.allocator, html, "https://fanfox.net");
    defer {
        for (titles) |*t| @constCast(t).deinit(std.testing.allocator);
        std.testing.allocator.free(titles);
    }
    try std.testing.expect(titles.len == 1);
}

const std = @import("std");
const manga = @import("../domain/manga.zig");

pub const library_index_header =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\  <meta charset="UTF-8">
    \\  <meta name="viewport" content="width=device-width, initial-scale=1">
    \\  <title>Manga Library</title>
    \\  <style>
    \\    body { font-family: sans-serif; margin: 0; padding: 20px; background: #1a1a2e; color: #eee; }
    \\    h1 { color: #e94560; }
    \\    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 16px; }
    \\    .card { background: #16213e; border-radius: 8px; overflow: hidden; text-align: center; }
    \\    .card img { width: 100%; height: 200px; object-fit: cover; }
    \\    .card a { display: block; padding: 8px; color: #e94560; text-decoration: none; font-size: 0.9em; }
    \\    .card a:hover { text-decoration: underline; }
    \\  </style>
    \\</head>
    \\<body>
    \\  <h1>Manga Library</h1>
    \\  <div class="grid">
;

pub const library_index_footer =
    \\  </div>
    \\</body>
    \\</html>
;

pub const chapter_reader_template =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\  <meta charset="UTF-8">
    \\  <meta name="viewport" content="width=device-width, initial-scale=1">
    \\  <title>{title} — Chapter {chapter}</title>
    \\  <style>
    \\    body { margin: 0; background: #111; color: #eee; font-family: sans-serif; }
    \\    header { padding: 12px 20px; background: #1a1a2e; }
    \\    header a { color: #e94560; text-decoration: none; margin-right: 12px; }
    \\    .pages { display: flex; flex-direction: column; align-items: center; padding: 20px; }
    \\    .pages img { max-width: 900px; width: 100%; margin-bottom: 8px; }
    \\  </style>
    \\</head>
    \\<body>
    \\  <header>
    \\    <a href="../index.html">← Library</a>
    \\    <a href="index.html">↑ {title}</a>
    \\    <strong>Chapter {chapter}</strong>
    \\  </header>
    \\  <div class="pages">
    \\{pages}
    \\  </div>
    \\</body>
    \\</html>
;

/// Generate the library index HTML for all entries.
pub fn generateLibraryIndex(
    allocator: std.mem.Allocator,
    entries: []const manga.LocalLibraryEntry,
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, library_index_header);

    for (entries) |entry| {
        try buf.appendSlice(allocator, "    <div class=\"card\">\n");
        if (entry.cover_path) |cover| {
            const line = try std.fmt.allocPrint(allocator, "      <img src=\"{s}\" alt=\"{s}\">\n", .{ cover, entry.title });
            defer allocator.free(line);
            try buf.appendSlice(allocator, line);
        }
        const link = try std.fmt.allocPrint(allocator, "      <a href=\"{s}/index.html\">{s}</a>\n", .{ entry.slug, entry.title });
        defer allocator.free(link);
        try buf.appendSlice(allocator, link);
        const cnt = try std.fmt.allocPrint(allocator, "      <small>{d} chapters</small>\n", .{entry.chapters.len});
        defer allocator.free(cnt);
        try buf.appendSlice(allocator, cnt);
        try buf.appendSlice(allocator, "    </div>\n");
    }

    try buf.appendSlice(allocator, library_index_footer);
    return buf.toOwnedSlice(allocator);
}

/// Generate an HTML title/chapter-list page for a manga.
pub fn generateTitlePage(
    allocator: std.mem.Allocator,
    entry: manga.LocalLibraryEntry,
) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);

    const header = try std.fmt.allocPrint(allocator,
        \\<!DOCTYPE html>
        \\<html lang="en">
        \\<head>
        \\  <meta charset="UTF-8">
        \\  <title>{s}</title>
        \\  <style>
        \\    body {{ font-family: sans-serif; margin: 20px; background: #1a1a2e; color: #eee; }}
        \\    h1 {{ color: #e94560; }}
        \\    a {{ color: #e94560; }}
        \\    ul {{ list-style: none; padding: 0; }}
        \\    li {{ margin: 6px 0; }}
        \\  </style>
        \\</head>
        \\<body>
        \\  <p><a href="../index.html">← Library</a></p>
        \\  <h1>{s}</h1>
        \\  <ul>
        \\
    , .{ entry.title, entry.title });
    defer allocator.free(header);
    try buf.appendSlice(allocator, header);

    for (entry.chapters) |ch| {
        const item = try std.fmt.allocPrint(allocator,
            "    <li><a href=\"c{s}/index.html\">Chapter {s}</a></li>\n",
            .{ ch.number, ch.number },
        );
        defer allocator.free(item);
        try buf.appendSlice(allocator, item);
    }

    try buf.appendSlice(allocator,
        \\  </ul>
        \\</body>
        \\</html>
    );

    return buf.toOwnedSlice(allocator);
}

/// Generate a chapter reader HTML page.
pub fn generateChapterPage(
    allocator: std.mem.Allocator,
    manga_title: []const u8,
    chapter_num: []const u8,
    page_paths: []const []const u8,
) ![]u8 {
    var pages_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer pages_buf.deinit(allocator);

    for (page_paths) |page| {
        const line = try std.fmt.allocPrint(allocator, "    <img src=\"{s}\" loading=\"lazy\">\n", .{page});
        defer allocator.free(line);
        try pages_buf.appendSlice(allocator, line);
    }

    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    // Manually substitute placeholders
    const tmpl = chapter_reader_template;
    var pos: usize = 0;
    while (pos < tmpl.len) {
        if (std.mem.indexOfPos(u8, tmpl, pos, "{title}")) |idx| {
            try result.appendSlice(allocator, tmpl[pos..idx]);
            try result.appendSlice(allocator, manga_title);
            pos = idx + "{title}".len;
        } else if (std.mem.indexOfPos(u8, tmpl, pos, "{chapter}")) |idx| {
            try result.appendSlice(allocator, tmpl[pos..idx]);
            try result.appendSlice(allocator, chapter_num);
            pos = idx + "{chapter}".len;
        } else if (std.mem.indexOfPos(u8, tmpl, pos, "{pages}")) |idx| {
            try result.appendSlice(allocator, tmpl[pos..idx]);
            try result.appendSlice(allocator, pages_buf.items);
            pos = idx + "{pages}".len;
        } else {
            try result.appendSlice(allocator, tmpl[pos..]);
            break;
        }
    }

    return result.toOwnedSlice(allocator);
}

// ── Tests ──────────────────────────────────────────────────────────────

test "generateLibraryIndex empty" {
    const html = try generateLibraryIndex(std.testing.allocator, &.{});
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "Manga Library") != null);
}

test "generateChapterPage substitutes placeholders" {
    const pages = [_][]const u8{ "001.jpg", "002.jpg" };
    const html = try generateChapterPage(std.testing.allocator, "Naruto", "1", &pages);
    defer std.testing.allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "Naruto") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "001.jpg") != null);
}

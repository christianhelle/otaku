const std = @import("std");
const manga = @import("../domain/manga.zig");
const templates = @import("templates.zig");

/// Walk library_root, discover manga subdirectories, and generate HTML files.
pub fn buildLibrary(allocator: std.mem.Allocator, library_root: []const u8) !void {
    var root_dir = std.fs.cwd().openDir(library_root, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound or err == error.NotDir) return;
        return err;
    };
    defer root_dir.close();

    var entries: std.ArrayListUnmanaged(manga.LocalLibraryEntry) = .empty;
    defer {
        for (entries.items) |*e| {
            allocator.free(e.slug);
            allocator.free(e.title);
            allocator.free(e.path);
            for (e.chapters) |ch| {
                allocator.free(ch.number);
                allocator.free(ch.path);
            }
            if (e.chapters.len > 0) allocator.free(e.chapters);
        }
        entries.deinit(allocator);
    }

    // Discover manga subdirectories
    var iter = root_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;

        const slug = entry.name;
        const title = slug; // Use slug as title for now

        const slug_copy = try allocator.dupe(u8, slug);
        errdefer allocator.free(slug_copy);
        const title_copy = try allocator.dupe(u8, title);
        errdefer allocator.free(title_copy);

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const dir_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ library_root, slug });
        const path_copy = try allocator.dupe(u8, dir_path);
        errdefer allocator.free(path_copy);

        const chapters = try discoverChapters(allocator, root_dir, slug);
        errdefer {
            for (chapters) |*ch| {
                allocator.free(ch.number);
                allocator.free(ch.path);
            }
            allocator.free(chapters);
        }

        // Optionally look for a cover image
        const cover_path = findCoverPath(allocator, root_dir, slug) catch null;

        try entries.append(allocator, manga.LocalLibraryEntry{
            .slug = slug_copy,
            .title = title_copy,
            .path = path_copy,
            .chapters = chapters,
            .cover_path = cover_path,
        });

        // Generate chapter HTML pages
        for (chapters) |ch| {
            generateChapterHtml(allocator, library_root, slug, ch.number, root_dir) catch {};
        }

        // Generate title index.html
        generateTitleHtml(allocator, library_root, entries.items[entries.items.len - 1]) catch {};
    }

    // Generate root index.html
    try generateIndexHtml(allocator, library_root, entries.items);
}

fn discoverChapters(
    allocator: std.mem.Allocator,
    root_dir: std.fs.Dir,
    slug: []const u8,
) ![]manga.LocalChapter {
    var chapters: std.ArrayListUnmanaged(manga.LocalChapter) = .empty;
    errdefer {
        for (chapters.items) |*ch| {
            allocator.free(ch.number);
            allocator.free(ch.path);
        }
        chapters.deinit(allocator);
    }

    var manga_dir = root_dir.openDir(slug, .{ .iterate = true }) catch return chapters.toOwnedSlice(allocator);
    defer manga_dir.close();

    var iter = manga_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .directory) continue;
        // Chapter dirs are named like "c1", "c2", "c10" etc.
        const name = entry.name;
        if (!std.mem.startsWith(u8, name, "c")) continue;
        const num = name[1..];
        if (num.len == 0) continue;

        const num_copy = try allocator.dupe(u8, num);
        errdefer allocator.free(num_copy);

        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ slug, name });
        errdefer allocator.free(path);

        // Count pages
        var page_count: u32 = 0;
        var chapter_dir = manga_dir.openDir(name, .{ .iterate = true }) catch null;
        if (chapter_dir) |*cd| {
            defer cd.close();
            var ch_iter = cd.iterate();
            while (ch_iter.next() catch null) |f| {
                if (f.kind == .file) page_count += 1;
            }
        }

        try chapters.append(allocator, manga.LocalChapter{
            .number = num_copy,
            .path = path,
            .page_count = page_count,
            .status = if (page_count > 0) .complete else .not_downloaded,
        });
    }

    // Sort chapters numerically
    std.mem.sort(manga.LocalChapter, chapters.items, {}, struct {
        pub fn lessThan(_: void, a: manga.LocalChapter, b: manga.LocalChapter) bool {
            const na = std.fmt.parseFloat(f64, a.number) catch 0;
            const nb = std.fmt.parseFloat(f64, b.number) catch 0;
            return na < nb;
        }
    }.lessThan);

    return chapters.toOwnedSlice(allocator);
}

fn findCoverPath(allocator: std.mem.Allocator, root_dir: std.fs.Dir, slug: []const u8) !?[]const u8 {
    const cover_names = [_][]const u8{ "cover.jpg", "cover.png", "cover.webp", "cover.jpeg" };
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    for (cover_names) |name| {
        const path = std.fmt.bufPrint(&buf, "{s}/{s}", .{ slug, name }) catch continue;
        root_dir.access(path, .{}) catch continue;
        return try allocator.dupe(u8, path);
    }
    return null;
}

fn generateIndexHtml(
    allocator: std.mem.Allocator,
    library_root: []const u8,
    entries: []const manga.LocalLibraryEntry,
) !void {
    const html = try templates.generateLibraryIndex(allocator, entries);
    defer allocator.free(html);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/index.html", .{library_root});
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(html);
}

fn generateTitleHtml(
    allocator: std.mem.Allocator,
    library_root: []const u8,
    entry: manga.LocalLibraryEntry,
) !void {
    const html = try templates.generateTitlePage(allocator, entry);
    defer allocator.free(html);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}/index.html", .{ library_root, entry.slug });

    // Ensure the directory exists
    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_path = try std.fmt.bufPrint(&dir_buf, "{s}/{s}", .{ library_root, entry.slug });
    std.fs.cwd().makePath(dir_path) catch {};

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    try file.writeAll(html);
}

fn generateChapterHtml(
    allocator: std.mem.Allocator,
    library_root: []const u8,
    slug: []const u8,
    chapter_num: []const u8,
    root_dir: std.fs.Dir,
) !void {
    // Collect page image filenames
    var pages: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (pages.items) |p| allocator.free(p);
        pages.deinit(allocator);
    }

    var ch_dir_buf: [512]u8 = undefined;
    const ch_dir_path = try std.fmt.bufPrint(&ch_dir_buf, "{s}/c{s}", .{ slug, chapter_num });
    var ch_dir = root_dir.openDir(ch_dir_path, .{ .iterate = true }) catch return;
    defer ch_dir.close();

    var iter = ch_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        const ext = std.fs.path.extension(entry.name);
        if (ext.len == 0) continue;
        // Accept common image extensions (case-sensitive check; fanfox uses lowercase)
        if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg") or
            std.mem.eql(u8, ext, ".png") or std.mem.eql(u8, ext, ".webp") or
            std.mem.eql(u8, ext, ".gif") or std.mem.eql(u8, ext, ".JPG") or
            std.mem.eql(u8, ext, ".PNG"))
        {
            const copy = try allocator.dupe(u8, entry.name);
            try pages.append(allocator, copy);
        }
    }

    // Sort pages by name
    std.mem.sort([]const u8, pages.items, {}, struct {
        pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    const html = try templates.generateChapterPage(allocator, slug, chapter_num, pages.items);
    defer allocator.free(html);

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}/c{s}/index.html", .{ library_root, slug, chapter_num });

    var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
    const dir_p = try std.fmt.bufPrint(&dir_buf, "{s}/{s}/c{s}", .{ library_root, slug, chapter_num });
    std.fs.cwd().makePath(dir_p) catch {};

    const file = std.fs.cwd().createFile(path, .{}) catch return;
    defer file.close();
    try file.writeAll(html);
}

// ── Tests ──────────────────────────────────────────────────────────────

test "buildLibrary nonexistent root returns silently" {
    // Should not error on missing directory
    try buildLibrary(std.testing.allocator, "./nonexistent_library_xyz");
}

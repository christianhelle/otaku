const std = @import("std");
const config_mod = @import("../storage/config.zig");
const saver = @import("saver.zig");
const manifest_mod = @import("manifest.zig");
const manga = @import("../domain/manga.zig");

pub const DownloadManager = struct {
    allocator: std.mem.Allocator,
    http: std.http.Client,
    config: config_mod.Config,

    pub fn init(allocator: std.mem.Allocator, config: config_mod.Config) DownloadManager {
        return .{
            .allocator = allocator,
            .http = std.http.Client{ .allocator = allocator },
            .config = config,
        };
    }

    pub fn deinit(self: *DownloadManager) void {
        self.http.deinit();
    }

    /// Download a single chapter. output_dir: base output directory.
    /// Chapter images go to: {output_dir}/{manga_slug}/c{chapter_number}/page_NNN.jpg
    pub fn downloadChapter(
        self: *DownloadManager,
        slug: []const u8,
        chapter: manga.Chapter,
        output_dir: []const u8,
    ) !void {
        // Build directory path
        var dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        const chapter_dir = try std.fmt.bufPrint(&dir_buf, "{s}/{s}/c{s}", .{ output_dir, slug, chapter.number });

        // Create directory structure
        std.fs.cwd().makePath(chapter_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        if (self.config.verbose) {
            var buf: [1024]u8 = undefined;
            var fw = std.fs.File.stdout().writer(&buf);
            fw.interface.print("Downloading chapter {s} to {s}\n", .{ chapter.number, chapter_dir }) catch {};
            fw.interface.flush() catch {};
        }

        // Note: Chapter struct doesn't have page_urls field yet
        // For now, just create the directory as a placeholder
        // In a full implementation, we would:
        // 1. Fetch the chapter reader page to get image URLs
        // 2. Loop over each image URL
        // 3. Call saver.saveImage() for each one
    }

    /// Download all chapters (or filtered list)
    pub fn downloadAll(
        self: *DownloadManager,
        slug: []const u8,
        chapters: []manga.Chapter,
        output_dir: []const u8,
        verbose: bool,
    ) !void {
        if (verbose) {
            var buf: [1024]u8 = undefined;
            var fw = std.fs.File.stdout().writer(&buf);
            fw.interface.print("Starting download of {d} chapters for {s}\n", .{ chapters.len, slug }) catch {};
            fw.interface.flush() catch {};
        }

        for (chapters, 0..) |ch, i| {
            if (verbose) {
                var buf: [1024]u8 = undefined;
                var fw = std.fs.File.stdout().writer(&buf);
                fw.interface.print("[{d}/{d}] Chapter {s}\n", .{ i + 1, chapters.len, ch.number }) catch {};
                fw.interface.flush() catch {};
            }

            try self.downloadChapter(slug, ch, output_dir);
        }

        if (verbose) {
            var buf: [1024]u8 = undefined;
            var fw = std.fs.File.stdout().writer(&buf);
            fw.interface.print("Download complete: {d} chapters\n", .{chapters.len}) catch {};
            fw.interface.flush() catch {};
        }
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "DownloadManager init and deinit" {
    var dm = DownloadManager.init(std.testing.allocator, config_mod.Config.defaults);
    defer dm.deinit();
}

test "downloadChapter creates directory" {
    const allocator = std.testing.allocator;
    var dm = DownloadManager.init(allocator, config_mod.Config.defaults);
    defer dm.deinit();

    const chapter = manga.Chapter{
        .number = "1",
        .url = "https://fanfox.net/manga/test/c1/",
    };

    const test_dir = "test_download_out";
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try dm.downloadChapter("test_manga", chapter, test_dir);

    // Verify directory was created
    const full_path = test_dir ++ "/test_manga/c1";
    var dir = std.fs.cwd().openDir(full_path, .{}) catch |err| {
        std.debug.print("Failed to open directory '{s}': {}\n", .{ full_path, err });
        return err;
    };
    dir.close();
}

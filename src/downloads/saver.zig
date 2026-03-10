const std = @import("std");
const http_client = @import("../http/client.zig");
const config_mod = @import("../storage/config.zig");

/// Download an image from url and write it to path on disk.
/// Creates parent directory if needed. Skips if file already exists.
pub fn saveImage(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    url: []const u8,
    path: []const u8,
    config: config_mod.Config,
) !void {
    // Skip if already exists
    if (std.fs.cwd().access(path, .{})) |_| {
        return; // already downloaded
    } else |_| {}

    // Create parent directories
    if (std.fs.path.dirname(path)) |dir| {
        std.fs.cwd().makePath(dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    const fetch_opts = http_client.FetchOptions{
        .timeout_ms = config.timeout_ms,
        .user_agent = config.user_agent,
        .max_body_size = 20 * 1024 * 1024, // 20 MB for images
    };

    var resp = try http_client.fetch(client, allocator, url, fetch_opts);
    defer resp.deinit();

    if (!resp.isSuccess()) return error.HttpError;
    if (resp.body.len == 0) return error.EmptyResponse;

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    try file.writeAll(resp.body);
}

/// Determine the file extension from a URL or content type.
pub fn imageExtension(url: []const u8, content_type: ?[]const u8) []const u8 {
    if (content_type) |ct| {
        if (std.mem.indexOf(u8, ct, "jpeg") != null or std.mem.indexOf(u8, ct, "jpg") != null) return ".jpg";
        if (std.mem.indexOf(u8, ct, "png") != null) return ".png";
        if (std.mem.indexOf(u8, ct, "gif") != null) return ".gif";
        if (std.mem.indexOf(u8, ct, "webp") != null) return ".webp";
    }
    // Fall back to URL extension
    const clean = blk: {
        const q = std.mem.indexOf(u8, url, "?") orelse url.len;
        break :blk url[0..q];
    };
    if (std.mem.lastIndexOf(u8, clean, ".")) |dot| {
        const ext = clean[dot..];
        if (ext.len >= 2 and ext.len <= 5) return ext;
    }
    return ".jpg";
}

// ── Tests ──────────────────────────────────────────────────────────────

test "imageExtension from content type" {
    try std.testing.expectEqualStrings(".png", imageExtension("https://example.com/img", "image/png"));
    try std.testing.expectEqualStrings(".jpg", imageExtension("https://example.com/img", "image/jpeg"));
}

test "imageExtension from URL" {
    try std.testing.expectEqualStrings(".png", imageExtension("https://example.com/img.png", null));
    try std.testing.expectEqualStrings(".jpg", imageExtension("https://example.com/img.jpg?v=1", null));
}

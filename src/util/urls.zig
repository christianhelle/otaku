const std = @import("std");

/// Extract the manga slug from a Fanfox URL.
/// e.g. "https://fanfox.net/manga/naruto/" → "naruto"
/// e.g. "https://fanfox.net/manga/one_piece/v1/c1/" → "one_piece"
/// Returns null if the URL does not contain "/manga/".
pub fn extractSlug(url: []const u8) ?[]const u8 {
    const manga_prefix = "/manga/";
    const idx = std.mem.indexOf(u8, url, manga_prefix) orelse return null;
    const after = url[idx + manga_prefix.len ..];
    const end = std.mem.indexOfScalar(u8, after, '/') orelse after.len;
    if (end == 0) return null;
    return after[0..end];
}

/// Returns true if the slug is a valid non-empty identifier with no
/// slashes and not starting with a dot.
pub fn isValidSlug(slug: []const u8) bool {
    if (slug.len == 0) return false;
    if (slug[0] == '.') return false;
    for (slug) |c| {
        if (c == '/') return false;
    }
    return true;
}

/// Returns true if the URL belongs to fanfox.net.
pub fn isFanfoxUrl(url: []const u8) bool {
    return std.mem.indexOf(u8, url, "fanfox.net") != null;
}

/// Construct a fanfox manga URL from a slug into buf.
pub fn mangaUrl(slug: []const u8, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf, "https://fanfox.net/manga/{s}/", .{slug});
}

/// Resolve a relative URL against a base URL into buf.
pub fn resolveUrl(base: []const u8, path: []const u8, buf: []u8) ![]const u8 {
    if (std.mem.startsWith(u8, path, "http://") or std.mem.startsWith(u8, path, "https://")) {
        if (path.len > buf.len) return error.NoSpaceLeft;
        @memcpy(buf[0..path.len], path);
        return buf[0..path.len];
    }
    const origin = getOrigin(base);
    if (std.mem.startsWith(u8, path, "/")) {
        return std.fmt.bufPrint(buf, "{s}{s}", .{ origin, path });
    }
    const after_origin = if (base.len > origin.len) base[origin.len..] else "/";
    const last_slash = std.mem.lastIndexOf(u8, after_origin, "/") orelse 0;
    const base_dir = after_origin[0 .. last_slash + 1];
    return std.fmt.bufPrint(buf, "{s}{s}{s}", .{ origin, base_dir, path });
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

// ── Tests ─────────────────────────────────────────────────────────────

test "extractSlug basic" {
    try std.testing.expectEqualStrings("naruto", extractSlug("https://fanfox.net/manga/naruto/").?);
}

test "extractSlug with sub-path" {
    try std.testing.expectEqualStrings("one_piece", extractSlug("https://fanfox.net/manga/one_piece/v1/c1/").?);
}

test "extractSlug no manga prefix returns null" {
    try std.testing.expectEqual(@as(?[]const u8, null), extractSlug("https://example.com/other"));
}

test "extractSlug empty returns null" {
    try std.testing.expectEqual(@as(?[]const u8, null), extractSlug(""));
}

test "isValidSlug valid" {
    try std.testing.expect(isValidSlug("naruto"));
    try std.testing.expect(isValidSlug("one_piece"));
    try std.testing.expect(isValidSlug("dragon_ball_z"));
}

test "isValidSlug empty is invalid" {
    try std.testing.expect(!isValidSlug(""));
}

test "isValidSlug dot-prefixed is invalid" {
    try std.testing.expect(!isValidSlug(".hidden"));
}

test "isValidSlug with slash is invalid" {
    try std.testing.expect(!isValidSlug("a/b"));
}

test "isFanfoxUrl" {
    try std.testing.expect(isFanfoxUrl("https://fanfox.net/manga/naruto/"));
    try std.testing.expect(isFanfoxUrl("http://fanfox.net/"));
    try std.testing.expect(!isFanfoxUrl("https://google.com/"));
    try std.testing.expect(!isFanfoxUrl(""));
}

test "mangaUrl" {
    var buf: [256]u8 = undefined;
    const url = try mangaUrl("naruto", &buf);
    try std.testing.expectEqualStrings("https://fanfox.net/manga/naruto/", url);
}

test "resolveUrl absolute passthrough" {
    var buf: [256]u8 = undefined;
    const url = try resolveUrl("https://fanfox.net/manga/naruto/", "https://cdn.example.com/img.jpg", &buf);
    try std.testing.expectEqualStrings("https://cdn.example.com/img.jpg", url);
}

test "resolveUrl root-relative" {
    var buf: [256]u8 = undefined;
    const url = try resolveUrl("https://fanfox.net/manga/naruto/", "/images/cover.jpg", &buf);
    try std.testing.expectEqualStrings("https://fanfox.net/images/cover.jpg", url);
}

const std = @import("std");

pub fn trimWhitespace(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\n\r");
}

pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

pub fn parseChapterRange(s: []const u8, from: *f64, to: *f64) !void {
    if (std.mem.indexOf(u8, s, "-")) |dash| {
        from.* = std.fmt.parseFloat(f64, s[0..dash]) catch return error.InvalidFormat;
        to.* = std.fmt.parseFloat(f64, s[dash + 1 ..]) catch return error.InvalidFormat;
    } else {
        const v = std.fmt.parseFloat(f64, s) catch return error.InvalidFormat;
        from.* = v;
        to.* = v;
    }
}

pub const SplitResult = struct { head: []const u8, tail: []const u8 };

/// Split on the first occurrence of delim. head excludes delim, tail begins after delim.
/// If delim is not found, head = s, tail = "".
pub fn splitOnce(s: []const u8, delim: []const u8) SplitResult {
    if (std.mem.indexOf(u8, s, delim)) |idx| {
        return .{ .head = s[0..idx], .tail = s[idx + delim.len ..] };
    }
    return .{ .head = s, .tail = "" };
}

pub fn formatFileSize(bytes: u64, buf: []u8) []const u8 {
    if (bytes < 1024) {
        return std.fmt.bufPrint(buf, "{d} B", .{bytes}) catch buf[0..0];
    } else if (bytes < 1024 * 1024) {
        return std.fmt.bufPrint(buf, "{d} KB", .{bytes / 1024}) catch buf[0..0];
    } else if (bytes < 1024 * 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
        return std.fmt.bufPrint(buf, "{d:.1} MB", .{mb}) catch buf[0..0];
    } else {
        const gb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0);
        return std.fmt.bufPrint(buf, "{d:.2} GB", .{gb}) catch buf[0..0];
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

test "trimWhitespace" {
    try std.testing.expectEqualStrings("hello", trimWhitespace("  hello  "));
    try std.testing.expectEqualStrings("hello", trimWhitespace("hello"));
    try std.testing.expectEqualStrings("", trimWhitespace("   "));
    try std.testing.expectEqualStrings("a b", trimWhitespace(" a b "));
}

test "containsIgnoreCase" {
    try std.testing.expect(containsIgnoreCase("Hello World", "world"));
    try std.testing.expect(containsIgnoreCase("NARUTO", "naruto"));
    try std.testing.expect(!containsIgnoreCase("hello", "xyz"));
    try std.testing.expect(containsIgnoreCase("", "") == true);
}

test "parseChapterRange full range" {
    var from: f64 = 0;
    var to: f64 = 0;
    try parseChapterRange("1-10", &from, &to);
    try std.testing.expectEqual(@as(f64, 1.0), from);
    try std.testing.expectEqual(@as(f64, 10.0), to);
}

test "parseChapterRange single chapter" {
    var from: f64 = 0;
    var to: f64 = 0;
    try parseChapterRange("5", &from, &to);
    try std.testing.expectEqual(@as(f64, 5.0), from);
    try std.testing.expectEqual(@as(f64, 5.0), to);
}

test "parseChapterRange decimal" {
    var from: f64 = 0;
    var to: f64 = 0;
    try parseChapterRange("5.5-10", &from, &to);
    try std.testing.expectApproxEqAbs(@as(f64, 5.5), from, 0.001);
    try std.testing.expectEqual(@as(f64, 10.0), to);
}

test "parseChapterRange invalid returns error" {
    var from: f64 = 0;
    var to: f64 = 0;
    try std.testing.expectError(error.InvalidFormat, parseChapterRange("abc", &from, &to));
}

test "formatFileSize bytes" {
    var buf: [32]u8 = undefined;
    const s = formatFileSize(512, &buf);
    try std.testing.expect(std.mem.indexOf(u8, s, "B") != null);
}

test "formatFileSize kilobytes" {
    var buf: [32]u8 = undefined;
    const s = formatFileSize(2048, &buf);
    try std.testing.expect(std.mem.indexOf(u8, s, "KB") != null);
}

test "formatFileSize megabytes" {
    var buf: [32]u8 = undefined;
    const s = formatFileSize(2 * 1024 * 1024, &buf);
    try std.testing.expect(std.mem.indexOf(u8, s, "MB") != null);
}

test "formatFileSize gigabytes" {
    var buf: [32]u8 = undefined;
    const s = formatFileSize(2 * 1024 * 1024 * 1024, &buf);
    try std.testing.expect(std.mem.indexOf(u8, s, "GB") != null);
}

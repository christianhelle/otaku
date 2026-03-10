const std = @import("std");
const manga = @import("manga.zig");
const Chapter = manga.Chapter;

/// Parse a chapter number string into a float for comparison.
/// Handles patterns like "5", "5.5", "v2/c10", "c10.5", "10".
pub fn parseChapterNumber(s: []const u8) f64 {
    // Try to find "c" prefix pattern (e.g. "v2/c10" or "c10.5")
    var num_str = s;

    // If there's a slash, take the part after it
    if (std.mem.lastIndexOfScalar(u8, s, '/')) |slash| {
        num_str = s[slash + 1 ..];
    }

    // Strip leading 'c' or 'C' prefix
    if (num_str.len > 0 and (num_str[0] == 'c' or num_str[0] == 'C')) {
        num_str = num_str[1..];
    }

    // Strip leading 'v' or 'V' prefix (for standalone "v2" patterns)
    if (num_str.len > 0 and (num_str[0] == 'v' or num_str[0] == 'V')) {
        num_str = num_str[1..];
    }

    if (num_str.len == 0) return 0.0;

    return std.fmt.parseFloat(f64, num_str) catch 0.0;
}

/// Numeric-aware chapter number comparison.
/// Compares chapter numbers as floats so "5.5" sorts between "5" and "6".
pub fn compareChapterNumbers(a: []const u8, b: []const u8) std.math.Order {
    const num_a = parseChapterNumber(a);
    const num_b = parseChapterNumber(b);
    return std.math.order(num_a, num_b);
}

/// Filter chapters whose numeric value falls within [from, to] inclusive.
/// Caller owns the returned slice and must free it with the same allocator.
pub fn filterChaptersInRange(
    allocator: std.mem.Allocator,
    chapters: []const Chapter,
    from: f64,
    to: f64,
) ![]Chapter {
    var result: std.ArrayList(Chapter) = .empty;
    errdefer result.deinit(allocator);
    for (chapters) |ch| {
        const n = parseChapterNumber(ch.number);
        if (n >= from and n <= to) {
            try result.append(allocator, ch);
        }
    }
    return result.toOwnedSlice(allocator);
}

/// Sort a slice of Chapters in ascending order by chapter number.
pub fn sortChapters(chapters: []Chapter) void {
    std.mem.sort(Chapter, chapters, {}, struct {
        fn lessThan(_: void, lhs: Chapter, rhs: Chapter) bool {
            return compareChapterNumbers(lhs.number, rhs.number) == .lt;
        }
    }.lessThan);
}

// ── Tests ─────────────────────────────────────────────────────────────

test "parseChapterNumber simple integers" {
    try std.testing.expectEqual(@as(f64, 5.0), parseChapterNumber("5"));
    try std.testing.expectEqual(@as(f64, 10.0), parseChapterNumber("10"));
    try std.testing.expectEqual(@as(f64, 100.0), parseChapterNumber("100"));
}

test "parseChapterNumber decimals" {
    try std.testing.expectEqual(@as(f64, 5.5), parseChapterNumber("5.5"));
    try std.testing.expectEqual(@as(f64, 10.1), parseChapterNumber("10.1"));
}

test "parseChapterNumber with prefixes" {
    try std.testing.expectEqual(@as(f64, 10.0), parseChapterNumber("c10"));
    try std.testing.expectEqual(@as(f64, 10.0), parseChapterNumber("v2/c10"));
    try std.testing.expectEqual(@as(f64, 10.5), parseChapterNumber("c10.5"));
}

test "parseChapterNumber empty and invalid" {
    try std.testing.expectEqual(@as(f64, 0.0), parseChapterNumber(""));
    try std.testing.expectEqual(@as(f64, 0.0), parseChapterNumber("abc"));
}

test "compareChapterNumbers ordering" {
    try std.testing.expectEqual(std.math.Order.lt, compareChapterNumbers("1", "2"));
    try std.testing.expectEqual(std.math.Order.gt, compareChapterNumbers("10", "5"));
    try std.testing.expectEqual(std.math.Order.eq, compareChapterNumbers("5", "5"));
    try std.testing.expectEqual(std.math.Order.lt, compareChapterNumbers("5", "5.5"));
    try std.testing.expectEqual(std.math.Order.lt, compareChapterNumbers("5.5", "6"));
}

test "sortChapters ascending" {
    var chapters = [_]Chapter{
        .{ .number = "10", .url = "u10" },
        .{ .number = "1", .url = "u1" },
        .{ .number = "5.5", .url = "u5.5" },
        .{ .number = "5", .url = "u5" },
        .{ .number = "2", .url = "u2" },
    };
    sortChapters(&chapters);
    try std.testing.expectEqualStrings("1", chapters[0].number);
    try std.testing.expectEqualStrings("2", chapters[1].number);
    try std.testing.expectEqualStrings("5", chapters[2].number);
    try std.testing.expectEqualStrings("5.5", chapters[3].number);
    try std.testing.expectEqualStrings("10", chapters[4].number);
}

test "filterChaptersInRange basic range" {
    const allocator = std.testing.allocator;
    const chapters = [_]Chapter{
        .{ .number = "1", .url = "u1" },
        .{ .number = "2", .url = "u2" },
        .{ .number = "3", .url = "u3" },
        .{ .number = "5.5", .url = "u5.5" },
        .{ .number = "10", .url = "u10" },
        .{ .number = "20", .url = "u20" },
    };
    const result = try filterChaptersInRange(allocator, &chapters, 2.0, 10.0);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 4), result.len);
    try std.testing.expectEqualStrings("2", result[0].number);
    try std.testing.expectEqualStrings("3", result[1].number);
    try std.testing.expectEqualStrings("5.5", result[2].number);
    try std.testing.expectEqualStrings("10", result[3].number);
}

test "filterChaptersInRange single chapter" {
    const allocator = std.testing.allocator;
    const chapters = [_]Chapter{
        .{ .number = "1", .url = "u1" },
        .{ .number = "5.5", .url = "u5.5" },
        .{ .number = "10", .url = "u10" },
    };
    const result = try filterChaptersInRange(allocator, &chapters, 5.5, 5.5);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("5.5", result[0].number);
}

test "filterChaptersInRange no matches" {
    const allocator = std.testing.allocator;
    const chapters = [_]Chapter{
        .{ .number = "1", .url = "u1" },
        .{ .number = "2", .url = "u2" },
    };
    const result = try filterChaptersInRange(allocator, &chapters, 100.0, 200.0);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "filterChaptersInRange empty input" {
    const allocator = std.testing.allocator;
    const chapters = [_]Chapter{};
    const result = try filterChaptersInRange(allocator, &chapters, 1.0, 10.0);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

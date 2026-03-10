const std = @import("std");

pub const StatusFilter = enum {
    all,
    ongoing,
    completed,

    pub fn queryParam(self: StatusFilter) ?[]const u8 {
        return switch (self) {
            .all => null,
            .ongoing => "ongoing",
            .completed => "completed",
        };
    }
};

pub const GenreFilter = struct {
    genre: []const u8,
};

pub const SortOrder = enum {
    latest,
    newest,
    top_rating,
    az,
    za,

    pub fn queryParam(self: SortOrder) []const u8 {
        return switch (self) {
            .latest => "latest",
            .newest => "newest",
            .top_rating => "rating",
            .az => "az",
            .za => "za",
        };
    }
};

pub const BrowseFilter = struct {
    status: StatusFilter = .all,
    genre: ?[]const u8 = null,
    sort: SortOrder = .latest,
    page: u32 = 1,
};

// ── Tests ─────────────────────────────────────────────────────────────

test "StatusFilter query params" {
    try std.testing.expectEqual(@as(?[]const u8, null), StatusFilter.all.queryParam());
    try std.testing.expectEqualStrings("ongoing", StatusFilter.ongoing.queryParam().?);
    try std.testing.expectEqualStrings("completed", StatusFilter.completed.queryParam().?);
}

test "BrowseFilter defaults" {
    const f = BrowseFilter{};
    try std.testing.expectEqual(StatusFilter.all, f.status);
    try std.testing.expectEqual(@as(?[]const u8, null), f.genre);
    try std.testing.expectEqual(@as(u32, 1), f.page);
}

test "SortOrder query params" {
    try std.testing.expectEqualStrings("latest", SortOrder.latest.queryParam());
    try std.testing.expectEqualStrings("newest", SortOrder.newest.queryParam());
    try std.testing.expectEqualStrings("rating", SortOrder.top_rating.queryParam());
    try std.testing.expectEqualStrings("az", SortOrder.az.queryParam());
    try std.testing.expectEqualStrings("za", SortOrder.za.queryParam());
}

test "GenreFilter stores genre" {
    const gf = GenreFilter{ .genre = "action" };
    try std.testing.expectEqualStrings("action", gf.genre);
}

test "BrowseFilter with genre and page" {
    const f = BrowseFilter{ .genre = "action", .page = 3, .sort = .top_rating };
    try std.testing.expectEqualStrings("action", f.genre.?);
    try std.testing.expectEqual(@as(u32, 3), f.page);
    try std.testing.expectEqual(SortOrder.top_rating, f.sort);
}

test "BrowseFilter sort default is latest" {
    const f = BrowseFilter{};
    try std.testing.expectEqual(SortOrder.latest, f.sort);
}

const std = @import("std");

// Re-export category types from manga.zig for convenience
pub const CategoryKind = @import("manga.zig").CategoryKind;
pub const CategoryFeed = @import("manga.zig").CategoryFeed;
pub const MangaTitle = @import("manga.zig").MangaTitle;

test "CategoryKind re-export" {
    try std.testing.expectEqualStrings("hot", CategoryKind.hot.slug());
}

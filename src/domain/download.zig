const std = @import("std");

// Re-export download types from manga.zig for convenience
pub const DownloadStatus = @import("manga.zig").DownloadStatus;
pub const DownloadJob = @import("manga.zig").DownloadJob;
pub const LocalChapter = @import("manga.zig").LocalChapter;
pub const LocalChapterStatus = @import("manga.zig").LocalChapterStatus;
pub const LocalLibraryEntry = @import("manga.zig").LocalLibraryEntry;

test "DownloadStatus re-export" {
    try std.testing.expectEqual(DownloadStatus.pending, DownloadStatus.pending);
}

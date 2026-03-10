const std = @import("std");
const manga = @import("../domain/manga.zig");

pub const DownloadQueue = struct {
    jobs: std.ArrayListUnmanaged(manga.DownloadJob),

    pub fn init() DownloadQueue {
        return .{ .jobs = .empty };
    }

    pub fn deinit(self: *DownloadQueue, allocator: std.mem.Allocator) void {
        self.jobs.deinit(allocator);
    }

    pub fn enqueue(self: *DownloadQueue, allocator: std.mem.Allocator, job: manga.DownloadJob) !void {
        try self.jobs.append(allocator, job);
    }

    pub fn dequeue(self: *DownloadQueue) ?manga.DownloadJob {
        if (self.jobs.items.len == 0) return null;
        const job = self.jobs.items[0];
        _ = self.jobs.orderedRemove(0);
        return job;
    }

    pub fn len(self: DownloadQueue) usize {
        return self.jobs.items.len;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "DownloadQueue init and deinit" {
    var queue = DownloadQueue.init();
    defer queue.deinit(std.testing.allocator);
}

test "DownloadQueue enqueue and dequeue" {
    const allocator = std.testing.allocator;
    var queue = DownloadQueue.init();
    defer queue.deinit(allocator);

    const job1 = manga.DownloadJob{
        .manga_slug = "naruto",
        .chapter_number = "1",
        .url = "https://fanfox.net/manga/naruto/c1/",
        .output_dir = "./manga",
    };

    const job2 = manga.DownloadJob{
        .manga_slug = "naruto",
        .chapter_number = "2",
        .url = "https://fanfox.net/manga/naruto/c2/",
        .output_dir = "./manga",
    };

    try queue.enqueue(allocator, job1);
    try queue.enqueue(allocator, job2);

    try std.testing.expectEqual(@as(usize, 2), queue.len());

    const dequeued1 = queue.dequeue();
    try std.testing.expect(dequeued1 != null);
    try std.testing.expectEqualStrings("1", dequeued1.?.chapter_number);

    const dequeued2 = queue.dequeue();
    try std.testing.expect(dequeued2 != null);
    try std.testing.expectEqualStrings("2", dequeued2.?.chapter_number);

    const dequeued3 = queue.dequeue();
    try std.testing.expectEqual(@as(?manga.DownloadJob, null), dequeued3);
}

test "DownloadQueue len" {
    const allocator = std.testing.allocator;
    var queue = DownloadQueue.init();
    defer queue.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), queue.len());

    const job = manga.DownloadJob{
        .manga_slug = "test",
        .chapter_number = "1",
        .url = "https://example.com",
        .output_dir = "./out",
    };

    try queue.enqueue(allocator, job);
    try std.testing.expectEqual(@as(usize, 1), queue.len());

    _ = queue.dequeue();
    try std.testing.expectEqual(@as(usize, 0), queue.len());
}

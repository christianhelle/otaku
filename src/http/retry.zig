const std = @import("std");
const http_client = @import("client.zig");

pub const RetryConfig = struct {
    max_retries: u8 = 3,
    base_delay_ms: u32 = 500,
    max_delay_ms: u32 = 10_000,
};

/// Fetch with retry and exponential backoff.
/// Retries on connection errors and 5xx responses.
pub fn retryFetch(
    client: *std.http.Client,
    allocator: std.mem.Allocator,
    url: []const u8,
    fetch_opts: http_client.FetchOptions,
    retry_cfg: RetryConfig,
) !http_client.Response {
    var attempt: u8 = 0;
    while (true) {
        const result = http_client.fetch(client, allocator, url, fetch_opts);

        if (result) |resp| {
            if (!resp.isServerError()) return resp;
            // Server error: retry if attempts remain
            if (attempt >= retry_cfg.max_retries) return resp;
            var mut_resp = resp;
            mut_resp.deinit();
        } else |_| {
            if (attempt >= retry_cfg.max_retries) return result;
        }

        // Exponential backoff: delay = min(base * 2^attempt, max)
        const shift: u6 = @intCast(@min(attempt, 10));
        const delay_ms: u64 = @min(
            @as(u64, retry_cfg.base_delay_ms) * (@as(u64, 1) << shift),
            @as(u64, retry_cfg.max_delay_ms),
        );
        std.Thread.sleep(delay_ms * 1_000_000);
        attempt += 1;
    }
}

// ── Tests ──────────────────────────────────────────────────────────────

test "RetryConfig defaults" {
    const cfg = RetryConfig{};
    try std.testing.expectEqual(@as(u8, 3), cfg.max_retries);
    try std.testing.expectEqual(@as(u32, 500), cfg.base_delay_ms);
    try std.testing.expectEqual(@as(u32, 10_000), cfg.max_delay_ms);
}

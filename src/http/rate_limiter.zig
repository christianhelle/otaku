const std = @import("std");

pub const RateLimiter = struct {
    delay_ms: u32,
    last_request_ns: i128 = 0,

    pub fn wait(self: *RateLimiter) void {
        if (self.delay_ms == 0) return;
        const now = std.time.nanoTimestamp();
        const delay_ns: i128 = @as(i128, self.delay_ms) * 1_000_000;
        const elapsed = now - self.last_request_ns;
        if (elapsed < delay_ns) {
            const sleep_ns: u64 = @intCast(delay_ns - elapsed);
            std.Thread.sleep(sleep_ns);
        }
    }

    pub fn recordRequest(self: *RateLimiter) void {
        self.last_request_ns = std.time.nanoTimestamp();
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "RateLimiter zero delay never sleeps" {
    var rl = RateLimiter{ .delay_ms = 0 };
    rl.wait(); // should return immediately
    rl.recordRequest();
    try std.testing.expect(rl.last_request_ns != 0);
}

test "RateLimiter recordRequest sets timestamp" {
    var rl = RateLimiter{ .delay_ms = 200 };
    const before = std.time.nanoTimestamp();
    rl.recordRequest();
    try std.testing.expect(rl.last_request_ns >= before);
}

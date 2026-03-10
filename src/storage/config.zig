const std = @import("std");

pub const Config = struct {
    library_root: []const u8,
    timeout_ms: u32,
    delay_ms: u32,
    concurrency: u8,
    retries: u8,
    user_agent: []const u8,
    cache_dir: []const u8,
    verbose: bool,
    auto_build_library: bool,

    pub const defaults = Config{
        .library_root = "./manga",
        .timeout_ms = 10_000,
        .delay_ms = 200,
        .concurrency = 3,
        .retries = 3,
        .user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        .cache_dir = ".otaku-cache",
        .verbose = false,
        .auto_build_library = false,
    };
};

/// Load configuration from a JSON file at the given path.
/// Returns defaults if the file does not exist.
pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    _ = allocator;
    _ = path;
    // TODO: implement JSON config loading
    return Config.defaults;
}

/// Save configuration to a JSON file at the given path.
pub fn saveConfig(config: Config, path: []const u8) !void {
    _ = config;
    _ = path;
    // TODO: implement JSON config saving
}

// ── Tests ─────────────────────────────────────────────────────────────

test "Config defaults" {
    const cfg = Config.defaults;
    try std.testing.expectEqual(@as(u32, 10_000), cfg.timeout_ms);
    try std.testing.expectEqual(@as(u32, 200), cfg.delay_ms);
    try std.testing.expectEqual(@as(u8, 3), cfg.concurrency);
    try std.testing.expectEqual(@as(u8, 3), cfg.retries);
    try std.testing.expectEqual(false, cfg.verbose);
    try std.testing.expectEqual(false, cfg.auto_build_library);
    try std.testing.expectEqualStrings("./manga", cfg.library_root);
    try std.testing.expectEqualStrings(".otaku-cache", cfg.cache_dir);
}

test "loadConfig returns defaults" {
    const cfg = try loadConfig(std.testing.allocator, "nonexistent.json");
    try std.testing.expectEqual(@as(u32, 10_000), cfg.timeout_ms);
}

test "Config default user agent is non-empty" {
    try std.testing.expect(Config.defaults.user_agent.len > 0);
}

test "Config default delay and concurrency" {
    const cfg = Config.defaults;
    try std.testing.expectEqual(@as(u32, 200), cfg.delay_ms);
    try std.testing.expectEqual(@as(u8, 3), cfg.concurrency);
    try std.testing.expectEqual(@as(u8, 3), cfg.retries);
}

test "Config default library root is relative path" {
    try std.testing.expect(Config.defaults.library_root.len > 0);
    // Should be a relative path starting with "./"
    try std.testing.expect(std.mem.startsWith(u8, Config.defaults.library_root, "./"));
}

test "Config default cache dir" {
    try std.testing.expect(Config.defaults.cache_dir.len > 0);
    try std.testing.expectEqualStrings(".otaku-cache", Config.defaults.cache_dir);
}

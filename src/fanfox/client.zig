const std = @import("std");
const http_client = @import("../http/client.zig");
const retry_mod = @import("../http/retry.zig");
const rate_limiter_mod = @import("../http/rate_limiter.zig");
const config_mod = @import("../storage/config.zig");
const endpoints = @import("endpoints.zig");
const chapters_parser = @import("parsers/chapters.zig");
const title_parser = @import("parsers/title.zig");
const categories_parser = @import("parsers/categories.zig");
const manga = @import("../domain/manga.zig");

pub const FanfoxClient = struct {
    allocator: std.mem.Allocator,
    http: std.http.Client,
    limiter: rate_limiter_mod.RateLimiter,
    config: config_mod.Config,

    pub fn init(allocator: std.mem.Allocator, config: config_mod.Config) FanfoxClient {
        return .{
            .allocator = allocator,
            .http = std.http.Client{ .allocator = allocator },
            .limiter = rate_limiter_mod.RateLimiter{ .delay_ms = config.delay_ms },
            .config = config,
        };
    }

    pub fn deinit(self: *FanfoxClient) void {
        self.http.deinit();
    }

    fn fetchUrl(self: *FanfoxClient, url: []const u8) !http_client.Response {
        self.limiter.wait();
        defer self.limiter.recordRequest();

        const fetch_opts = http_client.FetchOptions{
            .timeout_ms = self.config.timeout_ms,
            .user_agent = self.config.user_agent,
        };
        const retry_cfg = retry_mod.RetryConfig{
            .max_retries = self.config.retries,
        };
        return retry_mod.retryFetch(&self.http, self.allocator, url, fetch_opts, retry_cfg);
    }

    /// Fetch a category feed (hot, trending, etc.)
    pub fn fetchCategory(self: *FanfoxClient, kind: manga.CategoryKind) !manga.CategoryFeed {
        const url = switch (kind) {
            .hot => endpoints.Endpoints.hot,
            .trending => endpoints.Endpoints.trending,
            .new_release => endpoints.Endpoints.new_release,
            .last_updates => endpoints.Endpoints.last_updates,
            .recommended => endpoints.Endpoints.hot,
            .reading_now => endpoints.Endpoints.hot,
            .genre => endpoints.Endpoints.directory,
            .search => endpoints.Endpoints.search,
        };

        var resp = try self.fetchUrl(url);
        defer resp.deinit();

        if (!resp.isSuccess()) {
            return manga.CategoryFeed{ .kind = kind };
        }

        const titles = categories_parser.parseCategoryPage(self.allocator, resp.body, endpoints.base_url) catch
            try self.allocator.alloc(manga.MangaTitle, 0);

        return manga.CategoryFeed{
            .kind = kind,
            .titles = titles,
        };
    }

    /// Fetch title details for a given URL.
    pub fn fetchTitle(self: *FanfoxClient, url: []const u8) !manga.MangaTitle {
        var resp = try self.fetchUrl(url);
        defer resp.deinit();

        if (!resp.isSuccess()) {
            const slug_copy = try self.allocator.dupe(u8, "unknown");
            const title_copy = try self.allocator.dupe(u8, "Unknown");
            const url_copy = try self.allocator.dupe(u8, url);
            return manga.MangaTitle{
                .slug = slug_copy,
                .title = title_copy,
                .url = url_copy,
            };
        }

        return title_parser.parseTitleDetail(self.allocator, resp.body, url);
    }

    /// Fetch chapter list for a manga slug.
    pub fn fetchChapters(self: *FanfoxClient, slug: []const u8) ![]manga.Chapter {
        var url_buf: [512]u8 = undefined;
        const url = try endpoints.buildMangaUrl(slug, &url_buf);

        var resp = try self.fetchUrl(url);
        defer resp.deinit();

        if (!resp.isSuccess()) {
            return self.allocator.alloc(manga.Chapter, 0);
        }

        return chapters_parser.parseChapterList(self.allocator, resp.body, slug, endpoints.base_url);
    }

    /// Search for manga by query string.
    pub fn search(self: *FanfoxClient, query: []const u8) ![]manga.MangaTitle {
        var url_buf: [512]u8 = undefined;
        const url = try endpoints.buildSearchUrl(query, &url_buf);

        var resp = try self.fetchUrl(url);
        defer resp.deinit();

        if (!resp.isSuccess()) {
            return self.allocator.alloc(manga.MangaTitle, 0);
        }

        return categories_parser.parseCategoryPage(self.allocator, resp.body, endpoints.base_url);
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "FanfoxClient init/deinit" {
    var client = FanfoxClient.init(std.testing.allocator, config_mod.Config.defaults);
    defer client.deinit();
    try std.testing.expectEqual(@as(u32, 200), client.limiter.delay_ms);
}

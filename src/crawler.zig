/// HTTP-based web crawler for fetching manga metadata and page images.
const std = @import("std");
const manga = @import("manga.zig");

pub const CrawlerError = error{
    NetworkError,
    ParseError,
    InvalidUrl,
    TooManyRedirects,
    OutOfMemory,
};

/// Lightweight HTML attribute/text extractor – not a full parser,
/// but sufficient for scraping well-known patterns.
pub const HtmlParser = struct {
    source: []const u8,

    pub fn init(source: []const u8) HtmlParser {
        return .{ .source = source };
    }

    /// Extract the inner text of the first element matching the given tag name.
    pub fn firstTagText(self: HtmlParser, allocator: std.mem.Allocator, tag: []const u8) !?[]u8 {
        var open_buf: [64]u8 = undefined;
        const open_tag = try std.fmt.bufPrint(&open_buf, "<{s}", .{tag});
        const idx = std.mem.indexOf(u8, self.source, open_tag) orelse return null;
        // Find end of opening tag
        const tag_end = std.mem.indexOfPos(u8, self.source, idx, ">") orelse return null;
        // Find closing tag
        var close_buf: [64]u8 = undefined;
        const close_tag = try std.fmt.bufPrint(&close_buf, "</{s}>", .{tag});
        const close_idx = std.mem.indexOfPos(u8, self.source, tag_end + 1, close_tag) orelse return null;
        const inner = self.source[tag_end + 1 .. close_idx];
        return try allocator.dupe(u8, stripHtmlTags(inner));
    }

    /// Extract the value of a named attribute from the first element with the given tag.
    pub fn firstAttr(self: HtmlParser, allocator: std.mem.Allocator, tag: []const u8, attr: []const u8) !?[]u8 {
        var open_buf: [64]u8 = undefined;
        const open_tag = try std.fmt.bufPrint(&open_buf, "<{s}", .{tag});
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, self.source, pos, open_tag)) |idx| {
            const tag_end = std.mem.indexOfPos(u8, self.source, idx, ">") orelse break;
            const attrs_slice = self.source[idx..tag_end];

            var attr_buf: [128]u8 = undefined;
            // Try attr="..." pattern
            const dq = try std.fmt.bufPrint(&attr_buf, "{s}=\"", .{attr});
            if (std.mem.indexOf(u8, attrs_slice, dq)) |a_idx| {
                const val_start = a_idx + dq.len;
                const val_end = std.mem.indexOfPos(u8, attrs_slice, val_start, "\"") orelse break;
                return try allocator.dupe(u8, attrs_slice[val_start..val_end]);
            }
            // Try attr='...' pattern
            const sq = try std.fmt.bufPrint(&attr_buf, "{s}='", .{attr});
            if (std.mem.indexOf(u8, attrs_slice, sq)) |a_idx| {
                const val_start = a_idx + sq.len;
                const val_end = std.mem.indexOfPos(u8, attrs_slice, val_start, "'") orelse break;
                return try allocator.dupe(u8, attrs_slice[val_start..val_end]);
            }
            pos = tag_end + 1;
        }
        return null;
    }

    /// Collect values of a given attribute from all elements with the given tag.
    pub fn allAttrs(self: HtmlParser, allocator: std.mem.Allocator, tag: []const u8, attr: []const u8) ![][]u8 {
        var results: std.ArrayList([]u8) = .empty;
        errdefer {
            for (results.items) |item| allocator.free(item);
            results.deinit(allocator);
        }

        var open_buf: [64]u8 = undefined;
        const open_tag = try std.fmt.bufPrint(&open_buf, "<{s}", .{tag});
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, self.source, pos, open_tag)) |idx| {
            const tag_end = std.mem.indexOfPos(u8, self.source, idx, ">") orelse break;
            const attrs_slice = self.source[idx..tag_end];
            pos = tag_end + 1;

            var attr_buf: [128]u8 = undefined;
            const dq = try std.fmt.bufPrint(&attr_buf, "{s}=\"", .{attr});
            if (std.mem.indexOf(u8, attrs_slice, dq)) |a_idx| {
                const val_start = a_idx + dq.len;
                const val_end = std.mem.indexOfPos(u8, attrs_slice, val_start, "\"") orelse continue;
                const val = try allocator.dupe(u8, attrs_slice[val_start..val_end]);
                try results.append(allocator, val);
            }
        }
        return results.toOwnedSlice(allocator);
    }

    /// Collect inner text of all elements with a given tag.
    pub fn allTagText(self: HtmlParser, allocator: std.mem.Allocator, tag: []const u8) ![][]u8 {
        var results: std.ArrayList([]u8) = .empty;
        errdefer {
            for (results.items) |item| allocator.free(item);
            results.deinit(allocator);
        }

        var open_buf: [64]u8 = undefined;
        const open_tag = try std.fmt.bufPrint(&open_buf, "<{s}", .{tag});
        var close_buf: [64]u8 = undefined;
        const close_tag = try std.fmt.bufPrint(&close_buf, "</{s}>", .{tag});
        var pos: usize = 0;

        while (std.mem.indexOfPos(u8, self.source, pos, open_tag)) |idx| {
            const tag_end = std.mem.indexOfPos(u8, self.source, idx, ">") orelse break;
            const close_idx = std.mem.indexOfPos(u8, self.source, tag_end + 1, close_tag) orelse break;
            const inner = self.source[tag_end + 1 .. close_idx];
            const text = try allocator.dupe(u8, stripHtmlTags(inner));
            try results.append(allocator, text);
            pos = close_idx + close_tag.len;
        }
        return results.toOwnedSlice(allocator);
    }

    /// Remove all HTML tags from a string, returning a trimmed slice of the original.
    pub fn stripHtmlTags(s: []const u8) []const u8 {
        // Find first non-tag content
        var start: usize = 0;
        while (start < s.len and s[start] == '<') {
            const end = std.mem.indexOfPos(u8, s, start, ">") orelse break;
            start = end + 1;
        }
        // Find last non-tag content
        var end: usize = s.len;
        while (end > start) {
            const maybe_close = end - 1;
            if (s[maybe_close] == '>') {
                const open = std.mem.lastIndexOfScalar(u8, s[0..maybe_close], '<') orelse break;
                end = open;
            } else break;
        }
        return std.mem.trim(u8, s[start..end], " \t\n\r");
    }
};

/// Parse a URL query string like "?title=hello+world" into its components.
pub fn encodeQueryParam(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            try out.append(allocator, byte);
        } else if (byte == ' ') {
            try out.append(allocator, '+');
        } else {
            var hex: [3]u8 = undefined;
            _ = try std.fmt.bufPrint(&hex, "%{X:0>2}", .{byte});
            try out.appendSlice(allocator, &hex);
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Represents a crawl response containing raw bytes.
pub const FetchResponse = struct {
    body: []u8,
    status_code: u16,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *FetchResponse) void {
        self.allocator.free(self.body);
    }
};

/// Performs HTTP GET requests and parses manga metadata.
pub const Crawler = struct {
    allocator: std.mem.Allocator,
    http_client: std.http.Client,

    pub fn init(allocator: std.mem.Allocator) Crawler {
        return .{
            .allocator = allocator,
            .http_client = std.http.Client{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *Crawler) void {
        self.http_client.deinit();
    }

    /// Fetch a URL and return the body bytes. Caller owns the returned FetchResponse.
    pub fn fetch(self: *Crawler, url: []const u8) !FetchResponse {
        const uri = std.Uri.parse(url) catch return CrawlerError.InvalidUrl;
        var aw = std.Io.Writer.Allocating.init(self.allocator);
        errdefer aw.deinit();
        const res = self.http_client.fetch(.{
            .location = .{ .uri = uri },
            .response_writer = &aw.writer,
        }) catch {
            aw.deinit();
            return CrawlerError.NetworkError;
        };
        // Take ownership of the buffer from aw; aw is now empty (deinit safe).
        var body_list = aw.toArrayList();
        const body = try body_list.toOwnedSlice(self.allocator);
        return FetchResponse{
            .body = body,
            .status_code = @intFromEnum(res.status),
            .allocator = self.allocator,
        };
    }

    /// Search for manga on a given site. Returns owned slice; caller must free.
    pub fn searchMangaDex(self: *Crawler, query: []const u8) ![]manga.Manga {
        const encoded = try encodeQueryParam(self.allocator, query);
        defer self.allocator.free(encoded);
        const url = try std.fmt.allocPrint(self.allocator, "https://api.mangadex.org/manga?title={s}&limit=20&order[relevance]=desc", .{encoded});
        defer self.allocator.free(url);

        var resp = try self.fetch(url);
        defer resp.deinit();
        return try parseMangaDexSearch(self.allocator, resp.body);
    }

    /// Parse a MangaDex /manga JSON response. Caller owns returned slice.
    pub fn parseMangaDexSearch(allocator: std.mem.Allocator, json_body: []const u8) ![]manga.Manga {
        var results: std.ArrayList(manga.Manga) = .empty;
        errdefer {
            for (results.items) |*m| {
                var mutable = m.*;
                mutable.free(allocator);
            }
            results.deinit(allocator);
        }

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_body, .{}) catch return CrawlerError.ParseError;
        defer parsed.deinit();
        const root = parsed.value;

        const data = switch (root) {
            .object => |obj| obj.get("data") orelse return results.toOwnedSlice(allocator),
            else => return results.toOwnedSlice(allocator),
        };

        const items = switch (data) {
            .array => |arr| arr.items,
            else => return results.toOwnedSlice(allocator),
        };

        for (items) |item| {
            const obj = switch (item) {
                .object => |o| o,
                else => continue,
            };
            const id_val = obj.get("id") orelse continue;
            const id_str = switch (id_val) {
                .string => |s| s,
                else => continue,
            };

            // Extract English title from attributes.titles
            var title_str: []const u8 = "";
            var description_str: []const u8 = "";
            var status_str: []const u8 = "unknown";

            if (obj.get("attributes")) |attrs_val| {
                if (attrs_val == .object) {
                    const attrs = attrs_val.object;
                    if (attrs.get("title")) |title_val| {
                        if (title_val == .object) {
                            if (title_val.object.get("en")) |en| {
                                if (en == .string) title_str = en.string;
                            } else {
                                // Use first available language
                                var it = title_val.object.iterator();
                                if (it.next()) |kv| {
                                    if (kv.value_ptr.* == .string) title_str = kv.value_ptr.*.string;
                                }
                            }
                        }
                    }
                    if (attrs.get("description")) |desc_val| {
                        if (desc_val == .object) {
                            if (desc_val.object.get("en")) |en| {
                                if (en == .string) description_str = en.string;
                            }
                        }
                    }
                    if (attrs.get("status")) |s| {
                        if (s == .string) status_str = s.string;
                    }
                }
            }

            const manga_url = try std.fmt.allocPrint(allocator, "https://api.mangadex.org/manga/{s}", .{id_str});
            errdefer allocator.free(manga_url);

            const m = manga.Manga{
                .title = try allocator.dupe(u8, title_str),
                .url = manga_url,
                .cover_url = try allocator.dupe(u8, ""),
                .description = try allocator.dupe(u8, description_str),
                .status = manga.MangaStatus.fromString(status_str),
                .site = try allocator.dupe(u8, "MangaDex"),
            };
            try results.append(allocator, m);
        }
        return results.toOwnedSlice(allocator);
    }

    /// Parse MangaDex chapter list JSON. Returns owned slice of Chapters.
    pub fn parseMangaDexChapters(allocator: std.mem.Allocator, manga_id: i64, json_body: []const u8) ![]manga.Chapter {
        var results: std.ArrayList(manga.Chapter) = .empty;
        errdefer {
            for (results.items) |*ch| {
                var mutable = ch.*;
                mutable.free(allocator);
            }
            results.deinit(allocator);
        }

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, json_body, .{}) catch return CrawlerError.ParseError;
        defer parsed.deinit();

        const data = switch (parsed.value) {
            .object => |obj| obj.get("data") orelse return results.toOwnedSlice(allocator),
            else => return results.toOwnedSlice(allocator),
        };
        const items = switch (data) {
            .array => |arr| arr.items,
            else => return results.toOwnedSlice(allocator),
        };

        for (items) |item| {
            const obj = switch (item) {
                .object => |o| o,
                else => continue,
            };
            const id_val = obj.get("id") orelse continue;
            const id_str = switch (id_val) {
                .string => |s| s,
                else => continue,
            };
            var chapter_num: f64 = 0;
            var chapter_title: []const u8 = "";
            if (obj.get("attributes")) |attrs_val| {
                if (attrs_val == .object) {
                    const attrs = attrs_val.object;
                    if (attrs.get("chapter")) |cn| {
                        if (cn == .string) {
                            chapter_num = std.fmt.parseFloat(f64, cn.string) catch 0;
                        } else if (cn == .float) {
                            chapter_num = cn.float;
                        } else if (cn == .integer) {
                            chapter_num = @floatFromInt(cn.integer);
                        }
                    }
                    if (attrs.get("title")) |t| {
                        if (t == .string) chapter_title = t.string;
                    }
                }
            }
            const chapter_url = try std.fmt.allocPrint(allocator, "https://api.mangadex.org/at-home/server/{s}", .{id_str});
            errdefer allocator.free(chapter_url);
            const ch = manga.Chapter{
                .manga_id = manga_id,
                .number = chapter_num,
                .title = try allocator.dupe(u8, chapter_title),
                .url = chapter_url,
            };
            try results.append(allocator, ch);
        }
        return results.toOwnedSlice(allocator);
    }
};

// ---------- Unit Tests ----------

test "stripHtmlTags basic" {
    try std.testing.expectEqualStrings("Hello World", HtmlParser.stripHtmlTags("Hello World"));
    try std.testing.expectEqualStrings("Hello World", HtmlParser.stripHtmlTags("<b>Hello World</b>"));
    try std.testing.expectEqualStrings("text", HtmlParser.stripHtmlTags("  text  "));
}

test "HtmlParser.firstTagText" {
    const allocator = std.testing.allocator;
    const html = "<html><head><title>My Page</title></head><body><h1>Hello</h1></body></html>";
    const parser = HtmlParser.init(html);
    const title = try parser.firstTagText(allocator, "title");
    defer if (title) |t| allocator.free(t);
    try std.testing.expect(title != null);
    try std.testing.expectEqualStrings("My Page", title.?);
}

test "HtmlParser.firstAttr" {
    const allocator = std.testing.allocator;
    const html = "<img src=\"https://example.com/cover.jpg\" alt=\"cover\">";
    const parser = HtmlParser.init(html);
    const src = try parser.firstAttr(allocator, "img", "src");
    defer if (src) |s| allocator.free(s);
    try std.testing.expect(src != null);
    try std.testing.expectEqualStrings("https://example.com/cover.jpg", src.?);
}

test "HtmlParser.allAttrs" {
    const allocator = std.testing.allocator;
    const html =
        \\<div>
        \\  <a href="https://example.com/ch1">Chapter 1</a>
        \\  <a href="https://example.com/ch2">Chapter 2</a>
        \\  <a href="https://example.com/ch3">Chapter 3</a>
        \\</div>
    ;
    const parser = HtmlParser.init(html);
    const hrefs = try parser.allAttrs(allocator, "a", "href");
    defer {
        for (hrefs) |h| allocator.free(h);
        allocator.free(hrefs);
    }
    try std.testing.expectEqual(@as(usize, 3), hrefs.len);
    try std.testing.expectEqualStrings("https://example.com/ch1", hrefs[0]);
    try std.testing.expectEqualStrings("https://example.com/ch3", hrefs[2]);
}

test "HtmlParser.allTagText" {
    const allocator = std.testing.allocator;
    const html = "<ul><li>One</li><li>Two</li><li>Three</li></ul>";
    const parser = HtmlParser.init(html);
    const items = try parser.allTagText(allocator, "li");
    defer {
        for (items) |item| allocator.free(item);
        allocator.free(items);
    }
    try std.testing.expectEqual(@as(usize, 3), items.len);
    try std.testing.expectEqualStrings("One", items[0]);
    try std.testing.expectEqualStrings("Two", items[1]);
    try std.testing.expectEqualStrings("Three", items[2]);
}

test "encodeQueryParam" {
    const allocator = std.testing.allocator;
    const encoded = try encodeQueryParam(allocator, "hello world");
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("hello+world", encoded);
}

test "encodeQueryParam special chars" {
    const allocator = std.testing.allocator;
    const encoded = try encodeQueryParam(allocator, "one piece");
    defer allocator.free(encoded);
    try std.testing.expectEqualStrings("one+piece", encoded);
}

test "parseMangaDexSearch valid JSON" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "data": [
        \\    {
        \\      "id": "abc-123",
        \\      "attributes": {
        \\        "title": {"en": "Test Manga"},
        \\        "description": {"en": "A test description"},
        \\        "status": "ongoing"
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    const results = try Crawler.parseMangaDexSearch(allocator, json);
    defer {
        for (results) |*m| {
            var mutable = m.*;
            mutable.free(allocator);
        }
        allocator.free(results);
    }
    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Test Manga", results[0].title);
    try std.testing.expectEqualStrings("A test description", results[0].description);
    try std.testing.expectEqual(manga.MangaStatus.ongoing, results[0].status);
    try std.testing.expectEqualStrings("MangaDex", results[0].site);
}

test "parseMangaDexSearch empty data" {
    const allocator = std.testing.allocator;
    const json = "{\"data\": []}";
    const results = try Crawler.parseMangaDexSearch(allocator, json);
    defer allocator.free(results);
    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "parseMangaDexSearch invalid JSON" {
    const allocator = std.testing.allocator;
    const result = Crawler.parseMangaDexSearch(allocator, "not json at all");
    try std.testing.expectError(CrawlerError.ParseError, result);
}

test "parseMangaDexChapters valid JSON" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "data": [
        \\    {
        \\      "id": "ch-001",
        \\      "attributes": {
        \\        "chapter": "1",
        \\        "title": "The Start"
        \\      }
        \\    },
        \\    {
        \\      "id": "ch-002",
        \\      "attributes": {
        \\        "chapter": "2",
        \\        "title": ""
        \\      }
        \\    }
        \\  ]
        \\}
    ;
    const chapters = try Crawler.parseMangaDexChapters(allocator, 42, json);
    defer {
        for (chapters) |*ch| {
            var mutable = ch.*;
            mutable.free(allocator);
        }
        allocator.free(chapters);
    }
    try std.testing.expectEqual(@as(usize, 2), chapters.len);
    try std.testing.expectEqual(@as(i64, 42), chapters[0].manga_id);
    try std.testing.expectEqual(@as(f64, 1.0), chapters[0].number);
    try std.testing.expectEqualStrings("The Start", chapters[0].title);
    try std.testing.expectEqual(@as(f64, 2.0), chapters[1].number);
}

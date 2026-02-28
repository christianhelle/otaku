const std = @import("std");
const manga = @import("manga.zig");
const Allocator = std.mem.Allocator;

/// HTTP-based manga crawler targeting the MangaDex public API.
/// Supports searching manga titles, fetching chapter lists, and resolving page image URLs.
pub const Crawler = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Crawler {
        return .{ .allocator = allocator };
    }

    /// Build a MangaDex search URL for the given query string.
    pub fn buildSearchUrl(buf: []u8, query: []const u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "https://api.mangadex.org/manga?title={s}&limit=20&includes[]=cover_art", .{query}) catch error.NameTooLong;
    }

    /// Build a MangaDex chapter feed URL for the given manga source ID.
    pub fn buildChapterFeedUrl(buf: []u8, manga_source_id: []const u8) ![]const u8 {
        return std.fmt.bufPrint(
            buf,
            "https://api.mangadex.org/manga/{s}/feed?translatedLanguage[]=en&order[chapter]=asc&limit=100",
            .{manga_source_id},
        ) catch error.NameTooLong;
    }

    /// Build a MangaDex at-home server URL for page image resolution.
    pub fn buildPageUrl(buf: []u8, chapter_source_id: []const u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "https://api.mangadex.org/at-home/server/{s}", .{chapter_source_id}) catch error.NameTooLong;
    }

    /// Parse a MangaDex manga search JSON response into a list of Manga structs.
    pub fn parseSearchResults(self: *const Crawler, json_data: []const u8) !std.ArrayList(manga.Manga) {
        var results: std.ArrayList(manga.Manga) = .empty;
        errdefer {
            for (results.items) |*m| m.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        var scanner = JsonScanner.init(json_data);

        // Find "data" array
        if (!scanner.findKey("\"data\"")) return results;
        if (!scanner.skipToChar('[')) return results;

        // Parse each manga object in the array
        while (scanner.pos < scanner.data.len) {
            if (!scanner.skipToChar('{')) break;
            const obj_start = scanner.pos;

            // Find end of this object (balanced braces)
            const obj_end = scanner.findMatchingBrace() orelse break;
            const obj_slice = scanner.data[obj_start..obj_end];

            var obj_scanner = JsonScanner.init(obj_slice);

            const source_id = obj_scanner.extractStringValue("\"id\"") orelse continue;
            const title = extractTitle(obj_slice) orelse "Unknown";
            const description = extractDescription(obj_slice) orelse "";

            try results.append(self.allocator, .{
                .id = 0,
                .source = .mangadex,
                .source_id = try self.allocator.dupe(u8, source_id),
                .title = try self.allocator.dupe(u8, title),
                .description = try self.allocator.dupe(u8, description),
                .cover_url = try self.allocator.dupe(u8, ""),
                .url = try self.allocator.dupe(u8, ""),
            });

            // Check if there are more objects
            if (scanner.pos >= scanner.data.len) break;
            if (scanner.peekChar() == ']') break;
        }

        return results;
    }

    /// Parse a MangaDex chapter feed JSON response.
    pub fn parseChapterFeed(self: *const Crawler, json_data: []const u8, manga_id: u64) !std.ArrayList(manga.Chapter) {
        var results: std.ArrayList(manga.Chapter) = .empty;
        errdefer {
            for (results.items) |*c| c.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        var scanner = JsonScanner.init(json_data);
        if (!scanner.findKey("\"data\"")) return results;
        if (!scanner.skipToChar('[')) return results;

        while (scanner.pos < scanner.data.len) {
            if (!scanner.skipToChar('{')) break;
            const obj_start = scanner.pos;
            const obj_end = scanner.findMatchingBrace() orelse break;
            const obj_slice = scanner.data[obj_start..obj_end];

            var obj_scanner = JsonScanner.init(obj_slice);

            const source_id = obj_scanner.extractStringValue("\"id\"") orelse continue;

            // Extract chapter number from attributes
            const chapter_num = extractChapterNumber(obj_slice) orelse 0;
            const chapter_title = extractChapterTitle(obj_slice) orelse "";

            try results.append(self.allocator, .{
                .id = 0,
                .manga_id = manga_id,
                .source_id = try self.allocator.dupe(u8, source_id),
                .number = chapter_num,
                .title = try self.allocator.dupe(u8, chapter_title),
                .url = try self.allocator.dupe(u8, ""),
            });

            if (scanner.pos >= scanner.data.len) break;
            if (scanner.peekChar() == ']') break;
        }

        return results;
    }

    /// Parse a MangaDex at-home server response to get page image URLs.
    pub fn parsePageList(self: *const Crawler, json_data: []const u8, chapter_id: u64) !std.ArrayList(manga.Page) {
        var results: std.ArrayList(manga.Page) = .empty;
        errdefer {
            for (results.items) |*p| p.deinit(self.allocator);
            results.deinit(self.allocator);
        }

        var scanner = JsonScanner.init(json_data);

        // Extract baseUrl
        const base_url = scanner.extractStringValue("\"baseUrl\"") orelse return results;

        // Find chapter hash
        scanner.pos = 0;
        if (!scanner.findKey("\"hash\"")) return results;
        const hash = scanner.extractNextString() orelse return results;

        // Find "data" array (page filenames)
        scanner.pos = 0;
        // Look for "data" inside "chapter" object
        if (!scanner.findKey("\"chapter\"")) return results;
        if (!scanner.findKey("\"data\"")) return results;
        if (!scanner.skipToChar('[')) return results;
        scanner.pos += 1; // skip past '['

        var page_num: u32 = 1;
        while (scanner.pos < scanner.data.len) {
            const filename = scanner.extractNextString() orelse break;

            var url_buf: [2048]u8 = undefined;
            const url = std.fmt.bufPrint(&url_buf, "{s}/data/{s}/{s}", .{ base_url, hash, filename }) catch continue;

            try results.append(self.allocator, .{
                .id = 0,
                .chapter_id = chapter_id,
                .number = page_num,
                .image_url = try self.allocator.dupe(u8, url),
                .local_path = try self.allocator.dupe(u8, ""),
            });
            page_num += 1;

            // Skip comma or break on ]
            while (scanner.pos < scanner.data.len) : (scanner.pos += 1) {
                const ch = scanner.data[scanner.pos];
                if (ch == '"') break;
                if (ch == ']') break;
            }
            if (scanner.pos >= scanner.data.len) break;
            if (scanner.data[scanner.pos] == ']') break;
        }

        return results;
    }
};

// ── Lightweight JSON scanner ───────────────────────────────────────────

/// Minimal forward-only JSON scanner that extracts values by key name.
/// No allocations; works on slices. Not a full parser—just enough
/// for the well-structured MangaDex API responses.
const JsonScanner = struct {
    data: []const u8,
    pos: usize,

    fn init(data: []const u8) JsonScanner {
        return .{ .data = data, .pos = 0 };
    }

    /// Advance past the next occurrence of `key` (including its colon).
    fn findKey(self: *JsonScanner, key: []const u8) bool {
        while (self.pos + key.len <= self.data.len) {
            if (std.mem.startsWith(u8, self.data[self.pos..], key)) {
                self.pos += key.len;
                self.skipWhitespace();
                if (self.pos < self.data.len and self.data[self.pos] == ':') {
                    self.pos += 1;
                    self.skipWhitespace();
                    return true;
                }
            }
            self.pos += 1;
        }
        return false;
    }

    /// Extract the string value immediately after the current position.
    fn extractStringValue(self: *JsonScanner, key: []const u8) ?[]const u8 {
        if (!self.findKey(key)) return null;
        return self.extractNextString();
    }

    /// Extract the next JSON string (between quotes) at current position.
    fn extractNextString(self: *JsonScanner) ?[]const u8 {
        self.skipWhitespace();
        if (self.pos >= self.data.len or self.data[self.pos] != '"') return null;
        self.pos += 1; // skip opening quote
        const start = self.pos;
        while (self.pos < self.data.len) {
            if (self.data[self.pos] == '\\') {
                self.pos += 2; // skip escaped character
                continue;
            }
            if (self.data[self.pos] == '"') {
                const result = self.data[start..self.pos];
                self.pos += 1; // skip closing quote
                return result;
            }
            self.pos += 1;
        }
        return null;
    }

    fn skipWhitespace(self: *JsonScanner) void {
        while (self.pos < self.data.len and
            (self.data[self.pos] == ' ' or self.data[self.pos] == '\t' or
            self.data[self.pos] == '\n' or self.data[self.pos] == '\r'))
        {
            self.pos += 1;
        }
    }

    fn skipToChar(self: *JsonScanner, ch: u8) bool {
        while (self.pos < self.data.len) {
            if (self.data[self.pos] == ch) return true;
            self.pos += 1;
        }
        return false;
    }

    fn peekChar(self: *const JsonScanner) u8 {
        if (self.pos >= self.data.len) return 0;
        return self.data[self.pos];
    }

    /// Find the matching closing brace for the current '{'. Returns the position
    /// one past the closing brace. Advances self.pos past the matched object.
    fn findMatchingBrace(self: *JsonScanner) ?usize {
        if (self.pos >= self.data.len or self.data[self.pos] != '{') return null;
        var depth: u32 = 0;
        var in_string = false;
        var i = self.pos;
        while (i < self.data.len) : (i += 1) {
            const ch = self.data[i];
            if (in_string) {
                if (ch == '\\') {
                    i += 1;
                    continue;
                }
                if (ch == '"') in_string = false;
                continue;
            }
            switch (ch) {
                '"' => in_string = true,
                '{' => depth += 1,
                '}' => {
                    depth -= 1;
                    if (depth == 0) {
                        self.pos = i + 1;
                        return i + 1;
                    }
                },
                else => {},
            }
        }
        return null;
    }
};

fn extractTitle(obj: []const u8) ?[]const u8 {
    // Look for "title":{"en":"..."} pattern
    var scanner = JsonScanner.init(obj);
    if (!scanner.findKey("\"title\"")) return null;
    return scanner.extractStringValue("\"en\"");
}

fn extractDescription(obj: []const u8) ?[]const u8 {
    var scanner = JsonScanner.init(obj);
    if (!scanner.findKey("\"description\"")) return null;
    return scanner.extractStringValue("\"en\"");
}

fn extractChapterNumber(obj: []const u8) ?f64 {
    var scanner = JsonScanner.init(obj);
    if (!scanner.findKey("\"attributes\"")) return null;
    if (!scanner.findKey("\"chapter\"")) return null;
    scanner.skipWhitespace();
    if (scanner.pos >= scanner.data.len) return null;
    if (scanner.data[scanner.pos] == 'n') return null; // null
    if (scanner.data[scanner.pos] == '"') {
        const s = scanner.extractNextString() orelse return null;
        return std.fmt.parseFloat(f64, s) catch null;
    }
    return null;
}

fn extractChapterTitle(obj: []const u8) ?[]const u8 {
    var scanner = JsonScanner.init(obj);
    if (!scanner.findKey("\"attributes\"")) return null;
    return scanner.extractStringValue("\"title\"");
}

// ── Tests ──────────────────────────────────────────────────────────────

test "buildSearchUrl produces valid URL" {
    var buf: [512]u8 = undefined;
    const url = try Crawler.buildSearchUrl(&buf, "one+piece");
    try std.testing.expect(std.mem.indexOf(u8, url, "manga?title=one+piece") != null);
    try std.testing.expect(std.mem.startsWith(u8, url, "https://api.mangadex.org"));
}

test "buildChapterFeedUrl produces valid URL" {
    var buf: [512]u8 = undefined;
    const url = try Crawler.buildChapterFeedUrl(&buf, "abc-123");
    try std.testing.expect(std.mem.indexOf(u8, url, "/manga/abc-123/feed") != null);
}

test "buildPageUrl produces valid URL" {
    var buf: [512]u8 = undefined;
    const url = try Crawler.buildPageUrl(&buf, "ch-456");
    try std.testing.expect(std.mem.indexOf(u8, url, "/at-home/server/ch-456") != null);
}

test "parseSearchResults extracts manga from JSON" {
    const allocator = std.testing.allocator;
    const crawler = Crawler.init(allocator);

    const json =
        \\{"result":"ok","data":[{"id":"abc-123","type":"manga","attributes":{"title":{"en":"One Piece"},"description":{"en":"Pirates!"}}}]}
    ;

    var results = try crawler.parseSearchResults(json);
    defer {
        for (results.items) |*m| m.deinit(allocator);
        results.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqualStrings("abc-123", results.items[0].source_id);
    try std.testing.expectEqualStrings("One Piece", results.items[0].title);
    try std.testing.expectEqualStrings("Pirates!", results.items[0].description);
}

test "parseSearchResults handles empty data array" {
    const allocator = std.testing.allocator;
    const crawler = Crawler.init(allocator);

    const json =
        \\{"result":"ok","data":[]}
    ;

    var results = try crawler.parseSearchResults(json);
    defer results.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), results.items.len);
}

test "parseSearchResults handles missing data key" {
    const allocator = std.testing.allocator;
    const crawler = Crawler.init(allocator);

    var results = try crawler.parseSearchResults("{}");
    defer results.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), results.items.len);
}

test "parseChapterFeed extracts chapters" {
    const allocator = std.testing.allocator;
    const crawler = Crawler.init(allocator);

    const json =
        \\{"result":"ok","data":[{"id":"ch-1","type":"chapter","attributes":{"chapter":"1","title":"Romance Dawn","translatedLanguage":"en"}}]}
    ;

    var results = try crawler.parseChapterFeed(json, 42);
    defer {
        for (results.items) |*c| c.deinit(allocator);
        results.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), results.items.len);
    try std.testing.expectEqualStrings("ch-1", results.items[0].source_id);
    try std.testing.expectEqual(@as(f64, 1.0), results.items[0].number);
    try std.testing.expectEqual(@as(u64, 42), results.items[0].manga_id);
}

test "parsePageList extracts page URLs" {
    const allocator = std.testing.allocator;
    const crawler = Crawler.init(allocator);

    const json =
        \\{"baseUrl":"https://uploads.mangadex.org","chapter":{"hash":"abc123","data":["page1.png","page2.png"],"dataSaver":["s1.jpg"]}}
    ;

    var results = try crawler.parsePageList(json, 7);
    defer {
        for (results.items) |*p| p.deinit(allocator);
        results.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), results.items.len);
    try std.testing.expect(std.mem.indexOf(u8, results.items[0].image_url, "page1.png") != null);
    try std.testing.expect(std.mem.indexOf(u8, results.items[0].image_url, "abc123") != null);
    try std.testing.expectEqual(@as(u32, 1), results.items[0].number);
    try std.testing.expectEqual(@as(u32, 2), results.items[1].number);
    try std.testing.expectEqual(@as(u64, 7), results.items[0].chapter_id);
}

test "parseSearchResults with multiple manga" {
    const allocator = std.testing.allocator;
    const crawler = Crawler.init(allocator);

    const json =
        \\{"data":[{"id":"id1","type":"manga","attributes":{"title":{"en":"Manga A"},"description":{"en":"Desc A"}}},{"id":"id2","type":"manga","attributes":{"title":{"en":"Manga B"},"description":{"en":"Desc B"}}}]}
    ;

    var results = try crawler.parseSearchResults(json);
    defer {
        for (results.items) |*m| m.deinit(allocator);
        results.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 2), results.items.len);
    try std.testing.expectEqualStrings("id1", results.items[0].source_id);
    try std.testing.expectEqualStrings("id2", results.items[1].source_id);
}

test "JsonScanner findKey basic" {
    var s = JsonScanner.init("{\"key\": \"value\"}");
    try std.testing.expect(s.findKey("\"key\""));
    const val = s.extractNextString();
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("value", val.?);
}

test "JsonScanner findMatchingBrace" {
    var s = JsonScanner.init("{\"a\":{\"b\":1},\"c\":2}");
    const end = s.findMatchingBrace();
    try std.testing.expect(end != null);
    try std.testing.expectEqual(@as(usize, 19), end.?);
}

test "JsonScanner handles escaped quotes in strings" {
    var s = JsonScanner.init("{\"key\": \"value with \\\"quotes\\\"\"}");
    try std.testing.expect(s.findKey("\"key\""));
    const val = s.extractNextString();
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("value with \\\"quotes\\\"", val.?);
}

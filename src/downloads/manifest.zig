const std = @import("std");
const manga = @import("../domain/manga.zig");

pub const ManifestChapter = struct {
    number: []const u8,
    page_count: u32,
    status: manga.DownloadStatus,
};

pub const Manifest = struct {
    manga_slug: []const u8,
    manga_title: []const u8,
    chapters: []ManifestChapter,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Manifest) void {
        self.allocator.free(self.manga_slug);
        self.allocator.free(self.manga_title);
        for (self.chapters) |ch| {
            self.allocator.free(ch.number);
        }
        self.allocator.free(self.chapters);
    }

    /// Save manifest as a simple JSON file at the given path.
    pub fn save(self: *const Manifest, path: []const u8) !void {
        var json_buf: std.ArrayListUnmanaged(u8) = .empty;
        defer json_buf.deinit(self.allocator);

        try json_buf.appendSlice(self.allocator, "{\"manga_slug\":\"");
        try appendJsonString(self.allocator, &json_buf, self.manga_slug);
        try json_buf.appendSlice(self.allocator, "\",\"manga_title\":\"");
        try appendJsonString(self.allocator, &json_buf, self.manga_title);
        try json_buf.appendSlice(self.allocator, "\",\"chapters\":[");

        for (self.chapters, 0..) |ch, i| {
            if (i > 0) try json_buf.append(self.allocator, ',');
            const chunk = try std.fmt.allocPrint(self.allocator, "{{\"number\":\"{s}\",\"page_count\":{d},\"status\":\"{s}\"}}", .{
                ch.number,
                ch.page_count,
                @tagName(ch.status),
            });
            defer self.allocator.free(chunk);
            try json_buf.appendSlice(self.allocator, chunk);
        }
        try json_buf.appendSlice(self.allocator, "]}");

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(json_buf.items);
    }

    /// Load manifest from a JSON file at the given path.
    pub fn load(allocator: std.mem.Allocator, path: []const u8) !Manifest {
        const file = std.fs.cwd().openFile(path, .{}) catch return error.FileNotFound;
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1 * 1024 * 1024);
        defer allocator.free(content);

        return parseManifest(allocator, content);
    }
};

fn appendJsonString(allocator: std.mem.Allocator, buf: *std.ArrayListUnmanaged(u8), s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try buf.appendSlice(allocator, "\\\""),
            '\\' => try buf.appendSlice(allocator, "\\\\"),
            '\n' => try buf.appendSlice(allocator, "\\n"),
            '\r' => try buf.appendSlice(allocator, "\\r"),
            '\t' => try buf.appendSlice(allocator, "\\t"),
            else => try buf.append(allocator, c),
        }
    }
}

/// Simple JSON parser for manifest files (not a full JSON parser).
fn parseManifest(allocator: std.mem.Allocator, json: []const u8) !Manifest {
    const slug = extractJsonField(json, "manga_slug") orelse "";
    const title = extractJsonField(json, "manga_title") orelse "";

    const slug_copy = try allocator.dupe(u8, slug);
    errdefer allocator.free(slug_copy);
    const title_copy = try allocator.dupe(u8, title);
    errdefer allocator.free(title_copy);

    var chapters: std.ArrayListUnmanaged(ManifestChapter) = .empty;
    errdefer {
        for (chapters.items) |ch| allocator.free(ch.number);
        chapters.deinit(allocator);
    }

    // Parse chapters array
    if (std.mem.indexOf(u8, json, "\"chapters\":[")) |arr_start| {
        var pos = arr_start + 12;
        while (pos < json.len) {
            const obj_start = std.mem.indexOfPos(u8, json, pos, "{") orelse break;
            const obj_end = std.mem.indexOfPos(u8, json, obj_start, "}") orelse break;
            const obj = json[obj_start + 1 .. obj_end];
            pos = obj_end + 1;

            const num = extractJsonField(obj, "number") orelse continue;
            const pc_str = extractJsonField(obj, "page_count") orelse "0";
            const status_str = extractJsonField(obj, "status") orelse "pending";

            const num_copy = try allocator.dupe(u8, num);
            errdefer allocator.free(num_copy);
            const page_count = std.fmt.parseInt(u32, pc_str, 10) catch 0;
            const status = parseStatus(status_str);

            try chapters.append(allocator, ManifestChapter{
                .number = num_copy,
                .page_count = page_count,
                .status = status,
            });
        }
    }

    return Manifest{
        .manga_slug = slug_copy,
        .manga_title = title_copy,
        .chapters = try chapters.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

/// Simple JSON value extractor - handles both quoted strings and unquoted values.
fn extractJsonField(json: []const u8, field: []const u8) ?[]const u8 {
    var key_buf: [128]u8 = undefined;
    // Try quoted value: "field":"value"
    const key_quoted = std.fmt.bufPrint(&key_buf, "\"{s}\":\"", .{field}) catch return null;
    if (std.mem.indexOf(u8, json, key_quoted)) |idx| {
        const start = idx + key_quoted.len;
        const end = std.mem.indexOfScalarPos(u8, json, start, '"') orelse return null;
        return json[start..end];
    }
    // Try unquoted value: "field":value (for numbers/booleans)
    var key_buf2: [128]u8 = undefined;
    const key_unquoted = std.fmt.bufPrint(&key_buf2, "\"{s}\":", .{field}) catch return null;
    if (std.mem.indexOf(u8, json, key_unquoted)) |idx| {
        var start = idx + key_unquoted.len;
        // Skip whitespace
        while (start < json.len and (json[start] == ' ' or json[start] == '\t')) start += 1;
        if (start >= json.len or json[start] == '"') return null; // quoted, handled above
        // Read until delimiter
        var end = start;
        while (end < json.len and json[end] != ',' and json[end] != '}' and json[end] != ']' and
            json[end] != ' ' and json[end] != '\n') end += 1;
        if (end > start) return json[start..end];
    }
    return null;
}

fn parseStatus(s: []const u8) manga.DownloadStatus {
    if (std.mem.eql(u8, s, "pending")) return .pending;
    if (std.mem.eql(u8, s, "in_progress")) return .in_progress;
    if (std.mem.eql(u8, s, "completed")) return .completed;
    if (std.mem.eql(u8, s, "failed")) return .failed;
    if (std.mem.eql(u8, s, "cancelled")) return .cancelled;
    return .pending;
}

// ── Tests ──────────────────────────────────────────────────────────────

test "Manifest save and load" {
    const allocator = std.testing.allocator;
    const path = "test_manifest.json";
    defer std.fs.cwd().deleteFile(path) catch {};

    var chapters = [_]ManifestChapter{
        .{ .number = "1", .page_count = 20, .status = .completed },
        .{ .number = "2", .page_count = 18, .status = .pending },
    };

    var m = Manifest{
        .manga_slug = "naruto",
        .manga_title = "Naruto",
        .chapters = &chapters,
        .allocator = allocator,
    };
    try m.save(path);

    var loaded = try Manifest.load(allocator, path);
    defer loaded.deinit();

    try std.testing.expectEqualStrings("naruto", loaded.manga_slug);
    try std.testing.expectEqualStrings("Naruto", loaded.manga_title);
    try std.testing.expectEqual(@as(usize, 2), loaded.chapters.len);
    try std.testing.expectEqualStrings("1", loaded.chapters[0].number);
    try std.testing.expectEqual(@as(u32, 20), loaded.chapters[0].page_count);
    try std.testing.expectEqual(manga.DownloadStatus.completed, loaded.chapters[0].status);
}

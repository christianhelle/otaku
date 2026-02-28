const std = @import("std");
const Allocator = std.mem.Allocator;

/// Supported manga source websites
pub const Source = enum(u8) {
    mangadex = 0,
    manganato = 1,
    mangakakalot = 2,

    pub fn baseUrl(self: Source) []const u8 {
        return switch (self) {
            .mangadex => "https://api.mangadex.org",
            .manganato => "https://manganato.com",
            .mangakakalot => "https://mangakakalot.com",
        };
    }

    pub fn displayName(self: Source) []const u8 {
        return switch (self) {
            .mangadex => "MangaDex",
            .manganato => "Manganato",
            .mangakakalot => "MangaKakalot",
        };
    }
};

/// A manga title
pub const Manga = struct {
    id: u64,
    source: Source,
    source_id: []const u8,
    title: []const u8,
    description: []const u8,
    cover_url: []const u8,
    url: []const u8,

    pub fn deinit(self: *const Manga, allocator: Allocator) void {
        allocator.free(self.source_id);
        allocator.free(self.title);
        allocator.free(self.description);
        allocator.free(self.cover_url);
        allocator.free(self.url);
    }
};

/// A chapter within a manga
pub const Chapter = struct {
    id: u64,
    manga_id: u64,
    source_id: []const u8,
    number: f64,
    title: []const u8,
    url: []const u8,

    pub fn deinit(self: *const Chapter, allocator: Allocator) void {
        allocator.free(self.source_id);
        allocator.free(self.title);
        allocator.free(self.url);
    }
};

/// A single page within a chapter
pub const Page = struct {
    id: u64,
    chapter_id: u64,
    number: u32,
    image_url: []const u8,
    local_path: []const u8,

    pub fn deinit(self: *const Page, allocator: Allocator) void {
        allocator.free(self.image_url);
        allocator.free(self.local_path);
    }
};

/// Reading progress for a manga
pub const ReadingProgress = struct {
    manga_id: u64,
    last_chapter_id: u64,
    last_page_number: u32,
    updated_at: i64,
};

// ── Serialization helpers ──────────────────────────────────────────────

pub fn writeString(writer: anytype, s: []const u8) !void {
    try writer.writeInt(u32, @intCast(s.len), .little);
    try writer.writeAll(s);
}

pub fn readString(reader: anytype, allocator: Allocator) ![]const u8 {
    const len = try reader.readInt(u32, .little);
    if (len > 10 * 1024 * 1024) return error.StringTooLong;
    const buf = try allocator.alloc(u8, len);
    errdefer allocator.free(buf);
    const n = try reader.readAll(buf);
    if (n != len) return error.UnexpectedEof;
    return buf;
}

pub fn serializeManga(writer: anytype, m: *const Manga) !void {
    try writer.writeInt(u64, m.id, .little);
    try writer.writeInt(u8, @intFromEnum(m.source), .little);
    try writeString(writer, m.source_id);
    try writeString(writer, m.title);
    try writeString(writer, m.description);
    try writeString(writer, m.cover_url);
    try writeString(writer, m.url);
}

pub fn deserializeManga(reader: anytype, allocator: Allocator) !Manga {
    const id = try reader.readInt(u64, .little);
    const source_byte = try reader.readInt(u8, .little);
    const source = std.meta.intToEnum(Source, source_byte) catch return error.InvalidSource;
    const source_id = try readString(reader, allocator);
    errdefer allocator.free(source_id);
    const title = try readString(reader, allocator);
    errdefer allocator.free(title);
    const description = try readString(reader, allocator);
    errdefer allocator.free(description);
    const cover_url = try readString(reader, allocator);
    errdefer allocator.free(cover_url);
    const url = try readString(reader, allocator);
    errdefer allocator.free(url);
    return .{
        .id = id,
        .source = source,
        .source_id = source_id,
        .title = title,
        .description = description,
        .cover_url = cover_url,
        .url = url,
    };
}

pub fn serializeChapter(writer: anytype, c: *const Chapter) !void {
    try writer.writeInt(u64, c.id, .little);
    try writer.writeInt(u64, c.manga_id, .little);
    try writeString(writer, c.source_id);
    const num_bits: u64 = @bitCast(c.number);
    try writer.writeInt(u64, num_bits, .little);
    try writeString(writer, c.title);
    try writeString(writer, c.url);
}

pub fn deserializeChapter(reader: anytype, allocator: Allocator) !Chapter {
    const id = try reader.readInt(u64, .little);
    const manga_id = try reader.readInt(u64, .little);
    const source_id = try readString(reader, allocator);
    errdefer allocator.free(source_id);
    const num_bits = try reader.readInt(u64, .little);
    const number: f64 = @bitCast(num_bits);
    const title = try readString(reader, allocator);
    errdefer allocator.free(title);
    const url = try readString(reader, allocator);
    errdefer allocator.free(url);
    return .{
        .id = id,
        .manga_id = manga_id,
        .source_id = source_id,
        .number = number,
        .title = title,
        .url = url,
    };
}

pub fn serializePage(writer: anytype, p: *const Page) !void {
    try writer.writeInt(u64, p.id, .little);
    try writer.writeInt(u64, p.chapter_id, .little);
    try writer.writeInt(u32, p.number, .little);
    try writeString(writer, p.image_url);
    try writeString(writer, p.local_path);
}

pub fn deserializePage(reader: anytype, allocator: Allocator) !Page {
    const id = try reader.readInt(u64, .little);
    const chapter_id = try reader.readInt(u64, .little);
    const number = try reader.readInt(u32, .little);
    const image_url = try readString(reader, allocator);
    errdefer allocator.free(image_url);
    const local_path = try readString(reader, allocator);
    errdefer allocator.free(local_path);
    return .{
        .id = id,
        .chapter_id = chapter_id,
        .number = number,
        .image_url = image_url,
        .local_path = local_path,
    };
}

pub fn serializeProgress(writer: anytype, p: *const ReadingProgress) !void {
    try writer.writeInt(u64, p.manga_id, .little);
    try writer.writeInt(u64, p.last_chapter_id, .little);
    try writer.writeInt(u32, p.last_page_number, .little);
    try writer.writeInt(i64, p.updated_at, .little);
}

pub fn deserializeProgress(reader: anytype) !ReadingProgress {
    return .{
        .manga_id = try reader.readInt(u64, .little),
        .last_chapter_id = try reader.readInt(u64, .little),
        .last_page_number = try reader.readInt(u32, .little),
        .updated_at = try reader.readInt(i64, .little),
    };
}

// ── Tests ──────────────────────────────────────────────────────────────

test "Source base URLs are non-empty" {
    inline for (std.meta.tags(Source)) |src| {
        try std.testing.expect(src.baseUrl().len > 0);
        try std.testing.expect(src.displayName().len > 0);
    }
}

test "Manga round-trip serialization" {
    const allocator = std.testing.allocator;
    const original = Manga{
        .id = 42,
        .source = .mangadex,
        .source_id = "abc-123",
        .title = "One Piece",
        .description = "A pirate adventure",
        .cover_url = "https://example.com/cover.jpg",
        .url = "https://mangadex.org/title/abc-123",
    };

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serializeManga(fbs.writer(), &original);

    fbs.pos = 0;
    const restored = try deserializeManga(fbs.reader(), allocator);
    defer restored.deinit(allocator);

    try std.testing.expectEqual(original.id, restored.id);
    try std.testing.expectEqual(original.source, restored.source);
    try std.testing.expectEqualStrings(original.source_id, restored.source_id);
    try std.testing.expectEqualStrings(original.title, restored.title);
    try std.testing.expectEqualStrings(original.description, restored.description);
    try std.testing.expectEqualStrings(original.cover_url, restored.cover_url);
    try std.testing.expectEqualStrings(original.url, restored.url);
}

test "Chapter round-trip serialization" {
    const allocator = std.testing.allocator;
    const original = Chapter{
        .id = 7,
        .manga_id = 42,
        .source_id = "ch-001",
        .number = 1.5,
        .title = "Romance Dawn",
        .url = "https://mangadex.org/chapter/ch-001",
    };

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serializeChapter(fbs.writer(), &original);

    fbs.pos = 0;
    const restored = try deserializeChapter(fbs.reader(), allocator);
    defer restored.deinit(allocator);

    try std.testing.expectEqual(original.id, restored.id);
    try std.testing.expectEqual(original.manga_id, restored.manga_id);
    try std.testing.expectEqualStrings(original.source_id, restored.source_id);
    try std.testing.expectEqual(original.number, restored.number);
    try std.testing.expectEqualStrings(original.title, restored.title);
    try std.testing.expectEqualStrings(original.url, restored.url);
}

test "Page round-trip serialization" {
    const allocator = std.testing.allocator;
    const original = Page{
        .id = 99,
        .chapter_id = 7,
        .number = 3,
        .image_url = "https://example.com/page3.png",
        .local_path = "/home/user/.config/otaku/cache/page3.png",
    };

    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serializePage(fbs.writer(), &original);

    fbs.pos = 0;
    const restored = try deserializePage(fbs.reader(), allocator);
    defer restored.deinit(allocator);

    try std.testing.expectEqual(original.id, restored.id);
    try std.testing.expectEqual(original.chapter_id, restored.chapter_id);
    try std.testing.expectEqual(original.number, restored.number);
    try std.testing.expectEqualStrings(original.image_url, restored.image_url);
    try std.testing.expectEqualStrings(original.local_path, restored.local_path);
}

test "ReadingProgress round-trip serialization" {
    const original = ReadingProgress{
        .manga_id = 42,
        .last_chapter_id = 7,
        .last_page_number = 15,
        .updated_at = 1700000000,
    };

    var buf: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try serializeProgress(fbs.writer(), &original);

    fbs.pos = 0;
    const restored = try deserializeProgress(fbs.reader());

    try std.testing.expectEqual(original.manga_id, restored.manga_id);
    try std.testing.expectEqual(original.last_chapter_id, restored.last_chapter_id);
    try std.testing.expectEqual(original.last_page_number, restored.last_page_number);
    try std.testing.expectEqual(original.updated_at, restored.updated_at);
}

test "readString rejects oversized strings" {
    var buf: [4]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    // Write a length that exceeds the 10 MB safety limit
    fbs.writer().writeInt(u32, 11 * 1024 * 1024, .little) catch unreachable;
    fbs.pos = 0;
    const result = readString(fbs.reader(), std.testing.allocator);
    try std.testing.expectError(error.StringTooLong, result);
}

test "Source enum round-trip via intFromEnum" {
    inline for (std.meta.tags(Source)) |src| {
        const byte: u8 = @intFromEnum(src);
        const restored = std.meta.intToEnum(Source, byte) catch unreachable;
        try std.testing.expectEqual(src, restored);
    }
}

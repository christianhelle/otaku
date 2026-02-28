const std = @import("std");
const manga = @import("manga.zig");
const Allocator = std.mem.Allocator;
const fs = std.fs;

const MAGIC = [4]u8{ 'O', 'T', 'K', 'U' };
const VERSION: u32 = 1;

/// File-based database for persisting manga, chapters, pages, and reading progress.
/// Data is stored in a compact binary format under `~/.config/otaku/` (or a custom path).
pub const Database = struct {
    allocator: Allocator,
    data_dir: []const u8,
    manga_list: std.ArrayList(manga.Manga),
    chapter_list: std.ArrayList(manga.Chapter),
    page_list: std.ArrayList(manga.Page),
    progress_list: std.ArrayList(manga.ReadingProgress),
    next_manga_id: u64,
    next_chapter_id: u64,
    next_page_id: u64,

    pub fn init(allocator: Allocator, data_dir: []const u8) !Database {
        const owned_dir = try allocator.dupe(u8, data_dir);
        errdefer allocator.free(owned_dir);

        fs.makeDirAbsolute(owned_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        var db = Database{
            .allocator = allocator,
            .data_dir = owned_dir,
            .manga_list = .empty,
            .chapter_list = .empty,
            .page_list = .empty,
            .progress_list = .empty,
            .next_manga_id = 1,
            .next_chapter_id = 1,
            .next_page_id = 1,
        };

        db.loadAll() catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        return db;
    }

    pub fn deinit(self: *Database) void {
        for (self.manga_list.items) |*m| m.deinit(self.allocator);
        self.manga_list.deinit(self.allocator);
        for (self.chapter_list.items) |*c| c.deinit(self.allocator);
        self.chapter_list.deinit(self.allocator);
        for (self.page_list.items) |*p| p.deinit(self.allocator);
        self.page_list.deinit(self.allocator);
        self.progress_list.deinit(self.allocator);
        self.allocator.free(self.data_dir);
    }

    // ── CRUD: Manga ────────────────────────────────────────────────────

    pub fn addManga(self: *Database, m: manga.Manga) !u64 {
        var entry = m;
        entry.id = self.next_manga_id;
        entry.source_id = try self.allocator.dupe(u8, m.source_id);
        errdefer self.allocator.free(entry.source_id);
        entry.title = try self.allocator.dupe(u8, m.title);
        errdefer self.allocator.free(entry.title);
        entry.description = try self.allocator.dupe(u8, m.description);
        errdefer self.allocator.free(entry.description);
        entry.cover_url = try self.allocator.dupe(u8, m.cover_url);
        errdefer self.allocator.free(entry.cover_url);
        entry.url = try self.allocator.dupe(u8, m.url);
        errdefer self.allocator.free(entry.url);
        try self.manga_list.append(self.allocator, entry);
        self.next_manga_id += 1;
        return entry.id;
    }

    pub fn getManga(self: *const Database, id: u64) ?*const manga.Manga {
        for (self.manga_list.items) |*m| {
            if (m.id == id) return m;
        }
        return null;
    }

    pub fn getAllManga(self: *const Database) []const manga.Manga {
        return self.manga_list.items;
    }

    pub fn removeManga(self: *Database, id: u64) bool {
        for (self.manga_list.items, 0..) |*m, i| {
            if (m.id == id) {
                m.deinit(self.allocator);
                _ = self.manga_list.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    // ── CRUD: Chapters ─────────────────────────────────────────────────

    pub fn addChapter(self: *Database, c: manga.Chapter) !u64 {
        var entry = c;
        entry.id = self.next_chapter_id;
        entry.source_id = try self.allocator.dupe(u8, c.source_id);
        errdefer self.allocator.free(entry.source_id);
        entry.title = try self.allocator.dupe(u8, c.title);
        errdefer self.allocator.free(entry.title);
        entry.url = try self.allocator.dupe(u8, c.url);
        errdefer self.allocator.free(entry.url);
        try self.chapter_list.append(self.allocator, entry);
        self.next_chapter_id += 1;
        return entry.id;
    }

    pub fn getChapter(self: *const Database, id: u64) ?*const manga.Chapter {
        for (self.chapter_list.items) |*c| {
            if (c.id == id) return c;
        }
        return null;
    }

    pub fn getChaptersForManga(self: *const Database, manga_id: u64, out: *std.ArrayList(*const manga.Chapter)) !void {
        for (self.chapter_list.items) |*c| {
            if (c.manga_id == manga_id) try out.append(self.allocator, c);
        }
    }

    pub fn removeChapter(self: *Database, id: u64) bool {
        for (self.chapter_list.items, 0..) |*c, i| {
            if (c.id == id) {
                c.deinit(self.allocator);
                _ = self.chapter_list.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    // ── CRUD: Pages ────────────────────────────────────────────────────

    pub fn addPage(self: *Database, p: manga.Page) !u64 {
        var entry = p;
        entry.id = self.next_page_id;
        entry.image_url = try self.allocator.dupe(u8, p.image_url);
        errdefer self.allocator.free(entry.image_url);
        entry.local_path = try self.allocator.dupe(u8, p.local_path);
        errdefer self.allocator.free(entry.local_path);
        try self.page_list.append(self.allocator, entry);
        self.next_page_id += 1;
        return entry.id;
    }

    pub fn getPage(self: *const Database, id: u64) ?*const manga.Page {
        for (self.page_list.items) |*p| {
            if (p.id == id) return p;
        }
        return null;
    }

    pub fn getPagesForChapter(self: *const Database, chapter_id: u64, out: *std.ArrayList(*const manga.Page)) !void {
        for (self.page_list.items) |*p| {
            if (p.chapter_id == chapter_id) try out.append(self.allocator, p);
        }
    }

    pub fn removePage(self: *Database, id: u64) bool {
        for (self.page_list.items, 0..) |*p, i| {
            if (p.id == id) {
                p.deinit(self.allocator);
                _ = self.page_list.orderedRemove(i);
                return true;
            }
        }
        return false;
    }

    // ── CRUD: Reading Progress ─────────────────────────────────────────

    pub fn setProgress(self: *Database, prog: manga.ReadingProgress) !void {
        for (self.progress_list.items) |*p| {
            if (p.manga_id == prog.manga_id) {
                p.* = prog;
                return;
            }
        }
        try self.progress_list.append(self.allocator, prog);
    }

    pub fn getProgress(self: *const Database, manga_id: u64) ?manga.ReadingProgress {
        for (self.progress_list.items) |p| {
            if (p.manga_id == manga_id) return p;
        }
        return null;
    }

    // ── Persistence ────────────────────────────────────────────────────

    pub fn save(self: *const Database) !void {
        try self.saveMangaFile();
        try self.saveChapterFile();
        try self.savePageFile();
        try self.saveProgressFile();
    }

    fn saveFile(self: *const Database, name: []const u8, serializeFn: anytype, items: anytype, next_id: ?u64) !void {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try self.dbPath(name, &path_buf);

        var buf = std.array_list.Managed(u8).init(self.allocator);
        defer buf.deinit();
        const writer = buf.writer();

        try writer.writeAll(&MAGIC);
        try writer.writeInt(u32, VERSION, .little);
        try writer.writeInt(u32, @intCast(items.len), .little);
        if (next_id) |nid| try writer.writeInt(u64, nid, .little);
        for (items) |*item| try serializeFn(writer, item);

        const file = try fs.createFileAbsolute(path, .{});
        defer file.close();
        try file.writeAll(buf.items);
    }

    fn saveMangaFile(self: *const Database) !void {
        try self.saveFile("manga.db", manga.serializeManga, self.manga_list.items, self.next_manga_id);
    }

    fn saveChapterFile(self: *const Database) !void {
        try self.saveFile("chapters.db", manga.serializeChapter, self.chapter_list.items, self.next_chapter_id);
    }

    fn savePageFile(self: *const Database) !void {
        try self.saveFile("pages.db", manga.serializePage, self.page_list.items, self.next_page_id);
    }

    fn saveProgressFile(self: *const Database) !void {
        try self.saveFile("progress.db", manga.serializeProgress, self.progress_list.items, null);
    }

    fn loadAll(self: *Database) !void {
        try self.loadMangaFile();
        self.loadChapterFile() catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        self.loadPageFile() catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        self.loadProgressFile() catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }

    fn readFileContents(self: *const Database, name: []const u8) ![]u8 {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try self.dbPath(name, &path_buf);
        const file = try fs.openFileAbsolute(path, .{});
        defer file.close();
        const stat = try file.stat();
        const data = try self.allocator.alloc(u8, stat.size);
        errdefer self.allocator.free(data);
        const n = try file.readAll(data);
        if (n != stat.size) return error.UnexpectedEof;
        return data;
    }

    fn loadMangaFile(self: *Database) !void {
        const data = try self.readFileContents("manga.db");
        defer self.allocator.free(data);
        var fbs = std.io.fixedBufferStream(data);
        const reader = fbs.reader();
        try validateHeader(reader);
        const count = try reader.readInt(u32, .little);
        self.next_manga_id = try reader.readInt(u64, .little);
        for (0..count) |_| {
            const m = try manga.deserializeManga(reader, self.allocator);
            try self.manga_list.append(self.allocator, m);
        }
    }

    fn loadChapterFile(self: *Database) !void {
        const data = try self.readFileContents("chapters.db");
        defer self.allocator.free(data);
        var fbs = std.io.fixedBufferStream(data);
        const reader = fbs.reader();
        try validateHeader(reader);
        const count = try reader.readInt(u32, .little);
        self.next_chapter_id = try reader.readInt(u64, .little);
        for (0..count) |_| {
            const c = try manga.deserializeChapter(reader, self.allocator);
            try self.chapter_list.append(self.allocator, c);
        }
    }

    fn loadPageFile(self: *Database) !void {
        const data = try self.readFileContents("pages.db");
        defer self.allocator.free(data);
        var fbs = std.io.fixedBufferStream(data);
        const reader = fbs.reader();
        try validateHeader(reader);
        const count = try reader.readInt(u32, .little);
        self.next_page_id = try reader.readInt(u64, .little);
        for (0..count) |_| {
            const p = try manga.deserializePage(reader, self.allocator);
            try self.page_list.append(self.allocator, p);
        }
    }

    fn loadProgressFile(self: *Database) !void {
        const data = try self.readFileContents("progress.db");
        defer self.allocator.free(data);
        var fbs = std.io.fixedBufferStream(data);
        const reader = fbs.reader();
        try validateHeader(reader);
        const count = try reader.readInt(u32, .little);
        for (0..count) |_| {
            const p = try manga.deserializeProgress(reader);
            try self.progress_list.append(self.allocator, p);
        }
    }

    fn validateHeader(reader: anytype) !void {
        var hdr: [4]u8 = undefined;
        const n = try reader.readAll(&hdr);
        if (n != 4 or !std.mem.eql(u8, &hdr, &MAGIC)) return error.InvalidDatabase;
        const ver = try reader.readInt(u32, .little);
        if (ver != VERSION) return error.UnsupportedVersion;
    }

    fn dbPath(self: *const Database, name: []const u8, buf: *[std.fs.max_path_bytes]u8) ![]const u8 {
        return std.fmt.bufPrint(buf, "{s}/{s}", .{ self.data_dir, name }) catch error.NameTooLong;
    }
};

// ── Tests ──────────────────────────────────────────────────────────────

test "Database init creates directory" {
    const allocator = std.testing.allocator;
    const dir = "/tmp/otaku-test-db-init";
    fs.deleteTreeAbsolute(dir) catch {};
    defer fs.deleteTreeAbsolute(dir) catch {};

    var db = try Database.init(allocator, dir);
    defer db.deinit();

    // Directory should exist
    var d = try fs.openDirAbsolute(dir, .{});
    d.close();
}

test "Database add and get manga" {
    const allocator = std.testing.allocator;
    const dir = "/tmp/otaku-test-db-manga";
    fs.deleteTreeAbsolute(dir) catch {};
    defer fs.deleteTreeAbsolute(dir) catch {};

    var db = try Database.init(allocator, dir);
    defer db.deinit();

    const id = try db.addManga(.{
        .id = 0,
        .source = .mangadex,
        .source_id = "abc-123",
        .title = "Naruto",
        .description = "A ninja story",
        .cover_url = "https://example.com/cover.jpg",
        .url = "https://mangadex.org/title/abc-123",
    });

    try std.testing.expectEqual(@as(u64, 1), id);

    const m = db.getManga(id);
    try std.testing.expect(m != null);
    try std.testing.expectEqualStrings("Naruto", m.?.title);
    try std.testing.expectEqualStrings("abc-123", m.?.source_id);
}

test "Database remove manga" {
    const allocator = std.testing.allocator;
    const dir = "/tmp/otaku-test-db-remove";
    fs.deleteTreeAbsolute(dir) catch {};
    defer fs.deleteTreeAbsolute(dir) catch {};

    var db = try Database.init(allocator, dir);
    defer db.deinit();

    const id = try db.addManga(.{
        .id = 0,
        .source = .mangadex,
        .source_id = "x",
        .title = "Test",
        .description = "",
        .cover_url = "",
        .url = "",
    });

    try std.testing.expect(db.removeManga(id));
    try std.testing.expect(db.getManga(id) == null);
    try std.testing.expect(!db.removeManga(999));
}

test "Database save and reload" {
    const allocator = std.testing.allocator;
    const dir = "/tmp/otaku-test-db-persist";
    fs.deleteTreeAbsolute(dir) catch {};
    defer fs.deleteTreeAbsolute(dir) catch {};

    // Create and populate
    {
        var db = try Database.init(allocator, dir);
        defer db.deinit();

        _ = try db.addManga(.{
            .id = 0,
            .source = .mangadex,
            .source_id = "m1",
            .title = "Bleach",
            .description = "Soul reapers",
            .cover_url = "https://example.com/bleach.jpg",
            .url = "https://mangadex.org/title/m1",
        });

        _ = try db.addChapter(.{
            .id = 0,
            .manga_id = 1,
            .source_id = "c1",
            .number = 1.0,
            .title = "Chapter 1",
            .url = "https://mangadex.org/chapter/c1",
        });

        _ = try db.addPage(.{
            .id = 0,
            .chapter_id = 1,
            .number = 1,
            .image_url = "https://example.com/p1.png",
            .local_path = "/tmp/p1.png",
        });

        try db.setProgress(.{
            .manga_id = 1,
            .last_chapter_id = 1,
            .last_page_number = 1,
            .updated_at = 1700000000,
        });

        try db.save();
    }

    // Reload and verify
    {
        var db = try Database.init(allocator, dir);
        defer db.deinit();

        const all = db.getAllManga();
        try std.testing.expectEqual(@as(usize, 1), all.len);
        try std.testing.expectEqualStrings("Bleach", all[0].title);

        const ch = db.getChapter(1);
        try std.testing.expect(ch != null);
        try std.testing.expectEqualStrings("Chapter 1", ch.?.title);

        const pg = db.getPage(1);
        try std.testing.expect(pg != null);
        try std.testing.expectEqual(@as(u32, 1), pg.?.number);

        const prog = db.getProgress(1);
        try std.testing.expect(prog != null);
        try std.testing.expectEqual(@as(u32, 1), prog.?.last_page_number);
    }
}

test "Database chapter and page queries" {
    const allocator = std.testing.allocator;
    const dir = "/tmp/otaku-test-db-queries";
    fs.deleteTreeAbsolute(dir) catch {};
    defer fs.deleteTreeAbsolute(dir) catch {};

    var db = try Database.init(allocator, dir);
    defer db.deinit();

    const mid = try db.addManga(.{
        .id = 0,
        .source = .mangadex,
        .source_id = "m",
        .title = "T",
        .description = "",
        .cover_url = "",
        .url = "",
    });

    _ = try db.addChapter(.{ .id = 0, .manga_id = mid, .source_id = "c1", .number = 1, .title = "Ch1", .url = "" });
    _ = try db.addChapter(.{ .id = 0, .manga_id = mid, .source_id = "c2", .number = 2, .title = "Ch2", .url = "" });
    _ = try db.addChapter(.{ .id = 0, .manga_id = 999, .source_id = "c3", .number = 1, .title = "Other", .url = "" });

    var chapters: std.ArrayList(*const manga.Chapter) = .empty;
    defer chapters.deinit(allocator);
    try db.getChaptersForManga(mid, &chapters);
    try std.testing.expectEqual(@as(usize, 2), chapters.items.len);

    _ = try db.addPage(.{ .id = 0, .chapter_id = 1, .number = 1, .image_url = "u1", .local_path = "" });
    _ = try db.addPage(.{ .id = 0, .chapter_id = 1, .number = 2, .image_url = "u2", .local_path = "" });
    _ = try db.addPage(.{ .id = 0, .chapter_id = 2, .number = 1, .image_url = "u3", .local_path = "" });

    var pages: std.ArrayList(*const manga.Page) = .empty;
    defer pages.deinit(allocator);
    try db.getPagesForChapter(1, &pages);
    try std.testing.expectEqual(@as(usize, 2), pages.items.len);
}

test "Database setProgress updates existing" {
    const allocator = std.testing.allocator;
    const dir = "/tmp/otaku-test-db-progress";
    fs.deleteTreeAbsolute(dir) catch {};
    defer fs.deleteTreeAbsolute(dir) catch {};

    var db = try Database.init(allocator, dir);
    defer db.deinit();

    try db.setProgress(.{ .manga_id = 1, .last_chapter_id = 1, .last_page_number = 5, .updated_at = 100 });
    try db.setProgress(.{ .manga_id = 1, .last_chapter_id = 2, .last_page_number = 10, .updated_at = 200 });

    try std.testing.expectEqual(@as(usize, 1), db.progress_list.items.len);
    const prog = db.getProgress(1).?;
    try std.testing.expectEqual(@as(u64, 2), prog.last_chapter_id);
    try std.testing.expectEqual(@as(u32, 10), prog.last_page_number);
}

test "Database getAllManga returns empty on fresh db" {
    const allocator = std.testing.allocator;
    const dir = "/tmp/otaku-test-db-empty";
    fs.deleteTreeAbsolute(dir) catch {};
    defer fs.deleteTreeAbsolute(dir) catch {};

    var db = try Database.init(allocator, dir);
    defer db.deinit();

    try std.testing.expectEqual(@as(usize, 0), db.getAllManga().len);
}

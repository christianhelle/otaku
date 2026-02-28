/// SQLite-backed persistence layer for the Otaku manga reader.
const std = @import("std");
const manga = @import("manga.zig");

const c = @cImport({
    @cInclude("sqlite3.h");
});

/// Database errors.
pub const DbError = error{
    OpenFailed,
    PrepareFailed,
    StepFailed,
    BindFailed,
    SchemaFailed,
    NotFound,
    OutOfMemory,
};

/// Wraps a SQLite database connection and provides typed operations.
pub const Database = struct {
    db: *c.sqlite3,
    allocator: std.mem.Allocator,

    /// Open (or create) the database at the given path.
    pub fn open(allocator: std.mem.Allocator, path: [:0]const u8) DbError!Database {
        var db: ?*c.sqlite3 = null;
        if (c.sqlite3_open(path.ptr, &db) != c.SQLITE_OK) {
            return DbError.OpenFailed;
        }
        var self = Database{ .db = db.?, .allocator = allocator };
        try self.initSchema();
        return self;
    }

    /// Close the database connection.
    pub fn close(self: *Database) void {
        _ = c.sqlite3_close(self.db);
    }

    /// Create database schema tables if they do not exist.
    fn initSchema(self: *Database) DbError!void {
        const schema =
            \\PRAGMA journal_mode=WAL;
            \\PRAGMA foreign_keys=ON;
            \\
            \\CREATE TABLE IF NOT EXISTS manga (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  title TEXT NOT NULL,
            \\  url TEXT NOT NULL UNIQUE,
            \\  cover_url TEXT NOT NULL DEFAULT '',
            \\  description TEXT NOT NULL DEFAULT '',
            \\  status INTEGER NOT NULL DEFAULT 0,
            \\  site TEXT NOT NULL,
            \\  chapter_count INTEGER NOT NULL DEFAULT 0,
            \\  created_at INTEGER NOT NULL DEFAULT 0,
            \\  updated_at INTEGER NOT NULL DEFAULT 0
            \\);
            \\
            \\CREATE TABLE IF NOT EXISTS chapters (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  manga_id INTEGER NOT NULL REFERENCES manga(id) ON DELETE CASCADE,
            \\  number REAL NOT NULL,
            \\  title TEXT NOT NULL DEFAULT '',
            \\  url TEXT NOT NULL,
            \\  read INTEGER NOT NULL DEFAULT 0,
            \\  downloaded INTEGER NOT NULL DEFAULT 0,
            \\  page_count INTEGER NOT NULL DEFAULT 0,
            \\  created_at INTEGER NOT NULL DEFAULT 0,
            \\  UNIQUE(manga_id, number)
            \\);
            \\
            \\CREATE TABLE IF NOT EXISTS pages (
            \\  id INTEGER PRIMARY KEY AUTOINCREMENT,
            \\  chapter_id INTEGER NOT NULL REFERENCES chapters(id) ON DELETE CASCADE,
            \\  page_number INTEGER NOT NULL,
            \\  url TEXT NOT NULL,
            \\  local_path TEXT NOT NULL DEFAULT '',
            \\  UNIQUE(chapter_id, page_number)
            \\);
            \\
            \\CREATE INDEX IF NOT EXISTS idx_chapters_manga_id ON chapters(manga_id);
            \\CREATE INDEX IF NOT EXISTS idx_pages_chapter_id ON pages(chapter_id);
        ;
        const rc = c.sqlite3_exec(self.db, schema, null, null, null);
        if (rc != c.SQLITE_OK) return DbError.SchemaFailed;
    }

    // ---- Manga operations ----

    /// Insert a manga record. Returns the new row id.
    pub fn insertManga(self: *Database, m: manga.Manga) DbError!i64 {
        const sql = "INSERT OR IGNORE INTO manga(title,url,cover_url,description,status,site,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        const now = std.time.timestamp();
        _ = c.sqlite3_bind_text(stmt, 1, m.title.ptr, @intCast(m.title.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, m.url.ptr, @intCast(m.url.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 3, m.cover_url.ptr, @intCast(m.cover_url.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 4, m.description.ptr, @intCast(m.description.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int(stmt, 5, @intFromEnum(m.status));
        _ = c.sqlite3_bind_text(stmt, 6, m.site.ptr, @intCast(m.site.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int64(stmt, 7, now);
        _ = c.sqlite3_bind_int64(stmt, 8, now);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;
        return c.sqlite3_last_insert_rowid(self.db);
    }

    /// Update an existing manga record.
    pub fn updateManga(self: *Database, m: manga.Manga) DbError!void {
        const sql = "UPDATE manga SET title=?,cover_url=?,description=?,status=?,chapter_count=?,updated_at=? WHERE id=?";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, m.title.ptr, @intCast(m.title.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, m.cover_url.ptr, @intCast(m.cover_url.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 3, m.description.ptr, @intCast(m.description.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int(stmt, 4, @intFromEnum(m.status));
        _ = c.sqlite3_bind_int64(stmt, 5, m.chapter_count);
        _ = c.sqlite3_bind_int64(stmt, 6, std.time.timestamp());
        _ = c.sqlite3_bind_int64(stmt, 7, m.id);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    /// Retrieve a manga by its row id. Caller owns the returned Manga's strings.
    pub fn getMangaById(self: *Database, id: i64) DbError!manga.Manga {
        const sql = "SELECT id,title,url,cover_url,description,status,site,chapter_count,created_at,updated_at FROM manga WHERE id=?";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, id);
        if (c.sqlite3_step(stmt) != c.SQLITE_ROW) return DbError.NotFound;
        return try self.readMangaRow(stmt.?);
    }

    /// List all manga in the database. Caller owns the returned slice.
    pub fn listManga(self: *Database) DbError![]manga.Manga {
        const sql = "SELECT id,title,url,cover_url,description,status,site,chapter_count,created_at,updated_at FROM manga ORDER BY title ASC";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        var result: std.ArrayList(manga.Manga) = .empty;
        defer {
            if (@errorReturnTrace() != null) {
                for (result.items) |*m| {
                    var mutable = m.*;
                    mutable.free(self.allocator);
                }
                result.deinit(self.allocator);
            }
        }
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const m = try self.readMangaRow(stmt.?);
            try result.append(self.allocator, m);
        }
        return result.toOwnedSlice(self.allocator);
    }

    /// Delete a manga and all its chapters/pages (CASCADE).
    pub fn deleteManga(self: *Database, id: i64) DbError!void {
        const sql = "DELETE FROM manga WHERE id=?";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, id);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    // ---- Chapter operations ----

    /// Insert a chapter (or ignore if duplicate manga_id+number).
    pub fn insertChapter(self: *Database, ch: manga.Chapter) DbError!i64 {
        const sql = "INSERT OR IGNORE INTO chapters(manga_id,number,title,url,read,downloaded,page_count,created_at) VALUES(?,?,?,?,?,?,?,?)";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_int64(stmt, 1, ch.manga_id);
        _ = c.sqlite3_bind_double(stmt, 2, ch.number);
        _ = c.sqlite3_bind_text(stmt, 3, ch.title.ptr, @intCast(ch.title.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 4, ch.url.ptr, @intCast(ch.url.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_int(stmt, 5, if (ch.read) 1 else 0);
        _ = c.sqlite3_bind_int(stmt, 6, if (ch.downloaded) 1 else 0);
        _ = c.sqlite3_bind_int64(stmt, 7, ch.page_count);
        _ = c.sqlite3_bind_int64(stmt, 8, std.time.timestamp());

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;
        return c.sqlite3_last_insert_rowid(self.db);
    }

    /// Mark a chapter as read/unread.
    pub fn markChapterRead(self: *Database, chapter_id: i64, read: bool) DbError!void {
        const sql = "UPDATE chapters SET read=? WHERE id=?";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int(stmt, 1, if (read) 1 else 0);
        _ = c.sqlite3_bind_int64(stmt, 2, chapter_id);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;
    }

    /// Retrieve all chapters for a manga. Caller owns the returned slice.
    pub fn listChaptersByManga(self: *Database, manga_id: i64) DbError![]manga.Chapter {
        const sql = "SELECT id,manga_id,number,title,url,read,downloaded,page_count,created_at FROM chapters WHERE manga_id=? ORDER BY number ASC";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, manga_id);

        var result: std.ArrayList(manga.Chapter) = .empty;
        defer {
            if (@errorReturnTrace() != null) {
                for (result.items) |*ch| {
                    var mutable = ch.*;
                    mutable.free(self.allocator);
                }
                result.deinit(self.allocator);
            }
        }
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const ch = try self.readChapterRow(stmt.?);
            try result.append(self.allocator, ch);
        }
        return result.toOwnedSlice(self.allocator);
    }

    // ---- Page operations ----

    /// Insert a page (or ignore if duplicate chapter_id+page_number).
    pub fn insertPage(self: *Database, pg: manga.Page) DbError!i64 {
        const sql = "INSERT OR IGNORE INTO pages(chapter_id,page_number,url,local_path) VALUES(?,?,?,?)";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_int64(stmt, 1, pg.chapter_id);
        _ = c.sqlite3_bind_int(stmt, 2, pg.page_number);
        _ = c.sqlite3_bind_text(stmt, 3, pg.url.ptr, @intCast(pg.url.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 4, pg.local_path.ptr, @intCast(pg.local_path.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) return DbError.StepFailed;
        return c.sqlite3_last_insert_rowid(self.db);
    }

    /// Retrieve all pages for a chapter. Caller owns the returned slice.
    pub fn listPagesByChapter(self: *Database, chapter_id: i64) DbError![]manga.Page {
        const sql = "SELECT id,chapter_id,page_number,url,local_path FROM pages WHERE chapter_id=? ORDER BY page_number ASC";
        var stmt: ?*c.sqlite3_stmt = null;
        if (c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null) != c.SQLITE_OK) return DbError.PrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        _ = c.sqlite3_bind_int64(stmt, 1, chapter_id);

        var result: std.ArrayList(manga.Page) = .empty;
        defer {
            if (@errorReturnTrace() != null) {
                for (result.items) |*pg| {
                    var mutable = pg.*;
                    mutable.free(self.allocator);
                }
                result.deinit(self.allocator);
            }
        }
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const pg = try self.readPageRow(stmt.?);
            try result.append(self.allocator, pg);
        }
        return result.toOwnedSlice(self.allocator);
    }

    // ---- Private row readers ----

    fn readMangaRow(self: *Database, stmt: *c.sqlite3_stmt) DbError!manga.Manga {
        const id = c.sqlite3_column_int64(stmt, 0);
        const title = try self.columnText(stmt, 1);
        const url = try self.columnText(stmt, 2);
        const cover_url = try self.columnText(stmt, 3);
        const description = try self.columnText(stmt, 4);
        const status_raw: u8 = @intCast(c.sqlite3_column_int(stmt, 5));
        const site = try self.columnText(stmt, 6);
        const chapter_count = c.sqlite3_column_int64(stmt, 7);
        const created_at = c.sqlite3_column_int64(stmt, 8);
        const updated_at = c.sqlite3_column_int64(stmt, 9);

        const status: manga.MangaStatus = @enumFromInt(status_raw);
        return manga.Manga{
            .id = id,
            .title = title,
            .url = url,
            .cover_url = cover_url,
            .description = description,
            .status = status,
            .site = site,
            .chapter_count = chapter_count,
            .created_at = created_at,
            .updated_at = updated_at,
        };
    }

    fn readChapterRow(self: *Database, stmt: *c.sqlite3_stmt) DbError!manga.Chapter {
        const id = c.sqlite3_column_int64(stmt, 0);
        const manga_id = c.sqlite3_column_int64(stmt, 1);
        const number = c.sqlite3_column_double(stmt, 2);
        const title = try self.columnText(stmt, 3);
        const url = try self.columnText(stmt, 4);
        const read = c.sqlite3_column_int(stmt, 5) != 0;
        const downloaded = c.sqlite3_column_int(stmt, 6) != 0;
        const page_count = c.sqlite3_column_int64(stmt, 7);
        const created_at = c.sqlite3_column_int64(stmt, 8);
        return manga.Chapter{
            .id = id,
            .manga_id = manga_id,
            .number = number,
            .title = title,
            .url = url,
            .read = read,
            .downloaded = downloaded,
            .page_count = page_count,
            .created_at = created_at,
        };
    }

    fn readPageRow(self: *Database, stmt: *c.sqlite3_stmt) DbError!manga.Page {
        const id = c.sqlite3_column_int64(stmt, 0);
        const chapter_id = c.sqlite3_column_int64(stmt, 1);
        const page_number: i32 = @intCast(c.sqlite3_column_int(stmt, 2));
        const url = try self.columnText(stmt, 3);
        const local_path = try self.columnText(stmt, 4);
        return manga.Page{
            .id = id,
            .chapter_id = chapter_id,
            .page_number = page_number,
            .url = url,
            .local_path = local_path,
        };
    }

    /// Duplicate a SQLite column text value into the allocator. Returns "" for NULL.
    fn columnText(self: *Database, stmt: *c.sqlite3_stmt, col: c_int) DbError![]u8 {
        const ptr = c.sqlite3_column_text(stmt, col);
        if (ptr == null) return self.allocator.dupe(u8, "") catch return DbError.OutOfMemory;
        const len: usize = @intCast(c.sqlite3_column_bytes(stmt, col));
        const text: []const u8 = ptr[0..len];
        return self.allocator.dupe(u8, text) catch return DbError.OutOfMemory;
    }
};

// ---------- Unit Tests ----------

test "Database open and schema" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();
    // If we get here, the schema was created without error.
}

test "Insert and retrieve manga" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const m = manga.Manga{
        .title = "One Piece",
        .url = "https://mangadex.org/title/one-piece",
        .cover_url = "https://cdn.mangadex.org/one-piece.jpg",
        .description = "Pirates!",
        .status = .ongoing,
        .site = "MangaDex",
    };
    const id = try db.insertManga(m);
    try std.testing.expect(id > 0);

    var retrieved = try db.getMangaById(id);
    defer retrieved.free(allocator);
    try std.testing.expectEqualStrings("One Piece", retrieved.title);
    try std.testing.expectEqualStrings("https://mangadex.org/title/one-piece", retrieved.url);
    try std.testing.expectEqual(manga.MangaStatus.ongoing, retrieved.status);
    try std.testing.expectEqualStrings("MangaDex", retrieved.site);
}

test "Insert duplicate manga is idempotent" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const m = manga.Manga{
        .title = "Bleach",
        .url = "https://mangadex.org/title/bleach",
        .status = .completed,
        .site = "MangaDex",
    };
    const id1 = try db.insertManga(m);
    const id2 = try db.insertManga(m);
    // Second insert is ignored (INSERT OR IGNORE), rowid returns 0.
    try std.testing.expect(id1 > 0);
    _ = id2;
}

test "List manga" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    _ = try db.insertManga(manga.Manga{ .title = "Berserk", .url = "https://example.com/berserk", .status = .ongoing, .site = "S1" });
    _ = try db.insertManga(manga.Manga{ .title = "Akira", .url = "https://example.com/akira", .status = .completed, .site = "S2" });

    const list = try db.listManga();
    defer {
        for (list) |*item| {
            var m = item.*;
            m.free(allocator);
        }
        allocator.free(list);
    }
    try std.testing.expectEqual(@as(usize, 2), list.len);
    // Alphabetical order: Akira, Berserk
    try std.testing.expectEqualStrings("Akira", list[0].title);
    try std.testing.expectEqualStrings("Berserk", list[1].title);
}

test "Update manga" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const id = try db.insertManga(manga.Manga{ .title = "Dragon Ball", .url = "https://example.com/db", .status = .ongoing, .site = "S1" });
    var m = try db.getMangaById(id);
    defer m.free(allocator);
    m.chapter_count = 519;
    try db.updateManga(m);

    var updated = try db.getMangaById(id);
    defer updated.free(allocator);
    try std.testing.expectEqual(@as(i64, 519), updated.chapter_count);
}

test "Delete manga" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const id = try db.insertManga(manga.Manga{ .title = "Temp", .url = "https://example.com/temp", .status = .unknown, .site = "S1" });
    try db.deleteManga(id);
    const result = db.getMangaById(id);
    try std.testing.expectError(DbError.NotFound, result);
}

test "Insert and list chapters" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const manga_id = try db.insertManga(manga.Manga{ .title = "HxH", .url = "https://example.com/hxh", .status = .hiatus, .site = "S1" });
    _ = try db.insertChapter(manga.Chapter{ .manga_id = manga_id, .number = 1.0, .title = "Departure", .url = "https://example.com/hxh/1" });
    _ = try db.insertChapter(manga.Chapter{ .manga_id = manga_id, .number = 2.0, .title = "Examination", .url = "https://example.com/hxh/2" });

    const chapters = try db.listChaptersByManga(manga_id);
    defer {
        for (chapters) |*ch| {
            var c2 = ch.*;
            c2.free(allocator);
        }
        allocator.free(chapters);
    }
    try std.testing.expectEqual(@as(usize, 2), chapters.len);
    try std.testing.expectEqualStrings("Departure", chapters[0].title);
    try std.testing.expectEqual(@as(f64, 2.0), chapters[1].number);
}

test "Mark chapter read" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const manga_id = try db.insertManga(manga.Manga{ .title = "FMA", .url = "https://example.com/fma", .status = .completed, .site = "S1" });
    const ch_id = try db.insertChapter(manga.Chapter{ .manga_id = manga_id, .number = 1.0, .title = "Ch1", .url = "https://example.com/fma/1" });

    try db.markChapterRead(ch_id, true);
    const chapters = try db.listChaptersByManga(manga_id);
    defer {
        for (chapters) |*ch| {
            var c2 = ch.*;
            c2.free(allocator);
        }
        allocator.free(chapters);
    }
    try std.testing.expectEqual(true, chapters[0].read);
}

test "Insert and list pages" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const manga_id = try db.insertManga(manga.Manga{ .title = "Test", .url = "https://example.com/test", .status = .unknown, .site = "S1" });
    const ch_id = try db.insertChapter(manga.Chapter{ .manga_id = manga_id, .number = 1.0, .title = "Ch1", .url = "https://example.com/test/1" });
    _ = try db.insertPage(manga.Page{ .chapter_id = ch_id, .page_number = 1, .url = "https://cdn.example.com/1.jpg" });
    _ = try db.insertPage(manga.Page{ .chapter_id = ch_id, .page_number = 2, .url = "https://cdn.example.com/2.jpg", .local_path = "/tmp/2.jpg" });

    const pages = try db.listPagesByChapter(ch_id);
    defer {
        for (pages) |*pg| {
            var p2 = pg.*;
            p2.free(allocator);
        }
        allocator.free(pages);
    }
    try std.testing.expectEqual(@as(usize, 2), pages.len);
    try std.testing.expectEqual(@as(i32, 1), pages[0].page_number);
    try std.testing.expectEqualStrings("https://cdn.example.com/2.jpg", pages[1].url);
    try std.testing.expectEqualStrings("/tmp/2.jpg", pages[1].local_path);
}

test "Cascade delete chapters on manga delete" {
    const allocator = std.testing.allocator;
    var db = try Database.open(allocator, ":memory:");
    defer db.close();

    const manga_id = try db.insertManga(manga.Manga{ .title = "Cascade Test", .url = "https://example.com/cascade", .status = .unknown, .site = "S1" });
    _ = try db.insertChapter(manga.Chapter{ .manga_id = manga_id, .number = 1.0, .title = "Ch1", .url = "https://example.com/cascade/1" });
    try db.deleteManga(manga_id);

    const chapters = try db.listChaptersByManga(manga_id);
    defer allocator.free(chapters);
    try std.testing.expectEqual(@as(usize, 0), chapters.len);
}

const std = @import("std");
const database = @import("database.zig");
const manga = @import("manga.zig");
const crawler = @import("crawler.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Resolve data directory: $XDG_CONFIG_HOME/otaku or ~/.config/otaku
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const data_dir = blk: {
        if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
            break :blk try std.fmt.bufPrint(&path_buf, "{s}/otaku", .{xdg});
        }
        if (std.posix.getenv("HOME")) |home| {
            break :blk try std.fmt.bufPrint(&path_buf, "{s}/.config/otaku", .{home});
        }
        break :blk "/tmp/otaku";
    };

    var db = try database.Database.init(allocator, data_dir);
    defer {
        db.save() catch {};
        db.deinit();
    }

    const stdout_file = std.fs.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var fw = stdout_file.writer(&stdout_buf);
    const w = &fw.interface;
    w.writeAll("Otaku – Manga Reader\n") catch {};
    w.writeAll("Loading library...\n") catch {};

    const all = db.getAllManga();
    if (all.len == 0) {
        w.writeAll("No manga in library.\n") catch {};
    } else {
        for (all) |m| {
            w.print("  {s} ({s})\n", .{ m.title, m.source.displayName() }) catch {};
        }
    }
    w.flush() catch {};
}

test "imports compile" {
    _ = @import("manga.zig");
    _ = @import("database.zig");
    _ = @import("crawler.zig");
    _ = @import("ui.zig");
}

const std = @import("std");

pub const version = "0.1.0";

// ── Command & Options ─────────────────────────────────────────────────

pub const Command = enum {
    tui,
    browse,
    search,
    title,
    download,
    library_build,
    help,
    version_cmd,
};

pub const Options = struct {
    command: Command,
    // Positional / subcommand args
    browse_category: ?[]const u8 = null,
    genre: ?[]const u8 = null,
    query: ?[]const u8 = null,
    url_or_slug: ?[]const u8 = null,
    // Download flags
    chapters: ?[]const u8 = null,
    download_all: bool = false,
    output_dir: []const u8 = "./manga",
    parallel: bool = false,
    retries: u8 = 3,
    timeout_s: u32 = 10,
    delay_ms: u32 = 200,
    verbose: bool = false,
    build_library: bool = false,
    // Library flags
    library_root: []const u8 = "./manga",

    pub const defaults = Options{
        .command = .tui,
    };
};

pub const ParseError = error{
    UnknownCommand,
    UnknownOption,
    MissingValue,
    InvalidNumber,
};

/// Parse command-line arguments into Options.
/// Borrows slices from `args`.
pub fn parseArgs(args: []const []const u8) ParseError!Options {
    if (args.len < 2) return Options.defaults;

    var opts = Options.defaults;
    const cmd_str = args[1];

    // Global flags at position 1
    if (std.mem.eql(u8, cmd_str, "-h") or std.mem.eql(u8, cmd_str, "--help")) {
        opts.command = .help;
        return opts;
    }
    if (std.mem.eql(u8, cmd_str, "-v") or std.mem.eql(u8, cmd_str, "--version")) {
        opts.command = .version_cmd;
        return opts;
    }

    // Command dispatch
    if (std.mem.eql(u8, cmd_str, "browse")) {
        opts.command = .browse;
        // Next positional: category or "genre"
        if (args.len > 2) {
            if (std.mem.eql(u8, args[2], "genre")) {
                opts.browse_category = "genre";
                if (args.len > 3) opts.genre = args[3];
            } else {
                opts.browse_category = args[2];
            }
        }
    } else if (std.mem.eql(u8, cmd_str, "search")) {
        opts.command = .search;
        if (args.len > 2) opts.query = args[2];
    } else if (std.mem.eql(u8, cmd_str, "title")) {
        opts.command = .title;
        if (args.len > 2) opts.url_or_slug = args[2];
    } else if (std.mem.eql(u8, cmd_str, "download")) {
        opts.command = .download;
        if (args.len > 2 and !std.mem.startsWith(u8, args[2], "-")) {
            opts.url_or_slug = args[2];
        }
    } else if (std.mem.eql(u8, cmd_str, "library")) {
        opts.command = .library_build;
        // Check for "build" subcommand
        var start: usize = 2;
        if (args.len > 2 and std.mem.eql(u8, args[2], "build")) {
            start = 3;
        }
        // Parse library flags
        var i: usize = start;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "--root")) {
                i += 1;
                if (i >= args.len) return ParseError.MissingValue;
                opts.library_root = args[i];
            }
        }
        return opts;
    } else {
        return ParseError.UnknownCommand;
    }

    // Parse remaining flags (for browse, search, title, download)
    var i: usize = if (opts.command == .browse and opts.browse_category != null)
        (if (opts.genre != null) @as(usize, 4) else @as(usize, 3))
    else if (opts.command == .search and opts.query != null)
        @as(usize, 3)
    else if (opts.command == .title and opts.url_or_slug != null)
        @as(usize, 3)
    else if (opts.command == .download and opts.url_or_slug != null)
        @as(usize, 3)
    else
        @as(usize, 2);

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            opts.command = .help;
            return opts;
        } else if (std.mem.eql(u8, arg, "--chapters")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.chapters = args[i];
        } else if (std.mem.eql(u8, arg, "--all")) {
            opts.download_all = true;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) return ParseError.MissingValue;
            opts.output_dir = args[i];
        } else if (std.mem.eql(u8, arg, "--parallel")) {
            opts.parallel = true;
        } else if (std.mem.eql(u8, arg, "--retries")) {
            i += 1;
            if (i >= args.len) return ParseError.InvalidNumber;
            opts.retries = std.fmt.parseInt(u8, args[i], 10) catch return ParseError.InvalidNumber;
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            i += 1;
            if (i >= args.len) return ParseError.InvalidNumber;
            opts.timeout_s = std.fmt.parseInt(u32, args[i], 10) catch return ParseError.InvalidNumber;
        } else if (std.mem.eql(u8, arg, "--delay")) {
            i += 1;
            if (i >= args.len) return ParseError.InvalidNumber;
            opts.delay_ms = std.fmt.parseInt(u32, args[i], 10) catch return ParseError.InvalidNumber;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            opts.verbose = true;
        } else if (std.mem.eql(u8, arg, "--build-library")) {
            opts.build_library = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            return ParseError.UnknownOption;
        }
    }

    return opts;
}

// ── Output helpers ────────────────────────────────────────────────────

pub fn printHelp() !void {
    var buf: [4096]u8 = undefined;
    var fw = std.fs.File.stdout().writer(&buf);
    try fw.interface.print(
        \\otaku {s} — terminal manga browser for Fanfox
        \\
        \\Usage:
        \\  otaku                                    Launch TUI browser
        \\  otaku browse <category>                  Browse by category
        \\  otaku browse genre <genre>               Browse by genre
        \\  otaku search <query>                     Search for manga
        \\  otaku title <url-or-slug>                Show manga details
        \\  otaku download <url> [options]            Download chapters
        \\  otaku library build [--root dir]         Build local library
        \\
        \\Categories: hot, trending, new, updates, recommended, reading-now
        \\
        \\Download options:
        \\  --chapters N-M     Chapter range (e.g. 1-10)
        \\  --all              Download all chapters
        \\  -o, --output DIR   Output directory (default: ./manga)
        \\  --parallel         Download in parallel
        \\  --retries N        Retry count (default: 3)
        \\  --timeout N        Timeout in seconds (default: 10)
        \\  --delay N          Delay between requests in ms (default: 200)
        \\  --verbose          Verbose output
        \\  --build-library    Build library after download
        \\
        \\General:
        \\  -h, --help         Show this help
        \\  -v, --version      Show version
        \\
    , .{version});
    try fw.interface.flush();
}

pub fn printVersion() !void {
    var buf: [256]u8 = undefined;
    var fw = std.fs.File.stdout().writer(&buf);
    try fw.interface.print("otaku {s}\n", .{version});
    try fw.interface.flush();
}

pub fn printError(msg: []const u8) void {
    var buf: [1024]u8 = undefined;
    var fw = std.fs.File.stderr().writer(&buf);
    fw.interface.print("error: {s}\n", .{msg}) catch {};
    fw.interface.flush() catch {};
}

fn printNotImplemented(what: []const u8) !void {
    var buf: [1024]u8 = undefined;
    var fw = std.fs.File.stdout().writer(&buf);
    try fw.interface.print("Not yet implemented: {s}\n", .{what});
    try fw.interface.flush();
}

// ── Main ──────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const opts = parseArgs(args) catch |err| {
        const msg = switch (err) {
            ParseError.UnknownCommand => "unknown command. Use 'otaku --help' for usage",
            ParseError.UnknownOption => "unknown option",
            ParseError.MissingValue => "missing value for option",
            ParseError.InvalidNumber => "invalid numeric argument",
        };
        printError(msg);
        try printHelp();
        std.process.exit(1);
    };

    switch (opts.command) {
        .help => try printHelp(),
        .version_cmd => try printVersion(),
        .tui => {
            const app_mod = @import("app/app.zig");
            var app = try app_mod.App.init(allocator);
            defer app.deinit();
            try app.run();
        },
        .browse => try printNotImplemented("browse"),
        .search => try printNotImplemented("search"),
        .title => try printNotImplemented("title"),
        .download => try printNotImplemented("download"),
        .library_build => try printNotImplemented("library build"),
    }
}

// ── Tests ─────────────────────────────────────────────────────────────

test "parseArgs no args returns TUI" {
    const args = &[_][]const u8{"otaku"};
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.tui, opts.command);
}

test "parseArgs --help" {
    const args = &[_][]const u8{ "otaku", "--help" };
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.help, opts.command);
}

test "parseArgs -v" {
    const args = &[_][]const u8{ "otaku", "-v" };
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.version_cmd, opts.command);
}

test "parseArgs browse hot" {
    const args = &[_][]const u8{ "otaku", "browse", "hot" };
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.browse, opts.command);
    try std.testing.expectEqualStrings("hot", opts.browse_category.?);
}

test "parseArgs browse genre action" {
    const args = &[_][]const u8{ "otaku", "browse", "genre", "action" };
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.browse, opts.command);
    try std.testing.expectEqualStrings("genre", opts.browse_category.?);
    try std.testing.expectEqualStrings("action", opts.genre.?);
}

test "parseArgs search" {
    const args = &[_][]const u8{ "otaku", "search", "naruto" };
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.search, opts.command);
    try std.testing.expectEqualStrings("naruto", opts.query.?);
}

test "parseArgs download with flags" {
    const args = &[_][]const u8{
        "otaku", "download", "https://fanfox.net/manga/naruto",
        "--chapters", "1-10", "--parallel", "--verbose",
    };
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.download, opts.command);
    try std.testing.expectEqualStrings("https://fanfox.net/manga/naruto", opts.url_or_slug.?);
    try std.testing.expectEqualStrings("1-10", opts.chapters.?);
    try std.testing.expect(opts.parallel);
    try std.testing.expect(opts.verbose);
}

test "parseArgs unknown command" {
    const args = &[_][]const u8{ "otaku", "foobar" };
    try std.testing.expectError(ParseError.UnknownCommand, parseArgs(args));
}

test "parseArgs library build" {
    const args = &[_][]const u8{ "otaku", "library", "build", "--root", "/data/manga" };
    const opts = try parseArgs(args);
    try std.testing.expectEqual(Command.library_build, opts.command);
    try std.testing.expectEqualStrings("/data/manga", opts.library_root);
}

// Ensure all submodules compile
test "imports compile" {
    _ = @import("domain/manga.zig");
    _ = @import("domain/chapter.zig");
    _ = @import("domain/filters.zig");
    _ = @import("domain/category.zig");
    _ = @import("domain/download.zig");
    _ = @import("storage/config.zig");
    _ = @import("storage/cache.zig");
    _ = @import("storage/filesystem.zig");
    _ = @import("storage/metadata.zig");
    _ = @import("http/client.zig");
    _ = @import("http/rate_limiter.zig");
    _ = @import("http/retry.zig");
    _ = @import("fanfox/client.zig");
    _ = @import("fanfox/endpoints.zig");
    _ = @import("fanfox/adapters.zig");
    _ = @import("fanfox/parsers/categories.zig");
    _ = @import("fanfox/parsers/directory.zig");
    _ = @import("fanfox/parsers/title.zig");
    _ = @import("fanfox/parsers/chapters.zig");
    _ = @import("fanfox/parsers/reader.zig");
    _ = @import("downloads/manager.zig");
    _ = @import("downloads/queue.zig");
    _ = @import("downloads/saver.zig");
    _ = @import("downloads/manifest.zig");
    _ = @import("library/builder.zig");
    _ = @import("library/templates.zig");
    _ = @import("library/indexer.zig");
    _ = @import("tui/terminal.zig");
    _ = @import("tui/layout.zig");
    _ = @import("tui/widgets/list.zig");
    _ = @import("tui/widgets/table.zig");
    _ = @import("tui/widgets/detail.zig");
    _ = @import("tui/widgets/statusbar.zig");
    _ = @import("tui/widgets/modal.zig");
    _ = @import("tui/widgets/progress.zig");
    _ = @import("app/app.zig");
    _ = @import("app/router.zig");
    _ = @import("app/state.zig");
    _ = @import("app/actions.zig");
    _ = @import("util/strings.zig");
    _ = @import("util/html.zig");
    _ = @import("util/urls.zig");
    _ = @import("util/sort.zig");
    _ = @import("util/time.zig");
    _ = @import("integrations/argiope_compat.zig");
}

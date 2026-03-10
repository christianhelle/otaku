const std = @import("std");

// otaku library root — kept minimal; all logic lives in submodules.
pub const domain = @import("domain/manga.zig");
pub const chapter = @import("domain/chapter.zig");
pub const filters = @import("domain/filters.zig");
pub const config = @import("storage/config.zig");

test "root imports" {
    _ = domain;
    _ = chapter;
    _ = filters;
    _ = config;
}

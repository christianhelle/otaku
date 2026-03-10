const std = @import("std");

pub const LinkType = enum { anchor, image };

pub const Link = struct {
    href: []const u8,
    link_type: LinkType,
};

/// Extract all links and image sources from an HTML document.
/// The returned slices borrow from the input `html`. Caller frees the slice.
pub fn extractLinks(allocator: std.mem.Allocator, html: []const u8) ![]Link {
    var links: std.ArrayListUnmanaged(Link) = .empty;
    errdefer links.deinit(allocator);

    var pos: usize = 0;
    while (pos < html.len) {
        const tag_start = std.mem.indexOfPos(u8, html, pos, "<") orelse break;
        pos = tag_start + 1;
        if (pos >= html.len) break;

        // Skip comments
        if (pos + 2 < html.len and html[pos] == '!' and html[pos + 1] == '-' and html[pos + 2] == '-') {
            const comment_end = std.mem.indexOfPos(u8, html, pos, "-->") orelse break;
            pos = comment_end + 3;
            continue;
        }

        // Read tag name
        const tag_name_start = pos;
        while (pos < html.len and html[pos] != ' ' and html[pos] != '\t' and
            html[pos] != '\n' and html[pos] != '\r' and
            html[pos] != '>' and html[pos] != '/')
        {
            pos += 1;
        }
        const tag_name = html[tag_name_start..pos];

        const attr_name: ?[]const u8 = blk: {
            if (asciiEqlIgnoreCase(tag_name, "a") or
                asciiEqlIgnoreCase(tag_name, "link") or
                asciiEqlIgnoreCase(tag_name, "area") or
                asciiEqlIgnoreCase(tag_name, "base"))
            {
                break :blk "href";
            }
            if (asciiEqlIgnoreCase(tag_name, "img") or
                asciiEqlIgnoreCase(tag_name, "script") or
                asciiEqlIgnoreCase(tag_name, "source") or
                asciiEqlIgnoreCase(tag_name, "iframe") or
                asciiEqlIgnoreCase(tag_name, "embed") or
                asciiEqlIgnoreCase(tag_name, "video") or
                asciiEqlIgnoreCase(tag_name, "audio"))
            {
                break :blk "src";
            }
            break :blk null;
        };

        if (attr_name == null) continue;

        const link_type: LinkType = if (asciiEqlIgnoreCase(tag_name, "img") or
            asciiEqlIgnoreCase(tag_name, "source") or
            asciiEqlIgnoreCase(tag_name, "video") or
            asciiEqlIgnoreCase(tag_name, "audio"))
            .image
        else
            .anchor;

        const tag_end = std.mem.indexOfPos(u8, html, pos, ">") orelse break;
        const tag_content = html[pos..tag_end];

        if (findAttributeInTag(tag_content, attr_name.?)) |href| {
            if (href.len > 0 and
                !std.mem.startsWith(u8, href, "javascript:") and
                !std.mem.startsWith(u8, href, "mailto:") and
                !std.mem.startsWith(u8, href, "tel:") and
                !std.mem.startsWith(u8, href, "data:") and
                !std.mem.startsWith(u8, href, "#"))
            {
                try links.append(allocator, Link{ .href = href, .link_type = link_type });
            }
        }

        pos = tag_end + 1;
    }

    return links.toOwnedSlice(allocator);
}

/// Find value of `attr` on tag `tag` within `html`. Returns borrowed slice.
pub fn findAttrValue(html: []const u8, tag: []const u8, attr: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (pos < html.len) {
        const tag_start = std.mem.indexOfPos(u8, html, pos, "<") orelse break;
        pos = tag_start + 1;
        if (pos >= html.len) break;

        // Read tag name
        const name_start = pos;
        while (pos < html.len and html[pos] != ' ' and html[pos] != '\t' and
            html[pos] != '\n' and html[pos] != '\r' and
            html[pos] != '>' and html[pos] != '/')
        {
            pos += 1;
        }
        const name = html[name_start..pos];
        if (!asciiEqlIgnoreCase(name, tag)) continue;

        const tag_end = std.mem.indexOfPos(u8, html, pos, ">") orelse break;
        const tag_content = html[pos..tag_end];
        if (findAttributeInTag(tag_content, attr)) |val| return val;
        pos = tag_end + 1;
    }
    return null;
}

/// Strip HTML tags and return text content. Caller owns the returned slice.
pub fn extractText(allocator: std.mem.Allocator, html_fragment: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    var pos: usize = 0;
    var in_tag = false;
    while (pos < html_fragment.len) {
        const c = html_fragment[pos];
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
            // Add space between tags
            if (result.items.len > 0 and result.items[result.items.len - 1] != ' ') {
                try result.append(allocator, ' ');
            }
        } else if (!in_tag) {
            try result.append(allocator, c);
        }
        pos += 1;
    }

    // Trim trailing whitespace
    var end = result.items.len;
    while (end > 0 and isWhitespace(result.items[end - 1])) end -= 1;
    result.items.len = end;

    return result.toOwnedSlice(allocator);
}

pub fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn findAttributeInTag(tag_content: []const u8, attr_name: []const u8) ?[]const u8 {
    var pos: usize = 0;
    while (pos < tag_content.len) {
        while (pos < tag_content.len and isWhitespace(tag_content[pos])) pos += 1;
        if (pos >= tag_content.len) break;

        const name_start = pos;
        while (pos < tag_content.len and tag_content[pos] != '=' and
            !isWhitespace(tag_content[pos]) and tag_content[pos] != '>')
        {
            pos += 1;
        }
        const name = tag_content[name_start..pos];

        while (pos < tag_content.len and isWhitespace(tag_content[pos])) pos += 1;
        if (pos >= tag_content.len or tag_content[pos] != '=') continue;
        pos += 1;
        while (pos < tag_content.len and isWhitespace(tag_content[pos])) pos += 1;
        if (pos >= tag_content.len) break;

        const value = blk: {
            if (tag_content[pos] == '"') {
                pos += 1;
                const val_start = pos;
                while (pos < tag_content.len and tag_content[pos] != '"') pos += 1;
                const val = tag_content[val_start..pos];
                if (pos < tag_content.len) pos += 1;
                break :blk val;
            } else if (tag_content[pos] == '\'') {
                pos += 1;
                const val_start = pos;
                while (pos < tag_content.len and tag_content[pos] != '\'') pos += 1;
                const val = tag_content[val_start..pos];
                if (pos < tag_content.len) pos += 1;
                break :blk val;
            } else {
                const val_start = pos;
                while (pos < tag_content.len and !isWhitespace(tag_content[pos]) and
                    tag_content[pos] != '>')
                {
                    pos += 1;
                }
                break :blk tag_content[val_start..pos];
            }
        };

        if (asciiEqlIgnoreCase(name, attr_name)) return value;
    }
    return null;
}

fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

// ── Tests ──────────────────────────────────────────────────────────────

test "extractLinks anchor" {
    const html = "<a href=\"https://example.com\">Link</a>";
    const links = try extractLinks(std.testing.allocator, html);
    defer std.testing.allocator.free(links);
    try std.testing.expectEqual(@as(usize, 1), links.len);
    try std.testing.expectEqualStrings("https://example.com", links[0].href);
}

test "extractText strips tags" {
    const html = "<h1>Title</h1><p>Text here</p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "Title") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Text here") != null);
}

test "findAttrValue finds img src" {
    const html = "<img class=\"cover\" src=\"/images/cover.jpg\">";
    const val = findAttrValue(html, "img", "src");
    try std.testing.expect(val != null);
    try std.testing.expectEqualStrings("/images/cover.jpg", val.?);
}

test "asciiEqlIgnoreCase" {
    try std.testing.expect(asciiEqlIgnoreCase("Hello", "hello"));
    try std.testing.expect(!asciiEqlIgnoreCase("Hello", "world"));
}

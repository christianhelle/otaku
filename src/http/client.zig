const std = @import("std");

pub const HttpError = error{
    ConnectionFailed,
    TooManyRedirects,
    InvalidResponse,
    Timeout,
};

pub const Response = struct {
    status: u16,
    body: []u8,
    allocator: std.mem.Allocator,
    content_type: ?[]u8,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
        if (self.content_type) |ct| self.allocator.free(ct);
    }

    pub fn isSuccess(self: Response) bool {
        return self.status >= 200 and self.status < 300;
    }

    pub fn isRedirect(self: Response) bool {
        return self.status >= 300 and self.status < 400;
    }

    pub fn isClientError(self: Response) bool {
        return self.status >= 400 and self.status < 500;
    }

    pub fn isServerError(self: Response) bool {
        return self.status >= 500;
    }
};

pub const FetchOptions = struct {
    max_redirects: u8 = 5,
    timeout_ms: u32 = 10_000,
    max_body_size: usize = 10 * 1024 * 1024, // 10 MB
    extra_headers: []const std.http.Header = &.{},
    user_agent: ?[]const u8 = null,
};

/// Fetch a URL via GET, following redirects. Returns response with body.
/// Caller owns the returned Response and must call deinit().
pub fn fetch(client: *std.http.Client, allocator: std.mem.Allocator, url_str: []const u8, options: FetchOptions) !Response {
    var redirect_count: u8 = 0;
    var location_buf: [4096]u8 = undefined;
    var current_url: []const u8 = url_str;

    while (true) {
        const uri = std.Uri.parse(current_url) catch return error.ConnectionFailed;

        var req = client.request(.GET, uri, .{
            .redirect_behavior = .unhandled,
            .headers = .{
                .accept_encoding = .{ .override = "identity" },
                .user_agent = if (options.user_agent) |ua| .{ .override = ua } else .default,
            },
            .extra_headers = options.extra_headers,
        }) catch return error.ConnectionFailed;
        defer req.deinit();

        req.sendBodiless() catch return error.ConnectionFailed;

        var redirect_buf: [16 * 1024]u8 = undefined;
        var response = req.receiveHead(&redirect_buf) catch return error.ConnectionFailed;

        const status: u16 = @intFromEnum(response.head.status);

        if (status >= 300 and status < 400) {
            redirect_count += 1;
            if (redirect_count > options.max_redirects) return error.TooManyRedirects;

            const location = response.head.location orelse return error.ConnectionFailed;

            const new_url: []const u8 = blk: {
                if (std.mem.startsWith(u8, location, "http://") or
                    std.mem.startsWith(u8, location, "https://"))
                {
                    break :blk location;
                }
                const scheme = if (uri.port orelse 0 == 443) "https" else uri.scheme;
                const host = switch (uri.host orelse std.Uri.Component{ .raw = "" }) {
                    .raw => |r| r,
                    .percent_encoded => |r| r,
                };
                const port = uri.port;
                var build_buf: [4096]u8 = undefined;
                const built = if (port) |p|
                    std.fmt.bufPrint(&build_buf, "{s}://{s}:{d}{s}", .{ scheme, host, p, location }) catch return error.ConnectionFailed
                else
                    std.fmt.bufPrint(&build_buf, "{s}://{s}{s}", .{ scheme, host, location }) catch return error.ConnectionFailed;
                if (built.len > location_buf.len) return error.ConnectionFailed;
                @memcpy(location_buf[0..built.len], built);
                break :blk location_buf[0..built.len];
            };

            if (new_url.ptr != location_buf[0..].ptr) {
                if (new_url.len > location_buf.len) return error.ConnectionFailed;
                @memcpy(location_buf[0..new_url.len], new_url);
                current_url = location_buf[0..new_url.len];
            } else {
                current_url = new_url;
            }

            var drain_buf: [8192]u8 = undefined;
            _ = response.reader(&drain_buf);

            continue;
        }

        const content_type: ?[]u8 = if (response.head.content_type) |ct|
            allocator.dupe(u8, ct) catch null
        else
            null;
        errdefer if (content_type) |ct| allocator.free(ct);

        var transfer_buf: [8192]u8 = undefined;
        const reader = response.reader(&transfer_buf);
        const body = reader.allocRemaining(allocator, std.io.Limit.limited(options.max_body_size)) catch
            (allocator.dupe(u8, "") catch return error.ConnectionFailed);

        return Response{
            .status = status,
            .body = body,
            .allocator = allocator,
            .content_type = content_type,
        };
    }
}

/// Check if a content-type header indicates HTML content.
pub fn isHtmlContent(content_type: ?[]const u8) bool {
    const ct = content_type orelse return false;
    return std.mem.indexOf(u8, ct, "text/html") != null or
        std.mem.indexOf(u8, ct, "application/xhtml") != null;
}

/// Check if a content-type header indicates an image.
pub fn isImageContent(content_type: ?[]const u8) bool {
    const ct = content_type orelse return false;
    return std.mem.startsWith(u8, ct, "image/");
}

/// Get a human-readable status description.
pub fn statusText(code: u16) []const u8 {
    return switch (code) {
        200 => "OK",
        201 => "Created",
        301 => "Moved Permanently",
        302 => "Found",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        408 => "Request Timeout",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        else => "Unknown",
    };
}

// ── Tests ──────────────────────────────────────────────────────────────

test "Response.isSuccess" {
    var resp = Response{
        .status = 200,
        .body = try std.testing.allocator.dupe(u8, "ok"),
        .allocator = std.testing.allocator,
        .content_type = null,
    };
    defer resp.deinit();
    try std.testing.expect(resp.isSuccess());
    try std.testing.expect(!resp.isRedirect());
}

test "Response.isClientError" {
    var resp = Response{
        .status = 404,
        .body = try std.testing.allocator.dupe(u8, "not found"),
        .allocator = std.testing.allocator,
        .content_type = null,
    };
    defer resp.deinit();
    try std.testing.expect(resp.isClientError());
}

test "isHtmlContent" {
    try std.testing.expect(isHtmlContent("text/html; charset=utf-8"));
    try std.testing.expect(!isHtmlContent("application/json"));
    try std.testing.expect(!isHtmlContent(null));
}

test "isImageContent" {
    try std.testing.expect(isImageContent("image/png"));
    try std.testing.expect(!isImageContent("text/html"));
}

test "statusText" {
    try std.testing.expectEqualStrings("OK", statusText(200));
    try std.testing.expectEqualStrings("Not Found", statusText(404));
    try std.testing.expectEqualStrings("Unknown", statusText(999));
}

const std = @import("std");
const app_mod = @import("app.zig");
const App = app_mod.App;
const router = @import("router.zig");
const Action = router.Action;
const state_mod = @import("state.zig");
const Screen = state_mod.Screen;
const manga = @import("../domain/manga.zig");

pub fn executeAction(app: *App, action: Action) !void {
    switch (action) {
        .none => {},
        .quit => {
            app.running = false;
        },
        .back => {
            app.state.back();
        },
        .navigate_to => |screen| {
            app.state.navigate(screen);
        },
        .load_category => |kind| {
            app.state.loading = true;
            app.state.current_category = kind;
            app.state.category_selected = 0;
            app.state.setStatus("Loading...");
            app.state.navigate(.category_list);

            // Free old titles
            for (app.state.category_titles) |*t| t.deinit(app.allocator);
            app.allocator.free(app.state.category_titles);

            const feed = app.client.fetchCategory(kind) catch |err| {
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Error: {s}", .{@errorName(err)}) catch "Error";
                app.state.setStatus(msg);
                app.state.loading = false;
                app.state.category_titles = &.{};
                return;
            };
            app.state.category_titles = feed.titles;
            app.state.loading = false;
            var buf2: [64]u8 = undefined;
            const msg2 = std.fmt.bufPrint(&buf2, "{d} titles", .{feed.titles.len}) catch "Loaded";
            app.state.setStatus(msg2);
        },
        .load_title => |url| {
            app.state.loading = true;
            app.state.setStatus("Loading title...");
            app.state.navigate(.title_detail);

            if (app.state.current_title) |*t| t.deinit(app.allocator);

            const title = app.client.fetchTitle(url) catch |err| {
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Error: {s}", .{@errorName(err)}) catch "Error";
                app.state.setStatus(msg);
                app.state.loading = false;
                app.state.current_title = null;
                return;
            };
            app.state.current_title = title;
            app.state.loading = false;
            app.state.setStatus(title.title);
        },
        .load_chapters => |slug| {
            app.state.loading = true;
            app.state.setStatus("Loading chapters...");
            app.state.navigate(.chapter_list);

            for (app.state.current_chapters) |*ch| ch.deinit(app.allocator);
            app.allocator.free(app.state.current_chapters);

            const chapters = app.client.fetchChapters(slug) catch |err| {
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Error: {s}", .{@errorName(err)}) catch "Error";
                app.state.setStatus(msg);
                app.state.loading = false;
                app.state.current_chapters = &.{};
                return;
            };
            app.state.current_chapters = chapters;
            app.state.chapter_selected = 0;
            app.state.loading = false;
            var buf2: [64]u8 = undefined;
            const msg2 = std.fmt.bufPrint(&buf2, "{d} chapters", .{chapters.len}) catch "Loaded";
            app.state.setStatus(msg2);
        },
        .download_selected => {
            if (app.state.current_chapters.len > 0 and
                app.state.chapter_selected < app.state.current_chapters.len and
                app.state.current_title != null)
            {
                const ch = app.state.current_chapters[app.state.chapter_selected];
                const title = app.state.current_title.?;
                const slug_copy = app.allocator.dupe(u8, title.slug) catch {
                    app.state.setStatus("Out of memory");
                    return;
                };
                const number_copy = app.allocator.dupe(u8, ch.number) catch {
                    app.allocator.free(slug_copy);
                    app.state.setStatus("Out of memory");
                    return;
                };
                const url_copy = app.allocator.dupe(u8, ch.url) catch {
                    app.allocator.free(slug_copy);
                    app.allocator.free(number_copy);
                    app.state.setStatus("Out of memory");
                    return;
                };
                const output_copy = app.allocator.dupe(u8, "./downloads") catch {
                    app.allocator.free(slug_copy);
                    app.allocator.free(number_copy);
                    app.allocator.free(url_copy);
                    app.state.setStatus("Out of memory");
                    return;
                };
                const job = manga.DownloadJob{
                    .manga_slug = slug_copy,
                    .chapter_number = number_copy,
                    .url = url_copy,
                    .output_dir = output_copy,
                };
                app.state.download_jobs.append(app.allocator, job) catch {
                    app.allocator.free(slug_copy);
                    app.allocator.free(number_copy);
                    app.allocator.free(url_copy);
                    app.allocator.free(output_copy);
                    app.state.setStatus("Failed to queue");
                    return;
                };
                app.state.setStatus("Chapter queued");
            }
        },
        .download_all => {
            if (app.state.current_title == null) {
                app.state.setStatus("No title selected");
                return;
            }
            var queued: usize = 0;
            const title = app.state.current_title.?;
            for (app.state.current_chapters) |ch| {
                const slug_copy = app.allocator.dupe(u8, title.slug) catch continue;
                const number_copy = app.allocator.dupe(u8, ch.number) catch {
                    app.allocator.free(slug_copy);
                    continue;
                };
                const url_copy = app.allocator.dupe(u8, ch.url) catch {
                    app.allocator.free(slug_copy);
                    app.allocator.free(number_copy);
                    continue;
                };
                const output_copy = app.allocator.dupe(u8, "./downloads") catch {
                    app.allocator.free(slug_copy);
                    app.allocator.free(number_copy);
                    app.allocator.free(url_copy);
                    continue;
                };
                const job = manga.DownloadJob{
                    .manga_slug = slug_copy,
                    .chapter_number = number_copy,
                    .url = url_copy,
                    .output_dir = output_copy,
                };
                app.state.download_jobs.append(app.allocator, job) catch {
                    app.allocator.free(slug_copy);
                    app.allocator.free(number_copy);
                    app.allocator.free(url_copy);
                    app.allocator.free(output_copy);
                    continue;
                };
                queued += 1;
            }
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{d} chapters queued", .{queued}) catch "Queued";
            app.state.setStatus(msg);
        },
        .start_search => |query| {
            app.state.setStatus("Searching...");
            app.state.navigate(.search_results);

            for (app.state.search_results) |*t| t.deinit(app.allocator);
            app.allocator.free(app.state.search_results);

            const results = app.client.search(query) catch |err| {
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "Error: {s}", .{@errorName(err)}) catch "Error";
                app.state.setStatus(msg);
                app.state.search_results = &.{};
                return;
            };
            app.state.search_results = results;
            var buf2: [64]u8 = undefined;
            const msg2 = std.fmt.bufPrint(&buf2, "{d} results", .{results.len}) catch "Done";
            app.state.setStatus(msg2);
        },
        .build_library => {
            app.state.setStatus("Building library...");
        },
        .refresh => {
            app.state.loading = true;
            app.state.setStatus("Refreshing...");
        },
    }
}

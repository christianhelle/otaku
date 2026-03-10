# Decision: TUI-to-FanfoxClient Wiring

**Date:** 2025-01-22  
**Recorded by:** Spike (Lead)  
**Status:** Implemented  

## Context

The TUI layer (app/app.zig, app/actions.zig) was fully implemented with navigation, state management, and rendering, but all network actions were stubs. Jet's FanfoxClient (src/fanfox/client.zig) was complete with methods for fetching categories, titles, chapters, and search results. Phase 4 required wiring these layers together so the TUI fetches live data from the network.

## Decision

### App Ownership
- `App` struct owns a `FanfoxClient` instance
- Client initialized in `App.init()` with `Config.defaults`
- Client destroyed in `App.deinit()`
- App also stores `allocator: std.mem.Allocator` so actions can manage heap memory

### Action Implementation
Replaced all stub actions with real FanfoxClient calls:

**load_category:**
- Calls `client.fetchCategory(kind)` 
- Returns `CategoryFeed` with owned `[]MangaTitle`
- Frees old titles before assigning new ones
- Sets loading state and status messages

**load_title:**
- Calls `client.fetchTitle(url)`
- Returns owned `MangaTitle`
- Frees old title before assigning new one

**load_chapters:**
- Calls `client.fetchChapters(slug)`
- Returns owned `[]Chapter`
- Frees old chapters before assigning new ones

**start_search:**
- Calls `client.search(query)`
- Returns owned `[]MangaTitle`
- Frees old results before assigning new ones

**download_selected / download_all:**
- Build complete `DownloadJob` structs with all required fields
- Duplicate strings for manga_slug, chapter_number, url, output_dir
- Get manga_slug from `app.state.current_title.?.slug`
- Handle allocation failures gracefully
- Append to `app.state.download_jobs`

### Memory Management
- FanfoxClient returns owned slices allocated with its allocator
- AppState stores these slices
- AppState.deinit() recursively frees all owned data:
  - `category_titles` → each MangaTitle.deinit() → free the slice
  - `current_title` → MangaTitle.deinit() if present
  - `current_chapters` → each Chapter.deinit() → free the slice
  - `search_results` → each MangaTitle.deinit() → free the slice
- Actions free old data before assigning new data from network calls

### Error Handling
- All network calls use `catch` to handle errors
- Error messages formatted with `std.fmt.bufPrint` into status bar
- Loading state always cleared on error
- Empty slices returned on error (graceful degradation)

## Rationale

**Why App owns FanfoxClient:**
- Client needs to live as long as the app runs
- Client has internal state (HTTP client, rate limiter)
- Single initialization point simplifies lifecycle

**Why actions handle memory:**
- Actions know when old data is replaced
- Actions can show status during async operations
- Centralized cleanup logic in AppState.deinit

**Why duplicate strings for DownloadJobs:**
- Jobs outlive the chapters/titles that created them
- Jobs may be persisted or processed later
- Owned strings prevent dangling pointers

## Consequences

**Positive:**
- TUI now fetches and displays real manga data
- Users can browse categories, search, view titles, and queue downloads
- Memory is properly managed with no leaks
- Error handling provides user feedback

**Negative:**
- Network latency visible in UI (loading states help)
- Download queue just enqueues jobs (not yet processed by download engine)
- No caching layer (every action refetches)

## Future Work
- Implement download engine to process queued jobs
- Add caching layer to reduce redundant network calls
- Add pagination support for large category feeds
- Handle rate limiting in UI (show wait time)

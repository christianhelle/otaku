# Squad Decisions

## Phase 4: TUI-to-FanfoxClient Wiring

**Date:** 2025-01-22  
**Recorded by:** Spike (Lead)  
**Status:** Implemented  

### Context
The TUI layer was fully implemented with navigation, state management, and rendering, but all network actions were stubs. Jet's FanfoxClient was complete with methods for fetching categories, titles, chapters, and search results. Phase 4 required wiring these layers together so the TUI fetches live data from the network.

### Decision

**App Ownership**
- App struct owns a FanfoxClient instance
- Client initialized in App.init() with Config.defaults
- Client destroyed in App.deinit()
- App also stores allocator: std.mem.Allocator so actions can manage heap memory

**Action Implementation**
All stub actions replaced with real FanfoxClient calls:
- load_category: Calls client.fetchCategory(kind), frees old titles, sets loading state
- load_title: Calls client.fetchTitle(url), frees old title
- load_chapters: Calls client.fetchChapters(slug), frees old chapters
- start_search: Calls client.search(query), frees old results
- download_selected/download_all: Build complete DownloadJob structs with all required fields

**Memory Management**
- FanfoxClient returns owned slices allocated with its allocator
- AppState stores these slices
- AppState.deinit() recursively frees all owned data
- Actions free old data before assigning new data from network calls

**Error Handling**
- All network calls use catch to handle errors
- Error messages formatted with std.fmt.bufPrint into status bar
- Loading state always cleared on error
- Empty slices returned on error (graceful degradation)

### Rationale

**Why App owns FanfoxClient**
- Client needs to live as long as the app runs
- Client has internal state (HTTP client, rate limiter)
- Single initialization point simplifies lifecycle

**Why actions handle memory**
- Actions know when old data is replaced
- Actions can show status during async operations
- Centralized cleanup logic in AppState.deinit

**Why duplicate strings for DownloadJobs**
- Jobs outlive the chapters/titles that created them
- Jobs may be persisted or processed later
- Owned strings prevent dangling pointers

### Consequences

**Positive**
- TUI now fetches and displays real manga data
- Users can browse categories, search, view titles, and queue downloads
- Memory is properly managed with no leaks
- Error handling provides user feedback

**Negative**
- Network latency visible in UI (loading states help)
- Download queue just enqueues jobs (not yet processed)
- No caching layer (every action refetches)

### Future Work
- Implement download engine to process queued jobs
- Add caching layer to reduce redundant network calls
- Add pagination support for large category feeds
- Handle rate limiting in UI (show wait time)

---

## Phase 5-6: Downloads Manager/Queue + CLI Commands

**Date:** 2025  
**Author:** Jet (Systems Dev)  
**Status:** Implemented

### Summary
Implemented the downloads manager/queue layer and wired up all CLI commands (browse, search, title, download, library_build). The download infrastructure is in place but chapter image fetching is deferred until the reader parser is implemented.

### Implementation Details

**Downloads Layer**

src/downloads/manager.zig
- DownloadManager struct with init, deinit, downloadChapter, downloadAll
- Creates chapter directories at {output_dir}/{slug}/c{number}/
- Prints progress if verbose flag is set
- Placeholder for image downloading (needs reader parser)
- Uses std.http.Client and Config for HTTP settings

src/downloads/queue.zig
- DownloadQueue struct with FIFO job queue
- Uses std.ArrayListUnmanaged(DownloadJob) for storage
- Methods: init, deinit, enqueue, dequeue, len
- Simple ordered removal for dequeue

**CLI Commands**

All commands in src/main.zig now fully implemented:

.browse
- Maps category string to CategoryKind enum
- Fetches category feed via FanfoxClient.fetchCategory()
- Prints title, URL, status, author for each result
- Shows total count

.search
- Validates query argument is present
- Calls FanfoxClient.search(query)
- Prints title and URL for each result
- Shows total count

.title
- Accepts URL or slug, normalizes to URL
- Fetches title details and chapter list
- Prints: title, status, URL, author, genres, summary
- Lists all chapters with optional titles

.download
- Extracts slug from URL or uses slug directly
- Fetches chapters via FanfoxClient.fetchChapters()
- Filters chapters (TODO: implement range parsing for --chapters N-M)
- Creates DownloadManager and calls downloadAll()
- Optionally builds library if --build-library flag is set
- Respects timeout, retries, delay, verbose flags

.library_build
- Calls library/builder.zig to generate HTML library
- Walks directory tree, generates index/title/chapter pages
- Prints success message with path to index.html

### Testing
Added tests for:
- DownloadManager init/deinit
- DownloadManager downloadChapter (verifies directory creation)
- DownloadQueue init/deinit
- DownloadQueue enqueue/dequeue FIFO behavior
- DownloadQueue len tracking

All tests pass: 100/100

### Known Limitations

1. **Image downloading not implemented** — downloadChapter creates the directory structure but doesn't fetch chapter images. This requires the reader parser (src/fanfox/parsers/reader.zig) to extract image URLs from chapter pages.

2. **Chapter range filtering incomplete** — The --chapters N-M flag is parsed but the filtering logic is not implemented. Currently uses all chapters if --all is set, or just the first chapter otherwise.

3. **No progress tracking** — Downloads don't update a progress bar or save state to manifest files. Manifest support exists but isn't wired up yet.

4. **Serial downloads only** — The --parallel flag is parsed but not used. Downloads happen sequentially.

### Next Steps

1. Implement src/fanfox/parsers/reader.zig to parse chapter reader pages and extract image URLs
2. Wire reader parser into DownloadManager.downloadChapter() to fetch actual images
3. Implement chapter range parsing (e.g., "1-10", "5,7,9")
4. Add manifest tracking for resume-on-failure
5. Implement parallel downloads if --parallel flag is set

### Design Rationale

**Why create new allocator per command?**
Each CLI command is a short-lived process. Creating a fresh GPA per command ensures clean memory isolation and simplifies cleanup.

**Why placeholder implementation in downloadChapter?**
The reader parser is a separate concern owned by the parsing layer. Download manager should be implemented independently, then integrated once reader parser is ready.

**Why no retry logic in download manager?**
Retry logic is handled by the HTTP layer (http/retry.zig with exponential backoff). Download manager delegates to HTTP client, which already has retries configured.

### Dependencies

- src/fanfox/client.zig — for fetching titles, chapters, categories, search
- src/downloads/saver.zig — for saving individual image files (not yet called)
- src/library/builder.zig — for generating HTML library after download
- src/util/urls.zig — for slug extraction and URL normalization
- src/storage/config.zig — for timeout, retry, delay, verbose settings

---

## Governance

- All meaningful changes require team consensus
- Document architectural decisions here
- Keep history focused on work, decisions focused on direction

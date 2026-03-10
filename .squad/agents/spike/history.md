# Spike — History

## Core Context

**Project:** otaku — terminal-based manga browser and downloader  
**Language:** Zig (0.15.2)  
**User:** Christian Helle  
**Build:** zig build | **Test:** zig build test  
**Stack:** Zig, terminal UI (TUI), HTTP client, manga scraping  
**Sources:** MangaFox/FanFox and other manga websites  
**Repo:** C:\projects\christianhelle\otaku  

**Team:**
- Spike (me) — Lead
- Jet — Systems Dev (HTTP, scraping, download engine)
- Faye — TUI Dev (terminal UI, navigation, display)
- Ed — Tester (tests, edge cases, quality)

## Learnings

### Phase 1 Foundation (completed)
- Created full project directory structure (12 subdirectories, 47 source files)
- Implemented domain types: MangaTitle, Chapter, CategoryFeed, DownloadJob, LocalLibraryEntry with enums for MangaStatus, CategoryKind, DownloadStatus, LocalChapterStatus
- Implemented chapter ordering: parseChapterNumber() handles "5", "5.5", "v2/c10" patterns; compareChapterNumbers() for numeric-aware sort
- Implemented filter types: StatusFilter, GenreFilter, BrowseFilter, SortOrder
- Implemented Config with defaults following argiope Options pattern
- Rewrote main.zig with full CLI dispatch: tui, browse, search, title, download, library build, help, version
- Simplified build.zig: removed library module export, kept exe + test steps only
- Zig 0.15.2: std.fs.File.stdout().writer(&buf) then fw.interface.print(...) — NOT std.io.getStdOut()
- Zig 0.15.2: std.heap.GeneralPurposeAllocator(.{}) = .init not = {}
- std.mem.sort() takes a comparison function (not a struct method) — use anonymous struct .lessThan pattern
- @constCast needed to call deinit on items from a const slice iteration
- Module compile test in main.zig imports all submodules to catch broken files early

### Phase 4 TUI/FanfoxClient Wiring (completed)
- Wired TUI actions to FanfoxClient for live network data
- App struct now owns FanfoxClient instance initialized with Config.defaults
- Added allocator field to App so actions can manage heap memory
- All network actions (load_category, load_title, load_chapters, start_search) now fetch real data
- Memory lifecycle: FanfoxClient returns owned slices → AppState stores them → deinit frees recursively
- AppState.deinit now properly frees category_titles, current_title, current_chapters, search_results
- Download queue actions (download_selected, download_all) build full DownloadJob structs with all required fields (manga_slug, chapter_number, url, output_dir)
- Fixed pre-existing issue in downloads/manager.zig (pointless discard of chapter_dir variable)
- Build and test both pass

### Phase 5-6 Wiring Coordination
- Jet implemented DownloadManager (init/deinit, downloadChapter, downloadAll) and DownloadQueue (FIFO semantics)
- Jet wired all CLI commands: browse, search, title, download, library_build
- Each command creates fresh GPA allocator and FanfoxClient for isolation
- TUI layer now fully operational with network integration
- CLI layer fully operational for browsing, searching, viewing, queueing downloads
- All 100/100 tests pass in Jet's phase
- Download image fetching deferred pending reader parser implementation

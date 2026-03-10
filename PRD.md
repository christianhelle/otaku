# PRD: Otaku — Zig Terminal Manga Browser & Downloader for Fanfox

## Document Status
Draft v2

## Date
2026-03-09

## Owner
christianhelle

## Target Repository
`christianhelle/otaku`

## Related Repository
`christianhelle/argiope`

---

## 1. Product Summary

Otaku is the long-term home for all browse-first functionality in the Fanfox manga tooling ecosystem.

Otaku is a cross-platform Zig terminal user interface (TUI) application for browsing and downloading manga from Fanfox (`https://fanfox.net`). It will provide a terminal-native experience for:

- category browsing
- title discovery
- search and filtering
- title metadata inspection
- chapter selection
- chapter downloading
- offline HTML library generation
- direct CLI workflows for automation and power users

Otaku will be the primary user-facing product for browse-first workflows.

Argiope remains the download-first companion tool and implementation reference for proven Fanfox downloading behavior, extraction strategies, chapter ordering, and output conventions.

---

## 2. Background and Context

A prior Zig tool, `christianhelle/argiope`, already demonstrates that Fanfox-aware downloading is practical in Zig and provides important architectural guidance.

Argiope currently includes:

- Fanfox-aware URL routing
- chapter downloading
- chapter range filtering
- deterministic output organization
- lightweight HTML parsing/extraction
- offline HTML library generation
- cross-platform binary delivery
- a mostly stdlib-first implementation approach

Otaku should not duplicate complexity arbitrarily, but it should own the user experience for browse-first workflows while borrowing or adapting proven Fanfox logic from Argiope where it improves correctness, speed, or maintainability.

---

## 3. Problem Statement

Argiope works best when the user already knows the exact manga URL to download. It does not provide a rich browse-first interface for discovering titles, navigating Fanfox categories, filtering the manga directory, inspecting summaries, or interactively selecting chapters.

Users need a terminal-first application that lets them:

- browse Fanfox categories without leaving the terminal
- inspect manga metadata before downloading
- navigate directory listings by genre and status
- select one, many, a range of, or all chapters for download
- maintain a local downloadable library that can also be browsed offline through generated HTML

---

## 4. Vision

Build a fast, keyboard-driven, robust Zig terminal application that makes Fanfox natively browsable from the command line.

Otaku should feel like:

- a terminal manga discovery browser
- a terminal directory/catalog client
- a practical downloader for collectors and power users
- a local-library-oriented manga acquisition tool
- a clean, scriptable companion to Argiope

---

## 5. Product Positioning

### 5.1 Otaku
Otaku owns:

- browse-first workflows
- category navigation
- search and filtering
- title and chapter exploration
- interactive terminal UX
- direct CLI browse and download commands
- offline HTML library generation
- local library visibility and navigation

### 5.2 Argiope
Argiope remains:

- download-first
- a reference implementation for Fanfox extraction and download behavior
- a source of proven ideas for chapter discovery, ordering, and storage conventions
- a companion utility, not the primary browse-first interface

### 5.3 Product Relationship
The long-term architecture should allow Otaku to incorporate or adapt the best parts of Argiope’s download pipeline while keeping Otaku’s browse-first UX and product identity distinct.

---

## 6. Goals

### 6.1 Primary Goals
- Provide a terminal UI for browsing Fanfox manga categories
- Support browsing by genre and filtering by status
- Show manga metadata including title, author, genres, and summary
- Provide chapter lists with correct reading order
- Allow download of single chapters, selected chapters, chapter ranges, or all chapters
- Generate an offline HTML library directly in Otaku v1
- Provide direct CLI mode as a first-class MVP requirement
- Reuse or adapt Argiope’s proven Fanfox extraction and download logic where practical
- Ship as a cross-platform Zig binary

### 6.2 Secondary Goals
- Detect and surface local download state
- Cache metadata and browse results to improve responsiveness
- Minimize unnecessary network traffic
- Keep the implementation modular enough for future source expansion
- Preserve output compatibility with Argiope-style folder layouts where practical

### 6.3 Non-Goals for v1
- Embedded terminal image reader
- Multi-site scraping beyond Fanfox
- Browser automation
- Cloud sync
- User accounts
- AI-generated metadata enrichment
- Embedded database persistence
- Real-time notifications
- Favorites/watchlists unless they come “for free” from the architecture

---

## 7. Users

### 7.1 Primary Users
- Terminal-first users who want to browse manga without a web browser
- Existing Argiope users who want richer discovery and selection workflows
- Manga collectors and archivists who want structured download control

### 7.2 User Needs
- Fast keyboard navigation
- Efficient browse-first discovery
- Clear metadata before download
- Reliable chapter listing and selection
- Download queue visibility
- Recognition of already-downloaded content
- Offline library browsing after download

---

## 8. User Stories

### 8.1 Discovery
- As a user, I want to browse **Hot Manga Releases** so I can discover active titles.
- As a user, I want to browse **Being Read Right Now** so I can see what is currently popular.
- As a user, I want to browse **Recommended** titles.
- As a user, I want to browse **New Manga Release** titles.
- As a user, I want to browse **Last Updates**.
- As a user, I want to browse **Trending**.

### 8.2 Directory Browsing
- As a user, I want to browse by genre.
- As a user, I want to filter titles by status.
- As a user, I want to navigate long result sets efficiently.

### 8.3 Metadata
- As a user, I want to see:
  - title
  - author
  - genres
  - summary

### 8.4 Chapter Workflows
- As a user, I want to open a title and inspect available chapters.
- As a user, I want to download one chapter.
- As a user, I want to download selected chapters.
- As a user, I want to download a chapter range.
- As a user, I want to download all chapters.
- As a user, I want to know which chapters already exist locally.

### 8.5 Library Workflows
- As a user, I want Otaku to generate a browsable offline HTML library from downloaded content.
- As a user, I want to rebuild the HTML library without redownloading chapters.
- As a user, I want the generated library to remain portable across machines/folders.

### 8.6 Trust and Control
- As a user, I want visible progress and errors.
- As a user, I want polite network behavior by default.
- As a user, I want retries and sensible failure handling.
- As a user, I want both an interactive TUI and direct CLI workflows.

---

## 9. Scope

## 9.1 In Scope
- Interactive TUI browsing
- Required Fanfox category browsing
- Genre browsing
- Status filtering
- Search
- Title detail view
- Chapter list view
- Chapter selection
- Download queue and progress
- Local state awareness
- Offline HTML library generation
- Direct CLI browse/download/library commands
- File-based caching and metadata
- Cross-platform build and delivery

## 9.2 Out of Scope for v1
- In-terminal image rendering/reading
- Multi-source support
- Browser automation
- Embedded database
- Cloud sync
- User auth features
- Advanced recommendation systems beyond Fanfox-provided content

---

## 10. Functional Requirements

## 10.1 Application Modes

Otaku v1 must support both interactive and direct command workflows.

### 10.1.1 Interactive TUI
Default launch:
```sh
otaku
```

### 10.1.2 Direct CLI Mode
Required MVP functionality.

Examples:
```sh
otaku browse hot
otaku browse trending
otaku browse new
otaku browse updates
otaku search "naruto"
otaku title https://fanfox.net/manga/naruto/
otaku download https://fanfox.net/manga/naruto/ --chapters 1-20
otaku download https://fanfox.net/manga/naruto/ --all
otaku library build
otaku library build --root ./manga
```

### 10.1.3 Compatibility-Oriented Behavior
Where practical, Otaku should preserve familiar semantics from Argiope, especially for:
- `--chapters N-M`
- `-o, --output`
- timeout/delay controls
- skip-existing behavior
- deterministic output layout

---

## 10.2 Home Screen Requirements

The TUI home screen must expose:

1. Hot Manga Releases
2. Being Read Right Now
3. Recommended
4. New Manga Release
5. Last Updates
6. Trending
7. Browse by Genre
8. Search
9. Downloads
10. Library
11. Settings
12. Help
13. Exit

---

## 10.3 Required Browse Categories

The product must support these required browse categories:

1. Hot Manga Releases
2. Being Read Right Now
3. Recommended
4. New Manga Release
5. Last Updates
6. Trending

### Known Source URLs
- New Manga Release → `https://fanfox.net/directory/?news`
- Last Updates → `https://fanfox.net/releases/`
- Trending → `https://fanfox.net/trending/`
- Genre/Directory browsing → `https://fanfox.net/directory/`

For categories whose content may appear in homepage or composite layouts, the parser architecture must be resilient and adaptable rather than tightly coupled to one HTML layout.

---

## 10.4 Genre Browsing

The app must:
- list genres from Fanfox directory sources
- allow browsing by genre
- support applying a genre filter to title lists

### Minimum for v1
- one active genre filter

### Nice-to-have if cheap
- multi-genre support

---

## 10.5 Status Filtering

At minimum, the app must support:
- All
- Ongoing
- Completed

The model should remain extensible for:
- Hiatus
- Cancelled
- Unknown

---

## 10.6 Search

Otaku v1 must support:
- title keyword search
- result list navigation
- opening title detail view from search results

If Fanfox search behavior proves unstable, Otaku may implement directory-backed search heuristics as long as the user experience remains coherent and documented.

---

## 10.7 Title Detail View

The title detail view must display:

- title
- author
- genres
- summary

Strongly recommended if available:
- artist
- status
- alternative titles
- rating
- source URL
- latest chapter
- chapter count

### Detail View Actions
- View chapters
- Download selected
- Download all
- Download latest
- Open in browser
- Copy URL
- Back

---

## 10.8 Chapter List View

The chapter list view must:
- display chapters in correct numeric reading order
- support long chapter lists efficiently
- allow single-select and multi-select
- allow select all
- allow range-based selection
- indicate local chapter presence where possible

Ordering must preserve correct numeric behavior, including decimal chapter values where Fanfox exposes them.

---

## 10.9 Downloading

Users must be able to:
- download one chapter
- download selected chapters
- download a range of chapters
- download all chapters

### Output Layout
Default structure:
```text
<library-root>/<manga-title>/<chapter>/<page>.jpg
```

Otaku should preserve compatibility with Argiope-style output organization where practical.

### Download Queue Requirements
The app must provide:
- queue display
- per-job status
- current item progress
- completed count
- failed count
- retry support
- cancellation of current or queued work
- post-run summary

### Resume and Skip Requirements
- skip existing files by default
- allow force-redownload
- detect partial completion where possible
- maintain file-based manifests for download state

---

## 10.10 Local Library Awareness

Otaku must:
- detect whether a title exists locally
- detect whether individual chapters already exist locally
- expose local status in title/chapter views where practical

Optional future enhancements may include:
- direct TUI browsing of only local content
- local-only filtering
- import/reindex workflows

---

## 10.11 Configuration

Otaku must support persistent configuration.

### Suggested Config Paths
- Linux/macOS: `~/.config/otaku/config.toml`
- Windows: platform-appropriate app config path

### Configurable Values
- library root
- request timeout
- request delay
- concurrency
- retries
- user agent
- cache directory
- theme
- keybinding preset
- confirmation prompts
- browser command
- auto-build HTML library after downloads
- verbose logging defaults

---

## 10.12 File-Based Caching

Otaku v1 will use file-based caching only.

The application should cache:
- category pages or normalized category results
- directory results
- title metadata
- chapter listings

### Cache Features
- TTL-based expiration
- manual refresh
- stale-state indication
- invalidate-on-demand

### v1 Constraints
- no embedded database
- cache entries stored as files
- metadata stored as files
- local state inferred from filesystem plus manifest files

---

## 10.13 Local Metadata and Manifest Storage

Otaku v1 will use file-based metadata only.

### Requirements
- store download manifests as files
- store cache entries as files
- store normalized metadata snapshots as files where useful
- track completion using file manifests and filesystem inspection
- keep formats human-inspectable where practical (e.g. JSON or TOML)

### Design Goals
- portability
- easy backup
- minimal operational complexity
- straightforward debugging
- future migration path if a database is ever needed later

---

## 10.14 Offline HTML Library Generation

Otaku v1 must directly generate a browsable offline HTML library for downloaded content.

### Requirements
- generate a root library page
- generate per-title browsing pages
- generate per-chapter reader pages or equivalent ordered chapter navigation
- keep links relative for portability
- preserve compatibility with Argiope-style output where practical
- support regeneration without redownloading
- support generation from both TUI and CLI workflows

### CLI Examples
```sh
otaku library build
otaku library build --root ./manga
otaku download https://fanfox.net/manga/naruto/ --all --build-library
```

### TUI Requirements
- library build action available from Library or Downloads screen
- user can rebuild library after downloads complete
- user can rebuild library for an existing local root

---

## 10.15 Direct CLI Commands

Direct CLI commands are MVP-hard requirements.

### Required Command Families
- `browse`
- `search`
- `title`
- `download`
- `library`

### Proposed Commands
```sh
otaku browse hot
otaku browse trending
otaku browse new
otaku browse updates
otaku browse recommended
otaku browse reading-now
otaku browse genre <genre>
otaku search <query>
otaku title <url-or-slug>
otaku download <url-or-slug> --chapters N-M
otaku download <url-or-slug> --all
otaku library build
otaku library build --root <dir>
```

### Required Flags
```text
--output <dir>
--chapters N-M
--all
--timeout <sec>
--delay <ms>
--parallel
--retries <n>
--refresh
--verbose
--build-library
```

---

## 11. Non-Functional Requirements

### 11.1 Performance
- fast startup
- smooth scrolling for large lists
- low memory overhead
- progressive loading where practical

### 11.2 Reliability
- no crashes on malformed or missing metadata
- graceful parser failure handling
- actionable error messages
- resumable/skip-aware downloads where possible
- deterministic filesystem output

### 11.3 Portability
Must support:
- Linux
- macOS
- Windows

### 11.4 Maintainability
Architecture must isolate:
- app state and navigation
- TUI rendering
- HTTP/networking
- Fanfox adapters
- HTML parsing
- download engine
- config/cache/persistence
- library generation

### 11.5 Dependency Philosophy
Preferred:
- Zig stdlib only, or as close as possible
- any extra dependency must be justified, small, and isolated

### 11.6 Network Politeness
Otaku must:
- use conservative default request pacing
- support configurable delay and concurrency
- avoid aggressive defaults
- cache responses when useful
- retry only bounded transient failures

---

## 12. UX Requirements

## 12.1 Layout

Recommended TUI structure:
- left pane: categories / filters / navigation
- center pane: title list or chapter list
- right pane: metadata / actions / queue details

Alternative responsive layouts are acceptable as long as usability remains good at 80x24.

---

## 12.2 Keyboard Controls

Required baseline keyboard controls:
- `j/k` or arrows: move
- `Enter`: open/select
- `Tab`: switch pane
- `/`: search
- `g`: genre filter
- `s`: status filter
- `d`: download selected
- `a`: download all
- `Space`: toggle selection
- `A`: select all
- `r`: refresh
- `b`: build/rebuild library when contextually applicable
- `q`: back/quit depending on context
- `?`: help

---

## 12.3 Status Bar

The status bar should show:
- current screen/category
- item count
- selected item
- network activity
- queue summary
- cache or stale-state hints
- key hints

---

## 12.4 Empty and Error States

The app must clearly communicate:
- no titles found
- no chapters found
- network timeout
- parse failure
- summary unavailable
- download failed
- library build failed

---

## 13. Information Architecture and Data Model

## 13.1 MangaTitle
Fields:
- id
- slug
- url
- title
- alt_titles[]
- author
- artist
- genres[]
- status
- summary
- cover_url
- rating
- latest_chapter
- chapter_count
- last_fetched_at

## 13.2 Chapter
Fields:
- id
- manga_id
- number
- volume
- title
- url
- release_date
- page_count
- local_status

## 13.3 CategoryFeed
Fields:
- kind
- title
- url
- items[]
- fetched_at

## 13.4 DownloadJob
Fields:
- id
- manga_id
- manga_title
- chapter_ids[]
- destination
- status
- progress
- created_at
- updated_at
- error_message

## 13.5 LocalLibraryEntry
Fields:
- manga_title
- path
- downloaded_chapters[]
- total_size
- updated_at

---

## 14. Technical Architecture

## 14.1 High-Level Modules

```text
src/
  main.zig
  app/
    app.zig
    router.zig
    state.zig
    actions.zig
  tui/
    terminal.zig
    layout.zig
    widgets/
      list.zig
      table.zig
      detail.zig
      statusbar.zig
      modal.zig
      progress.zig
  domain/
    manga.zig
    chapter.zig
    category.zig
    filters.zig
    download.zig
  fanfox/
    client.zig
    endpoints.zig
    adapters.zig
    parsers/
      categories.zig
      directory.zig
      title.zig
      chapters.zig
      reader.zig
  http/
    client.zig
    rate_limiter.zig
    retry.zig
  downloads/
    manager.zig
    queue.zig
    saver.zig
    manifest.zig
  library/
    builder.zig
    templates.zig
    indexer.zig
  storage/
    cache.zig
    config.zig
    filesystem.zig
    metadata.zig
  integrations/
    argiope_compat.zig
  util/
    strings.zig
    html.zig
    urls.zig
    sort.zig
    time.zig
```

---

## 14.2 Architectural Principles
- keep Fanfox-specific logic isolated
- keep the download engine reusable
- separate rendering from application state
- separate normalized models from parser output details
- use file-based persistence in v1
- preserve the ability to evolve shared logic with Argiope later

---

## 15. Argiope Reuse Requirements

Otaku should reuse or adapt proven ideas from `christianhelle/argiope`, especially for:

- Fanfox host detection
- chapter discovery
- chapter/page/image extraction
- numeric chapter ordering
- chapter range semantics
- output directory conventions
- offline HTML library generation patterns
- downloader behavior and retry/skip concepts

Preferred implementation strategy:
- isolate reused/adapted logic behind clean interfaces
- avoid tight coupling between TUI code and downloader internals
- preserve future options for shared-module convergence

---

## 16. Networking Requirements

The HTTP/network layer must support:
- GET requests
- timeout control
- redirects
- retries with backoff
- configurable user agent
- request throttling
- bounded concurrency

### Behavioral Constraints
- polite defaults
- bounded retries
- clear classification of network vs parse vs filesystem failures
- cache-aware fetching where practical

---

## 17. Parsing Requirements

The parser layer must support:
- category/homepage discovery blocks
- releases pages
- trending pages
- directory pages
- title detail pages
- chapter list pages
- reader/image pages where required for downloading

### Parser Design Requirements
- primary extraction rules
- fallback extraction rules
- normalized domain model output
- clear parse-failure diagnostics
- fixture-based tests

---

## 18. Testing Requirements

Otaku should include:

### 18.1 Parser Tests
- fixture coverage for all supported source page types
- regression tests for layout drift where practical

### 18.2 Unit Tests
- chapter ordering
- filter application
- config load/save
- cache TTL behavior
- manifest read/write

### 18.3 Integration Tests
- title browse flow with fixtures/mocks
- chapter selection to download job conversion
- library generation output checks

### 18.4 CLI Tests
- command parsing
- help output
- required flag behavior
- direct library build workflow

---

## 19. Acceptance Criteria

### 19.1 Browsing
- Launching `otaku` opens an interactive home screen.
- The home screen lists all required categories.
- Selecting a category loads titles.
- Genre browsing is available.
- Status filters update visible results.
- Search returns navigable title results.

### 19.2 Metadata
- Selecting a title displays title, author, genres, and summary.

### 19.3 Chapters
- Selecting a title opens a chapter list.
- Chapter ordering matches expected reading order.
- Chapter list supports selection and select-all behavior.

### 19.4 Downloads
- User can download one chapter.
- User can download selected chapters.
- User can download a chapter range.
- User can download all chapters.
- Existing files are skipped by default unless forced.

### 19.5 Local Awareness
- Existing local chapters are detected where practical.
- Local status is surfaced in the UI and/or command output.

### 19.6 HTML Library
- Otaku can generate an offline HTML library from existing content.
- Otaku can rebuild the library without redownloading.
- Generated links remain portable and relative.

### 19.7 CLI
- Direct CLI browse, title, download, and library commands work in MVP.

### 19.8 Reliability
- Parser failures do not crash the app.
- Network failures are surfaced clearly.
- The application exits cleanly.

---

## 20. MVP Definition

The MVP includes:

1. Interactive TUI home screen
2. All 6 required browse categories
3. Genre browsing
4. Status filtering
5. Search
6. Title detail view with required metadata
7. Chapter list
8. Single/select/range/all download support
9. Download progress queue
10. Persistent configuration
11. File-based caching and metadata persistence
12. Direct CLI commands for browse, title lookup, download, and library build
13. Offline HTML library generation in Otaku
14. Fanfox parsing and download logic adapted from Argiope where useful

The MVP does not require:
- offline reading in terminal
- favorites/watchlists
- notifications
- multi-source support
- embedded database persistence

---

## 21. Risks and Mitigations

### 21.1 Fanfox HTML Drift
Risk:
- page structures may change and break parsers

Mitigation:
- modular parser design
- fallback extraction rules
- fixture-based tests
- parse diagnostics

### 21.2 TUI Complexity
Risk:
- TUI feature growth may slow delivery

Mitigation:
- prioritize reliable list/detail/download flows
- defer in-terminal reading and advanced visuals

### 21.3 Shared Logic Drift with Argiope
Risk:
- copied logic diverges over time

Mitigation:
- isolate compatibility boundaries
- keep shared concerns explicit
- document reuse/adaptation points

### 21.4 Request Blocking / Anti-Bot Constraints
Risk:
- source site may react poorly to aggressive scraping

Mitigation:
- conservative defaults
- cache usage
- configurable delays
- bounded concurrency
- bounded retries

### 21.5 File-Based Metadata Scaling
Risk:
- file-based storage may become awkward at larger scale

Mitigation:
- keep formats simple and structured
- isolate persistence interfaces
- defer database complexity until proven necessary

---

## 22. Delivery Plan

### Phase 1 — Foundation
- project scaffold
- build system
- app state model
- error model
- config basics
- logging
- CLI skeleton

### Phase 2 — Data and Parsing
- endpoint definitions
- HTTP client
- category parsers
- directory parser
- title parser
- chapter parser
- parser fixtures/tests

### Phase 3 — TUI Shell
- terminal rendering
- navigation framework
- reusable widgets
- home screen
- loading/error/help states

### Phase 4 — Browse Flows
- category screens
- search
- genre filter
- status filter
- title detail
- chapter list and selection

### Phase 5 — Downloads and Local State
- downloader integration
- queue
- manifests
- skip/resume behavior
- local chapter detection

### Phase 6 — Offline Library
- HTML library generation
- rebuild workflows
- TUI + CLI integration

### Phase 7 — Polish
- docs
- tests
- packaging
- UX tuning
- compatibility improvements

---

## 23. Success Metrics

### 23.1 Product Success
- users can browse all required categories from the terminal
- users can inspect title metadata and chapter lists
- users can download selected or all chapters
- users can build and rebuild an offline HTML library
- users can use either interactive or direct CLI workflows

### 23.2 Engineering Success
- stable builds on Linux/macOS/Windows
- parser coverage across all source page types
- deterministic output layout
- stable behavior under parser/network failures

### 23.3 UX Success
- keyboard-only usage is efficient
- layout remains usable at 80x24
- progress and errors are understandable
- local chapter state is clear enough to avoid accidental redownloads

---

## 24. Decision Record

### Confirmed Decisions
- Otaku is the long-term home for browse-first functionality.
- Argiope remains the download-first companion/reference tool.
- Offline HTML library generation is required in Otaku v1.
- Direct CLI commands are MVP-hard requirements.
- Local metadata and cache are file-based only in v1.

---

## 25. Open Implementation Questions

These are implementation questions, not product-direction questions:

- Should Otaku vendor adapted Argiope logic directly at first, or extract shared modules immediately?
- Should category fetches cache raw HTML, normalized JSON/TOML, or both?
- Should library generation be incremental by default, or always full rebuild unless explicitly optimized later?
- What is the minimum useful local manifest schema for balancing portability and resumability?

---
```
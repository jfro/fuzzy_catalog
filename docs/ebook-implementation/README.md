# Ebook File Management - Implementation Guide

This directory contains the complete implementation plan for adding ebook file management to FuzzyCatalog with a test-driven development approach.

## Quick Links

- [Phase 1: Oban Setup](./01-oban-setup.md) - Install and configure background job processing
- [Phase 2: Ebook Schema](./02-ebook-schema.md) - Create core data model with tests
- [Phase 3: Metadata Extraction](./03-metadata-extraction.md) - EPUB/PDF parsing libraries
- [Phase 4: ScanWorker](./04-scan-worker.md) - File discovery and scanning
- [Phase 5: ProcessWorker](./05-process-worker.md) - Metadata extraction and processing
- [Phase 6: Context API](./06-context-api.md) - Enhanced context functions
- [Phase 7: Configuration](./07-configuration.md) - Final configuration and verification

## Overview

**Goal:** Add support for managing ebook files on disk with proper metadata extraction, cover thumbnails, and book matching.

**Key Features:**
- ✅ Independent Ebook schema (first-class entities)
- ✅ Oban workers for background processing
- ✅ EPUB and PDF metadata extraction
- ✅ Cover thumbnail generation and storage
- ✅ ISBN-based and fuzzy book matching
- ✅ File integrity verification
- ✅ User-scoped operations

**Approach:** Test-Driven Development (TDD)
- Write tests first to define expected behavior
- Implement minimal code to pass tests
- Refactor while keeping tests green

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    User Interface                        │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│              Ebooks Context (API)                        │
│  - trigger_scan/1                                        │
│  - trigger_reprocess/1                                   │
│  - list_ebooks/1, get_ebook!/2                          │
└────────┬──────────────────────────────┬─────────────────┘
         │                              │
         ▼                              ▼
┌──────────────────┐          ┌──────────────────┐
│   ScanWorker     │          │  ProcessWorker   │
│  (Discovery)     │──────────│  (Enhancement)   │
│                  │  Enqueue │                  │
│ • Find files     │          │ • Extract meta   │
│ • Hash files     │          │ • Match books    │
│ • Create records │          │ • Store covers   │
└──────────────────┘          └──────────────────┘
         │                              │
         └──────────┬───────────────────┘
                    ▼
         ┌─────────────────────┐
         │   Ebook Schema      │
         │  (Database)         │
         └─────────────────────┘
                    │
         ┌──────────┴──────────┐
         ▼                     ▼
    ┌─────────┐          ┌─────────┐
    │  Book   │          │  User   │
    │ (opt.)  │          │ (req.)  │
    └─────────┘          └─────────┘
```

## Data Model

**Ebook Schema** (independent entity):
- File information (path, format, size, hash)
- Extracted metadata (title, author, ISBN, etc.)
- Processing status (pending, processing, completed, failed)
- Optional link to Book (via book_id)
- Required link to User (via user_id)

## Dependencies

New dependencies to add:
- `{:oban, "~> 2.18"}` - Background job processing
- `{:bupe, "~> 0.6.3"}` - EPUB parsing
- `{:pdfinfo, "~> 1.0"}` - PDF metadata extraction

## File Summary

**New Files:** 19 total
- 8 test files
- 7 implementation files
- 2 migrations
- 2 fixture files

**Modified Files:** 4 total
- `mix.exs` - dependencies
- `config/config.exs` - Oban config
- `config/test.exs` - Oban test config
- `lib/fuzzy_catalog/application.ex` - supervision tree

## TDD Workflow

For each phase:
1. **Red** - Write tests that define expected behavior (they fail)
2. **Green** - Write minimal implementation to pass tests
3. **Refactor** - Improve code quality while keeping tests green
4. **Verify** - Run `mix test` to ensure all tests pass

## Critical Notes

### User Scoping
**CRITICAL:** All ebook operations must be scoped to user_id:
- Every ebook belongs to a user
- All queries filter by user_id
- Test multi-user isolation

### Integration Points
- **Storage:** Use existing `Storage.store_cover/2` and `Storage.get_cover_url/1`
- **Catalog:** Use `Catalog.get_book_by_isbn/1` and `Catalog.find_book_by_title_and_author/2`
- **Testing:** Use ExUnit's `@tag :tmp_dir` for filesystem tests
- **Oban:** Use `Oban.Testing` module with `perform_job/2` helper

## Progress Tracking

- [ ] Phase 1: Oban Setup
- [ ] Phase 2: Ebook Schema
- [ ] Phase 3: Metadata Extraction
- [ ] Phase 4: ScanWorker
- [ ] Phase 5: ProcessWorker
- [ ] Phase 6: Context API
- [ ] Phase 7: Configuration

## Getting Started

Begin with [Phase 1: Oban Setup](./01-oban-setup.md) to install and configure the background job processing foundation.

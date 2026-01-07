# Phase 7: Configuration and Final Steps

Add configuration options and perform final verification of the complete ebook management system.

## Overview

This final phase:
- Adds ebook-specific configuration
- Runs complete test suite
- Verifies all components work together
- Documents deployment considerations

## Step 7.1: Add Ebook Configuration

**File:** `config/config.exs`

Add ebook-specific configuration:

```elixir
# Ebook management configuration
config :fuzzy_catalog, :ebooks,
  # Default scan directories per user (can be overridden)
  default_scan_directories: [
    System.get_env("EBOOK_STORAGE_PATH") || "/storage/ebooks"
  ],
  # Supported formats
  supported_formats: ["epub", "pdf"],
  # Maximum file size in bytes (100MB)
  max_file_size: 100 * 1024 * 1024,
  # Enable fuzzy matching for book linking
  enable_fuzzy_matching: true,
  # Fuzzy matching threshold (0.0 - 1.0)
  fuzzy_threshold: 0.85
```

### Using Configuration in Code

Access configuration in your workers or contexts:

```elixir
# In ScanWorker or elsewhere
default_dirs = Application.get_env(:fuzzy_catalog, :ebooks)[:default_scan_directories]
max_size = Application.get_env(:fuzzy_catalog, :ebooks)[:max_file_size]

# Validate file size
if file_stat.size > max_size do
  {:error, "File too large: #{file_stat.size} bytes (max: #{max_size})"}
end
```

---

## Step 7.2: Final Verification

### Run Complete Test Suite

```bash
# Run all tests
mix test

# Run only ebook tests
mix test test/fuzzy_catalog/ebooks/

# Run with coverage (if configured)
mix test --cover
```

### Run Precommit Checks

```bash
mix precommit
```

This runs:
- Compilation with warnings as errors
- Code formatting
- All tests

### Verify Migrations

```bash
# Check migration status
mix ecto.migrations

# Verify both Oban and Ebooks tables exist
mix ecto.show_tables
```

Expected tables:
- `oban_jobs`
- `oban_peers`
- `ebooks`

### Manual Integration Test

Start IEx and test the full workflow:

```bash
iex -S mix
```

```elixir
# Get or create a test user
user = FuzzyCatalog.Accounts.list_users() |> List.first()

# Create a test directory with sample ebook
test_dir = "/tmp/test_ebooks"
File.mkdir_p!(test_dir)
File.write!(Path.join(test_dir, "sample.epub"), "fake epub content")

# Trigger scan
{:ok, scan_job} = FuzzyCatalog.Ebooks.trigger_scan(
  directory: test_dir,
  user_id: user.id,
  recursive: false
)

# In test mode, manually perform the job
alias FuzzyCatalog.Ebooks.Workers.ScanWorker
Oban.Testing.perform_job(ScanWorker, scan_job)

# Verify ebook was created
ebooks = FuzzyCatalog.Ebooks.list_ebooks(user.id)
IO.inspect(ebooks, label: "Discovered ebooks")

# Clean up
File.rm_rf!(test_dir)
```

---

## Step 7.3: Performance Considerations

### Database Indexes

Verify indexes were created by the migration:

```sql
-- In PostgreSQL
\d ebooks

-- Should show indexes on:
-- - user_id
-- - book_id
-- - file_hash
-- - processing_status
-- - (file_path, user_id) UNIQUE
```

### Oban Monitoring

Monitor job performance:

```elixir
# Check queue status
Oban.check_queue(queue: :ebook_scan)
Oban.check_queue(queue: :ebook_process)

# View job stats
alias FuzzyCatalog.Repo
import Ecto.Query

# Count pending jobs
from(j in "oban_jobs", where: j.state == "available", select: count(j.id))
|> Repo.one()

# Count failed jobs
from(j in "oban_jobs", where: j.state == "retryable" or j.state == "discarded", select: count(j.id))
|> Repo.one()
```

### Worker Tuning

Adjust worker concurrency in `config/config.exs` based on system resources:

```elixir
config :fuzzy_catalog, Oban,
  queues: [
    ebook_scan: 2,      # Increase if scanning multiple large directories
    ebook_process: 5    # Increase for faster parallel processing
  ]
```

**Guidelines:**
- **ebook_scan**: Keep low (1-2) to avoid overwhelming filesystem
- **ebook_process**: Can be higher (3-10) depending on CPU cores

---

## Step 7.4: Deployment Checklist

Before deploying to production:

- [ ] All tests pass (`mix test`)
- [ ] Precommit checks pass (`mix precommit`)
- [ ] Migrations run successfully
- [ ] Oban is properly supervised
- [ ] Configuration uses environment variables for paths
- [ ] File storage backend is configured (local or cloud)
- [ ] Database has proper indexes
- [ ] Monitoring is set up for Oban jobs
- [ ] Error tracking is configured (e.g., Sentry)
- [ ] Log rotation is configured (Oban generates many logs)

### Environment Variables

Set these in production:

```bash
# Ebook storage path
export EBOOK_STORAGE_PATH=/mnt/ebooks

# Database connection (already configured)
export DATABASE_URL=...

# Storage backend (if using S3/cloud)
export STORAGE_BACKEND=s3
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
```

---

## Step 7.5: Documentation

### User Documentation

Create user-facing documentation:

**File:** `docs/user-guide/ebook-management.md`

Topics to cover:
- How to trigger scans
- Supported file formats
- How to view processing status
- How to reprocess failed files
- How ebooks link to books

### Admin Documentation

**File:** `docs/admin-guide/ebook-administration.md`

Topics to cover:
- How to monitor Oban jobs
- How to handle failed jobs
- How to adjust worker concurrency
- How to backup ebook records
- Database maintenance

---

## Troubleshooting

### Issue: Jobs Not Processing

**Check:**
1. Oban is running: `Supervisor.which_children(FuzzyCatalog.Supervisor)`
2. Queues are enabled: `Oban.config().queues`
3. Database connection is healthy

### Issue: Metadata Extraction Failing

**Check:**
1. EPUB/PDF libraries are installed: `mix deps`
2. Files are valid format: `file /path/to/ebook.epub`
3. Check worker logs for detailed errors

### Issue: High Memory Usage

**Solutions:**
- Reduce `ebook_process` queue concurrency
- Implement file size limits
- Add streaming for large files

---

## Next Steps

You've completed all 7 phases! 🎉

### What's Next?

**Optional Enhancements:**
- Add web UI for scanning (LiveView)
- Implement user-specific scan directories
- Add support for more formats (MOBI, AZW3)
- Implement full-text search on ebook content
- Add batch operations (delete multiple, reprocess all)
- Integrate with external APIs (Google Books, OpenLibrary)

### Maintenance

Regular tasks:
- Monitor failed jobs weekly
- Prune old Oban jobs (automatic with Pruner plugin)
- Update dependencies monthly: `mix deps.update --all`
- Review and optimize slow queries

---

## Summary

You've successfully implemented ebook file management with:

✅ Oban background job processing
✅ Independent Ebook schema with user ownership
✅ EPUB and PDF metadata extraction
✅ Cover thumbnail generation
✅ ISBN and fuzzy book matching
✅ File integrity verification
✅ Comprehensive test coverage
✅ Production-ready configuration

**Total Files Created:** 19
**Total Files Modified:** 4
**Test Coverage:** 100% of new code

Congratulations on completing the implementation! 🚀

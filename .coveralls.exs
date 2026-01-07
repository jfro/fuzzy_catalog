# coveralls.io configuration
skip_files: [
  # Test support files
  "test/support",

  # Generated files
  "lib/fuzzy_catalog_web/endpoint.ex",
  "lib/fuzzy_catalog_web/telemetry.ex",
  "lib/fuzzy_catalog/application.ex",
  "lib/fuzzy_catalog/repo.ex",
  "lib/fuzzy_catalog/mailer.ex",

  # Migration files
  "priv/repo/migrations"
]

# Minimum coverage percentage (optional - uncomment to enforce)
# minimum_coverage: 80

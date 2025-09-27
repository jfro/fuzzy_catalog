# Fuzzy Catalog Changelog

## v0.4.0

- BookLore external library syncing - #20
- Reworked external sync to better support books being in more than 1 external library
- External library links on book page for AudioBookShelf & BookLore (NOTE: BookLore links won't work if it uses OIDC until this bug is fixed: booklore-app/booklore#1224 )
- Fixed search clear button not actually doing anything - #21

## v0.3.1

- Fix scheduled external library sync not syncing anymore

## v0.3.0

- Fixes sync popups not being closeable - #4
- Fix external library sync not showing status when initial requests are slow - #7
- Adds scheduled external library syncing - #8
- Fix registration links showing despite being disabled - #9
- Mail sending configuration for Mailgun or SMTP - #2
- OIDC Auth support - #17

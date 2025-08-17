# FuzzyCatalog

## Under Development

This is still pretty heavily under development, but closing in on something I think I can personally use. I hope it may be useful to others who were looking for something to catalog their physical books & more with. Hopefully more to come!

## Features

- Barcode scanning of physical books via keyboard input scanners (webcam one may still work but have not had much luck with it)
- Ability to sync with digital libraries, currently from Audiobookshelf (via API) & Calibre (via actual path to library files)
- Adding books via title or ISBN pulls metadata from Open Library or Google Books (Library of Congress available but not sure it's worth using)

## Environment Setup

| Env | Usage |
| --- | --- |
| DATABASE_URL | REQUIRED postgres database URL, i.e.: ecto://user:password@host:port/database |
| SECRET_KEY_BASE | REQUIRED random secret |
| PHX_HOST | domain to use (i.e. localhost) |
| PORT | port to use, default is 4000 |
| AUDIOBOOKSHELF_URL | URL to an instance of Audiobookshelf for syncing |
| AUDIOBOOKSHELF_API_KEY | API key for Audiobookshelf |
| AUDIOBOOKSHELF_LIBRARIES | Comma separated list of library names to sync from Audiobookshelf |
| CALIBRE_LIBRARY_PATH | Path to Calibre library files, including ebooks & metadata.db file |

## Possible TODO

- Expose mail sending configuration (Swoosh settings) to ENV
- Support for other digital libraries like Kavita, Calibre-Web (OPDS), and more
- Explore adding support for other physical items like movies or games

## Local Dev

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

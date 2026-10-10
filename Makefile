# This repository builds nothing (E15). It publishes the surface a mod author
# writes against: the generated SDK stubs, the worked examples and the docs.
#
# Two things here are produced by the engine and committed, so an author needs
# neither a toolchain nor a checkout of the engine:
#
#   stubs/ermod.lua               `make stubs`      in elden-ring-mods-engine
#   docs/cli.md, docs/cli.html    `make cli-docs`   in elden-ring-mods-engine
#
# What is left here is checking that what is committed is what the engine
# would produce, and `make site`, which renders docs/ into the website with
# pandoc and pagefind from the flake. Its output (_site/) is never committed.

ENGINE ?= ../elden-ring-mods-engine

RUMDL ?= rumdl
PANDOC ?= pandoc
PAGEFIND ?= pagefind

# The website, built into $(SITE) and deployed by .github/workflows/pages.yml.
SITE ?= _site
SITE_URL := https://benehiko.github.io/elden-ring-mods
REPO_BLOB := https://github.com/Benehiko/elden-ring-mods/blob/main

# A guide's <meta name="description">, for search results and link previews,
# comes from a `<!-- description: ... -->` line under its title (invisible on
# GitHub). A guide without one gets this.
DEFAULT_DESCRIPTION := Cross-platform Elden Ring mods: live Lua mods on Linux, macOS and Windows (experimental), private LAN or VPN co-op on Linux and macOS, your game install and saves never touched.

# Every guide in docs/ becomes a page. cli.md is left out: the engine
# generates cli.html for the website itself. docs/README.md is the guides
# index, so it becomes guides.html.
GUIDES := $(filter-out docs/cli.md docs/README.md,$(wildcard docs/*.md))

.PHONY: hooks check-stubs check-cli-docs fmt check-fmt site serve

# Builds the website: plain HTML and CSS, a few lines of JavaScript for the
# theme switch, and a static search index. Nothing runs on a server.
#
#   1. The hand-written pages and assets are copied as they are.
#   2. pandoc renders each guide into docs/guide.template.html. Line 1 of a
#      guide is its `# Title`; it becomes the page title and the template's
#      <h1>, and the rest is rendered with GitHub's heading anchors, so a link
#      that works on GitHub works on the site.
#   3. Links are rewritten for the site: guide.md to guide.html, links out of
#      docs/ to GitHub, and the GitHub guide links in the generated cli.html to
#      the pages here. cli.html also gets the theme script, which the engine's
#      generator does not emit yet.
#   4. cli.html gets a canonical link, and sitemap.xml lists
#      every page but search.html, for search engines. (A robots.txt would be
#      ignored: it only counts at the root of benehiko.github.io.)
#   5. pagefind indexes the result into $(SITE)/pagefind for search.html.
#
# pandoc and pagefind come from the flake, pinned by flake.lock.
site:
	@rm -rf $(SITE) && mkdir -p $(SITE)
	@cp docs/index.html docs/cli.html docs/search.html docs/style.css docs/theme.js $(SITE)/
	@for md in $(GUIDES) docs/README.md; do \
		name=$$(basename "$$md" .md); \
		[ "$$name" = README ] && name=guides; \
		title=$$(sed -n '1s/^# //p' "$$md"); \
		[ -n "$$title" ] || { echo "site: $$md must start with a '# Title' line" >&2; exit 1; }; \
		desc=$$(sed -n 's/^<!-- description: \(.*\) -->$$/\1/p' "$$md" | head -n 1); \
		[ -n "$$desc" ] || desc='$(DEFAULT_DESCRIPTION)'; \
		sed -e 1d -e '/^<!-- description: /d' "$$md" | $(PANDOC) --from gfm --to html5 \
			--template docs/guide.template.html \
			--toc --toc-depth=2 --wrap=none \
			--metadata pagetitle="$$title" --metadata source="$$md" \
			--metadata description="$$desc" --metadata url="$(SITE_URL)/$$name.html" \
			--output "$(SITE)/$$name.html" || exit 1; \
	done
	@for f in $(SITE)/*.html; do \
		sed -E \
			-e 's#href="README\.md#href="guides.md#g' \
			-e 's#href="([A-Za-z0-9_-]+)\.md#href="\1.html#g' \
			-e 's#href="\.\./#href="$(REPO_BLOB)/#g' \
			-e 's#href="$(REPO_BLOB)/docs/([A-Za-z0-9_-]+)\.md#href="\1.html#g' \
			"$$f" > "$$f.tmp" && mv "$$f.tmp" "$$f" || exit 1; \
	done
	@grep -q 'src="theme.js"' $(SITE)/cli.html || { \
		sed 's#</head>#<script src="theme.js"></script></head>#' $(SITE)/cli.html > $(SITE)/cli.html.tmp && \
		mv $(SITE)/cli.html.tmp $(SITE)/cli.html; }
	@grep -q 'rel="canonical"' $(SITE)/cli.html || { \
		sed 's#</head>#<link rel="canonical" href="$(SITE_URL)/cli.html"></head>#' \
			$(SITE)/cli.html > $(SITE)/cli.html.tmp && mv $(SITE)/cli.html.tmp $(SITE)/cli.html; }
	@{ echo '<?xml version="1.0" encoding="UTF-8"?>'; \
		echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'; \
		echo '  <url><loc>$(SITE_URL)/</loc></url>'; \
		for f in $(SITE)/*.html; do \
			name=$$(basename "$$f"); \
			case "$$name" in index.html|search.html) continue;; esac; \
			echo "  <url><loc>$(SITE_URL)/$$name</loc></url>"; \
		done; \
		echo '</urlset>'; } > $(SITE)/sitemap.xml
	@$(PAGEFIND) --site $(SITE) --output-subdir pagefind --quiet
	@echo "site: built $(SITE)/ ($$(ls $(SITE)/*.html | wc -l | tr -d ' ') pages)"

# Serves the built site on http://localhost:1414. Search needs a server:
# browsers refuse to load the index from file:// URLs.
serve: site
	@$(PAGEFIND) --site $(SITE) --output-subdir pagefind --quiet --serve

# Formats and lint-fixes every Markdown file with rumdl (.rumdl.toml). `nix
# develop` provides it, at the version pinned in flake.lock; the generated
# docs/cli.md is left alone.
fmt:
	@$(RUMDL) fmt .

# Fails if any Markdown file is not formatted or breaks a lint rule (a
# broken relative link, say). CI runs the same check.
check-fmt:
	@$(RUMDL) check .

hooks:
	git config core.hooksPath .githooks
	chmod +x .githooks/pre-commit

# Fails if the committed stubs are not what the engine generates. The engine
# has the binding tables, so it is the authority; this only detects drift.
check-stubs:
	@test -x "$(ENGINE)/zig-out/bin/ermod-engine" || { \
		echo "check-stubs: build the engine first (make -C $(ENGINE) build)" >&2; exit 1; }
	@$(ENGINE)/zig-out/bin/ermod-engine dev stubs /tmp/ermod-stubs-check.lua >/dev/null
	@diff -u stubs/ermod.lua /tmp/ermod-stubs-check.lua && echo "check-stubs: stubs are current"

# Fails if the committed command reference is not what the engine generates
# from its --help. The engine's `zig build test` makes the same check from
# its side.
check-cli-docs:
	@test -f "$(ENGINE)/build.zig" || { \
		echo "check-cli-docs: no engine checkout at $(ENGINE)" >&2; exit 1; }
	@rm -rf /tmp/ermod-cli-check && mkdir -p /tmp/ermod-cli-check
	@cd "$(ENGINE)" && zig build cli-docs -- /tmp/ermod-cli-check 2>/dev/null
	@diff -u docs/cli.md /tmp/ermod-cli-check/cli.md && \
		diff -u docs/cli.html /tmp/ermod-cli-check/cli.html && \
		echo "check-cli-docs: the command reference is current"

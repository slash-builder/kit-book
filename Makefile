# The Makefile is the one entry point: people, and the CI job, call these targets and nothing else.
# Works with the system make on macOS (3.81) and Linux. Plain POSIX sh underneath; see tools/.

BOOK_NAME := kit-book

SHELL := /bin/sh
.DEFAULT_GOAL := help

# KITS=public (default) fetches only public Kits; KITS=all also fetches private ones (needs a GitHub login).
KITS ?= public
export KITS
# APP=<folder under apps/> for `make app` and `make run`.
APP ?=
# KIT=<name from kits.lock> for `make lock`; empty means every Kit.
KIT ?=
# Maintainers only, for `make docs-catalog`: the Kit registry file (or set KITS_REGISTRY), the registry commit to print
# in the catalog index, OFFLINE=1 to reuse tools/kit-visibility.tsv instead of asking GitHub, and the python to run
# (it needs PyYAML; readers and `make docs` never do). `make docs-pull` needs no PyYAML: it uses python3 and the standard library.
REGISTRY ?=
REGISTRY_COMMIT ?=
OFFLINE ?=
PYTHON ?= python3
export PYTHON

# The website (make site, site-check, publish-site). These lines are the only place the values are written; the scripts in
# tools/ read them from the environment and, when run without make, from these lines (tools/site-env.sh).
# Values: see book/90-reference/publishing.md and the Variables table in book/90-reference/make-targets.md.
SITE_DOMAIN ?= kits.slashbuilder.com
SITE_TITLE ?= The Kit Book
SITE_REPO_URL ?= https://github.com/slash-builder/kit-book
SITE_REPO_BRANCH ?= main
SITE_REWRITE_REPO_LINKS ?= 1
SITE_INDEXABLE ?= 0
export SITE_DOMAIN SITE_TITLE SITE_REPO_URL SITE_REPO_BRANCH SITE_REWRITE_REPO_LINKS SITE_INDEXABLE
# publish-site pushes the gh-pages branch only when PUBLISH=1 and the repository is public; otherwise it is a dry run.
PUBLISH ?=
export PUBLISH
# stranger-test (after release): the repository to clone, whether to only print the plan, which steps to run, and whether to keep the clone.
STRANGER_REPO_URL ?= https://github.com/slash-builder/kit-book
STRANGER_DRY ?=
STRANGER_STEPS ?=
STRANGER_KEEP ?=
export STRANGER_REPO_URL STRANGER_DRY STRANGER_STEPS STRANGER_KEEP

# flutter_rust_bridge_codegen is usually installed by `cargo install`, which puts it in ~/.cargo/bin; that folder is often not on
# PATH in a make shell (Homebrew's Rust does not add it). Look there too.
export PATH := $(PATH):$(or $(CARGO_HOME),$(HOME)/.cargo)/bin

# The host operating system decides which Flutter desktop target the apps are built for.
UNAME := $(shell uname -s)
ifeq ($(UNAME),Darwin)
FLUTTER_DEVICE := macos
else
FLUTTER_DEVICE := linux
endif

APPS := $(notdir $(patsubst %/,%,$(wildcard apps/*/)))

.PHONY: help all build lint fmt doctor setup fetch lock test test-fast test-integration apps app run frb \
        docs docs-catalog docs-pull docs-pull-check test-tools site site-check publish-site check-public community \
        go-public-check stranger-test linux-smoke-image linux-smoke clean clean-all

help: ## Show this list (the default)
	@echo "$(BOOK_NAME): make targets"
	@echo
	@awk 'BEGIN { FS = ":.*## " } /^[a-zA-Z0-9_-]+:.*## / { printf "  %-18s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "First time here: make doctor, then make setup, then make test-fast."
	@echo "While the Kits are private: make setup KITS=all.   More: book/90-reference/make-targets.md"

all: lint test-fast build ## Everything CI needs: lint, fast tests, then build the apps

doctor: ## Check the toolchain and say what to install (installs nothing)
	@sh tools/doctor.sh

setup: ## Doctor, fetch the Kits, fetch packages (KITS=all for private Kits, SETUP_INSTALL=1 to install tools)
	@sh tools/setup.sh

fetch: ## Only fetch the Kits listed in kits.lock into .kits/ (KITS=all for private Kits)
	@sh tools/fetch-kits.sh

lock: ## Show how the Kit pins would move, then ask before rewriting kits.lock (KIT=name for one Kit)
	@sh tools/lock.sh $(KIT)

test: ## All tests: fetched Kits, labs and apps, then integration suites that can run here
	@sh tools/test-run.sh all

test-fast: ## The same without anything that needs Docker, Redis or a running daemon
	@sh tools/test-run.sh fast

test-integration: ## Only the suites that need Docker, Redis or a daemon (skips with a message when absent)
	@sh tools/test-run.sh integration

apps: ## Build every demo app for this computer in debug mode
	@sh tools/doctor.sh --require-apps >/dev/null || { sh tools/doctor.sh --require-apps; exit 1; }
	@set -e; for a in $(APPS); do if sh tools/app-gate.sh $$a; then $(MAKE) --no-print-directory app APP=$$a; fi; done

app: ## Build one demo app: make app APP=notepad
	@test -n "$(APP)" || { echo "Say which app: make app APP=<$(APPS)>"; exit 2; }
	@test -d apps/$(APP) || { echo "No such app: $(APP). Choose from: $(APPS)"; exit 2; }
	@test -d .kits/app-context-kit || { echo "The App Context Kit is not fetched. Run: make setup (KITS=all while it is private)"; exit 2; }
	@sh tools/app-gate.sh --direct $(APP)
	@echo "==> building apps/$(APP) for $(FLUTTER_DEVICE) (debug)"
	@cd apps/$(APP) && flutter pub get >/dev/null && flutter build $(FLUTTER_DEVICE) --debug

run: ## Run one demo app on this computer: make run APP=notepad
	@test -n "$(APP)" || { echo "Say which app: make run APP=<$(APPS)>"; exit 2; }
	@test -d apps/$(APP) || { echo "No such app: $(APP). Choose from: $(APPS)"; exit 2; }
	@test -d .kits/app-context-kit || { echo "The App Context Kit is not fetched. Run: make setup (KITS=all while it is private)"; exit 2; }
	@sh tools/app-gate.sh --direct $(APP)
	@cd apps/$(APP) && flutter pub get >/dev/null && flutter run -d $(FLUTTER_DEVICE)

frb: ## Regenerate the Flutter-to-Rust bridge of every app that has one (flutter_rust_bridge_codegen)
	@sh tools/frb.sh

build: apps ## Alias for apps

lint: ## Analyse the Dart code in apps/ and labs/ and run the documentation checks
	@set -e; for d in labs/interface_candidates $(addprefix apps/,$(APPS)); do \
	  echo "==> flutter analyze $$d"; (cd $$d && flutter analyze); done
	@$(MAKE) --no-print-directory docs check-public

fmt: ## Format the Dart code in apps/ and labs/
	@dart format apps labs

docs: ## Check every relative link and heading anchor in the book and the README files
	@python3 tools/check-links.py
	@sh tools/check-make-docs.sh

docs-catalog: ## Maintainers: regenerate the Kit catalog from the registry (REGISTRY=path), then run docs and check-public
	@r="$(REGISTRY)"; [ -n "$$r" ] || r="$$KITS_REGISTRY"; \
	  [ -n "$$r" ] || { echo "Say where the Kit registry (kits.yaml) is: make docs-catalog REGISTRY=/path/to/kits.yaml, or set KITS_REGISTRY."; exit 2; }; \
	  $(PYTHON) tools/gen-catalog.py --registry "$$r" $(if $(REGISTRY_COMMIT),--registry-commit $(REGISTRY_COMMIT)) $(if $(OFFLINE),--offline)
	@$(MAKE) --no-print-directory docs check-public

docs-pull: ## Maintainers: pull each Kit's own reference docs (from .kits/) into the book, then run docs and check-public
	@python3 tools/pull-docs.py
	@$(MAKE) --no-print-directory docs check-public

docs-pull-check: ## Maintainers: fail if the pulled reference pages differ from a fresh pull (skips Kits not in .kits/)
	@python3 tools/pull-docs.py --check

test-tools: ## Run the unit tests of the maintainer tools in tools/ (the catalog tests skip without PyYAML)
	@$(PYTHON) -m unittest discover -s tools/tests -v

site: ## Build the book as a website with mdBook, if installed (output in build/site; SITE_INDEXABLE=1 at publish time)
	@sh tools/site.sh

site-check: ## Check the built website: links, CNAME and .nojekyll, noindex switch, vendored diagram script (run make site first)
	@python3 tools/site-check.py

publish-site: ## Maintainers: build and check the site, commit it to a local gh-pages branch; push only with PUBLISH=1 and a public repo
	@rm -rf build/site build/site-publish
	@sh tools/site.sh
	@python3 tools/site-check.py
	@sh tools/publish-site.sh

check-public: ## Scan the whole tree for anything that must not be public (names, paths, ids, secrets)
	@sh tools/check-public.sh

community: ## Maintainers: render CODE_OF_CONDUCT.md and SECURITY.md from tools/community/ and the contacts in tools/contacts.conf
	@python3 tools/render-community.py

go-public-check: ## Maintainers: the launch gate. A read-only checklist (ok / warn / FAIL) of everything to settle before going public; exits 1 on a FAIL
	@sh tools/go-public-check.sh

stranger-test: ## Maintainers, AFTER release: clone the public repository with no GitHub login and run doctor, setup, test-fast (STRANGER_DRY=1 prints the plan)
	@sh tools/stranger-test.sh

linux-smoke-image: ## Build the Docker image for linux-smoke (Ubuntu, Flutter 3.41.9 and Rust pinned, Xvfb); slow once, then cached
	@sh tools/linux-smoke.sh image

linux-smoke: ## Build every demo app for Linux in a container and launch it under a virtual display (LINUX_SMOKE_APPS="a b" for some); results in build/linux-smoke/
	@sh tools/linux-smoke.sh run

clean: ## Remove build output, test logs and the website (keeps the fetched Kits)
	@rm -rf build
	@for d in $(addprefix apps/,$(APPS)) labs/interface_candidates; do rm -rf $$d/build $$d/.dart_tool $$d/rust/target; done
	@rm -rf .kits/*/rust/target
	@echo "cleaned build output"

clean-all: clean ## clean, and also delete the fetched Kits in .kits/
	@rm -rf .kits
	@echo "removed .kits/"

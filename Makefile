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
        docs docs-catalog site check-public clean clean-all

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
	@set -e; for a in $(APPS); do $(MAKE) --no-print-directory app APP=$$a; done

app: ## Build one demo app: make app APP=notepad
	@test -n "$(APP)" || { echo "Say which app: make app APP=<$(APPS)>"; exit 2; }
	@test -d apps/$(APP) || { echo "No such app: $(APP). Choose from: $(APPS)"; exit 2; }
	@test -d .kits/application-kit || { echo "The Application Kit is not fetched. Run: make setup (KITS=all while it is private)"; exit 2; }
	@test ! -d apps/$(APP)/rust || test -d .kits/storage-kit || { echo "apps/$(APP) has a Rust core that builds against the Storage Kit, which is not fetched. Run: make setup KITS=all"; exit 2; }
	@echo "==> building apps/$(APP) for $(FLUTTER_DEVICE) (debug)"
	@cd apps/$(APP) && flutter pub get >/dev/null && flutter build $(FLUTTER_DEVICE) --debug

run: ## Run one demo app on this computer: make run APP=notepad
	@test -n "$(APP)" || { echo "Say which app: make run APP=<$(APPS)>"; exit 2; }
	@test -d apps/$(APP) || { echo "No such app: $(APP). Choose from: $(APPS)"; exit 2; }
	@test -d .kits/application-kit || { echo "The Application Kit is not fetched. Run: make setup (KITS=all while it is private)"; exit 2; }
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

docs-catalog: ## Hook for the generated Kit catalog (not implemented yet; it will list EVERY Kit in the registry)
	@echo "catalog generation not implemented yet"
	@echo "rule for when it is: the catalog lists EVERY Kit in the registry, public, private, banked and archived, as status cards;"
	@echo "a repository link appears only for a public Kit; this repository is the book, not a Kit, and is never listed."

site: ## Build the book as an HTML website with mdBook, if installed (output in build/site)
	@sh tools/site.sh

check-public: ## Scan the whole tree for anything that must not be public (names, paths, ids, secrets)
	@sh tools/check-public.sh

clean: ## Remove build output, test logs and the website (keeps the fetched Kits)
	@rm -rf build
	@for d in $(addprefix apps/,$(APPS)) labs/interface_candidates; do rm -rf $$d/build $$d/.dart_tool $$d/rust/target; done
	@rm -rf .kits/*/rust/target
	@echo "cleaned build output"

clean-all: clean ## clean, and also delete the fetched Kits in .kits/
	@rm -rf .kits
	@echo "removed .kits/"

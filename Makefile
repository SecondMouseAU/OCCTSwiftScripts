PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
BIN     = occtkit
BUILD   = .build/release/$(BIN)

# The verb list comes from the built binary (`occtkit --verbs`, backed by
# Registry.all) rather than a second hand-maintained copy here. A duplicated
# list had already drifted and silently dropped graph-select from `make install`.
#
# Recursive `=`, not `:=`, so this only runs when `install` expands its recipe
# (by which point `install: $(BUILD)` has forced a build), not on `make help`.
# stderr is deliberately not suppressed: a failure here must be visible, and the
# install recipe guards against an empty result rather than linking nothing.
VERBS = $(shell $(BUILD) --verbs)

.PHONY: build install uninstall clean help recipe recipes-test recipes-render verb-check

help:
	@echo "Targets:"
	@echo "  build              swift build -c release"
	@echo "  install [PREFIX=]  copy occtkit + verb symlinks to \$$(PREFIX)/bin (default /usr/local)"
	@echo "  uninstall [PREFIX=]"
	@echo "  clean              swift package clean"
	@echo "  recipe NAME=<n>    scaffold recipes/NN-<n>/ (auto-numbered)"
	@echo "  recipes-test       run + smoke-test every recipe (occtkit run + metrics)"
	@echo "  recipes-render     regenerate each recipe's output.png (skips if no Metal)"
	@echo "  verb-check         assert the verb inventory is single-sourced + consistent"

recipe:
	@Scripts/new-recipe.sh "$(NAME)"

recipes-test:
	@Scripts/recipe-check.sh

recipes-render:
	@Scripts/render-recipe.sh

verb-check:
	@Scripts/verb-check.sh

build:
	swift build -c release

$(BUILD): build

install: $(BUILD)
	@test -n "$(VERBS)" || { \
		echo "error: '$(BUILD) --verbs' produced no verb names; refusing to install"; \
		echo "       (an occtkit older than --verbs prints help and exits non-zero here)"; \
		exit 1; \
	}
	@install -d $(BINDIR)
	install -m 0755 $(BUILD) $(BINDIR)/$(BIN)
	@for v in $(VERBS); do \
		case "$$v" in \
			*[!a-z0-9-]*|"") echo "error: unexpected verb name '$$v'"; exit 1 ;; \
		esac; \
		ln -sf $(BIN) $(BINDIR)/$$v; \
		echo "linked $(BINDIR)/$$v -> $(BIN)"; \
	done
	@echo "Installed $(words $(VERBS)) verb symlinks to $(BINDIR)/$(BIN)"

uninstall:
	@# Remove every symlink in BINDIR that points at the occtkit binary, rather
	@# than replaying a verb list. This still works when the build tree is gone,
	@# and it cleans up verbs removed from Registry.all since install time.
	@# Errors are not suppressed: an unwritable BINDIR must not report success.
	@if [ -d $(BINDIR) ]; then \
		find $(BINDIR) -maxdepth 1 -type l -lname '$(BIN)' -exec rm -f {} + ; \
	fi
	@rm -f $(BINDIR)/$(BIN)
	@echo "Removed $(BIN) and verb symlinks from $(BINDIR)"

clean:
	swift package clean

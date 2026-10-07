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
#
# Recursive expansion means `install` invokes the binary three times: once for the
# `test -n` guard, once for the `for` loop, once for `$(words ...)`. That is a
# deliberate trade, three fast process launches against keeping each line readable;
# hoisting into a shell variable would collapse the recipe into one opaque block.
VERBS = $(shell $(BUILD) --verbs)

.PHONY: build install uninstall clean help recipe recipes-test recipes-render verb-check run-identity-check test serve-check policy-check ci

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
	@echo "  run-identity-check assert occtkit run's workspace identity matches its dep path"
	@echo "  test               swift test (unit + in-process verb tests)"
	@echo "  serve-check        assert --serve answers one envelope per request and recovers from a failure"
	@echo "  policy-check       assert okf/policies, okf/index.md and CLAUDE.md agree"
	@echo "  ci                 everything CI blocks on, locally: test, verb-check, run-identity-check, serve-check, policy-check, recipes-test"

recipe:
	@Scripts/new-recipe.sh "$(NAME)"

recipes-test:
	@Scripts/recipe-check.sh

recipes-render:
	@Scripts/render-recipe.sh

verb-check:
	@Scripts/verb-check.sh

run-identity-check: $(BUILD)
	@OCCTKIT=$(BUILD) Scripts/run-identity-check.sh

test:
	swift test

serve-check: $(BUILD)
	@OCCTKIT=$(BUILD) Scripts/serve-check.sh

policy-check:
	@Scripts/policy-check.sh

# Mirrors the blocking CI jobs that need no extra tooling (swift-format and SwiftLint are
# installed separately; see .github/workflows/code-style.yml).
ci: test verb-check run-identity-check serve-check policy-check recipes-test

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

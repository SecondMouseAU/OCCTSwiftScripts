PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
BIN     = occtkit
BUILD   = .build/release/$(BIN)

# The verb list comes from the built binary (`occtkit --verbs`, backed by
# Registry.all) rather than a second hand-maintained copy here. A duplicated
# list had already drifted and silently dropped graph-select from `make install`.
VERBS = $(shell $(BUILD) --verbs 2>/dev/null)

.PHONY: build install uninstall clean help recipe recipes-test recipes-render

help:
	@echo "Targets:"
	@echo "  build              swift build -c release"
	@echo "  install [PREFIX=]  copy occtkit + verb symlinks to \$$(PREFIX)/bin (default /usr/local)"
	@echo "  uninstall [PREFIX=]"
	@echo "  clean              swift package clean"
	@echo "  recipe NAME=<n>    scaffold recipes/NN-<n>/ (auto-numbered)"
	@echo "  recipes-test       run + smoke-test every recipe (occtkit run + metrics)"
	@echo "  recipes-render     regenerate each recipe's output.png (skips if no Metal)"

recipe:
	@Scripts/new-recipe.sh "$(NAME)"

recipes-test:
	@Scripts/recipe-check.sh

recipes-render:
	@Scripts/render-recipe.sh

build:
	swift build -c release

$(BUILD): build

install: $(BUILD)
	@install -d $(BINDIR)
	install -m 0755 $(BUILD) $(BINDIR)/$(BIN)
	@for v in $(VERBS); do \
		ln -sf $(BIN) $(BINDIR)/$$v; \
		echo "linked $(BINDIR)/$$v -> $(BIN)"; \
	done
	@echo "Installed to $(BINDIR)/$(BIN)"

uninstall:
	@# Remove every symlink in BINDIR that points at the occtkit binary, rather
	@# than replaying a verb list. This still works when the build tree is gone,
	@# and it cleans up verbs removed from Registry.all since install time.
	@find $(BINDIR) -maxdepth 1 -type l -lname '$(BIN)' -exec rm -f {} + 2>/dev/null || true
	@rm -f $(BINDIR)/$(BIN)
	@echo "Removed $(BIN) and verb symlinks from $(BINDIR)"

clean:
	swift package clean

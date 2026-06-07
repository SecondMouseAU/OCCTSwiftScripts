PREFIX ?= /usr/local
BINDIR  = $(PREFIX)/bin
BIN     = occtkit
BUILD   = .build/release/$(BIN)

VERBS = run graph-validate graph-compact graph-dedup graph-query graph-ml feature-recognize dxf-export drawing-export reconstruct compose-sheet-metal transform boolean pattern metrics query-topology measure-distance load-brep import check-thickness analyze-clearance heal mesh render-preview inspect-assembly set-metadata simplify-mesh

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
	@rm -f $(BINDIR)/$(BIN)
	@for v in $(VERBS); do rm -f $(BINDIR)/$$v; done
	@echo "Removed $(BIN) and verb symlinks from $(BINDIR)"

clean:
	swift package clean

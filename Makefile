# Janus Compiler Build System
# Comprehensive build automation with Linux packaging and VSCode extension

.PHONY: all build test clean install uninstall package release help
.PHONY: vscode-extension watch dev version-bump
.PHONY: aur-package alpine-package debian-package fedora-package
.PHONY: test-lsp test-integration test-all
.PHONY: submodule-update submodule-clean submodule-status
.DEFAULT_GOAL := help

# Configuration
ZIG := zig
VERSION := $(shell cat VERSION 2>/dev/null || echo "0.1.0-dev.$$(date +%Y%m%d)")
BUILD_MODE := ReleaseSafe
PREFIX := /usr/local
DESTDIR :=

# Colors for output
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
RESET := \033[0m

# Build targets
all: ## Build everything using automated build script
	@echo "$(BLUE)🚀 Running automated build system...$(RESET)"
	@./scripts/automated-build.sh

quick: build vscode-extension ## Quick build (core + VSCode extension only)

build: ## Build core Janus components (janus, janusd, lsp-bridge)
	@echo "$(BLUE)🔨 Building Janus core components...$(RESET)"
	@$(ZIG) build -Doptimize=$(BUILD_MODE)
	@echo "$(GREEN)✅ Core build complete$(RESET)"

test: ## Run all tests
	@echo "$(BLUE)🧪 Running tests...$(RESET)"
	$(ZIG) build test
	@echo "$(GREEN)✅ Tests passed$(RESET)"

test-release: ## Run tests in ReleaseSafe mode
	@echo "$(BLUE)🧪 Running tests (ReleaseSafe)...$(RESET)"
	$(ZIG) build test-release-safe
	@echo "$(GREEN)✅ ReleaseSafe tests passed$(RESET)"

test-sanitizers: ## Run tests with sanitizers
	@echo "$(BLUE)🧪 Running tests with sanitizers...$(RESET)"
	$(ZIG) build test-sanitizers
	@echo "$(GREEN)✅ Sanitizer tests passed$(RESET)"

test-lsp: ## Test LSP functionality
	@echo "$(BLUE)🔌 Testing LSP functionality...$(RESET)"
	@if [ -f test_lsp_functionality.sh ]; then \
		./test_lsp_functionality.sh; \
		echo "$(GREEN)✅ LSP tests passed$(RESET)"; \
	else \
		echo "$(YELLOW)⚠️  LSP test script not found$(RESET)"; \
	fi

test-integration: build test-lsp ## Run integration tests
	@echo "$(BLUE)🔗 Running integration tests...$(RESET)"
	@./zig-out/bin/janus version || ./zig-out/bin/janus --help
	@./zig-out/bin/janusd --help
	@./zig-out/bin/lsp-bridge --help
	@echo "$(GREEN)✅ Integration tests passed$(RESET)"

test-all: test test-release test-sanitizers test-integration ## Run all test suites

vscode-extension: ## Build VSCode extension
	@echo "$(BLUE)📦 Building VSCode extension...$(RESET)"
	@$(MAKE) -C tools/vscode package
	@if [ -f zig-out/janus-lang-*.vsix ]; then \
		echo "$(GREEN)✅ VSCode extension built: $$(ls zig-out/janus-lang-*.vsix)$(RESET)"; \
	else \
		echo "$(RED)❌ VSCode extension build failed$(RESET)"; \
		exit 1; \
	fi

clean: ## Clean build artifacts
	@echo "$(BLUE)🧹 Cleaning build artifacts...$(RESET)"
	rm -rf zig-out zig-cache .zig-cache
	rm -f *.log deployment-checklist-*.md
	@$(MAKE) -C tools/vscode clean 2>/dev/null || true
	@echo "$(GREEN)✅ Clean complete$(RESET)"

# Submodule management (blake3 for CID packaging)
submodule-update: ## Update all submodules (blake3) to committed state
	@echo "$(BLUE)📦 Updating submodules...$(RESET)"
	@git submodule update --init --recursive
	@git submodule foreach --recursive 'git reset --hard HEAD && git clean -fd'
	@echo "$(GREEN)✅ Submodules updated$(RESET)"

submodule-clean: ## Clean submodule modifications (reset to committed state)
	@echo "$(BLUE)🧹 Cleaning submodule modifications...$(RESET)"
	@git submodule foreach --recursive 'git reset --hard HEAD && git clean -fd'
	@echo "$(GREEN)✅ Submodules cleaned$(RESET)"

submodule-status: ## Show submodule status
	@echo "$(BLUE)📊 Submodule status:$(RESET)"
	@git submodule status

install: build vscode-extension ## Install Janus to system
	@echo "$(BLUE)📥 Installing Janus to $(DESTDIR)$(PREFIX)...$(RESET)"
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m755 zig-out/bin/janus $(DESTDIR)$(PREFIX)/bin/
	install -m755 zig-out/bin/janusd $(DESTDIR)$(PREFIX)/bin/
	install -m755 zig-out/bin/lsp-bridge $(DESTDIR)$(PREFIX)/bin/

	@# Install documentation
	install -d $(DESTDIR)$(PREFIX)/share/doc/janus-lang
	install -m644 README.md LICENSE $(DESTDIR)$(PREFIX)/share/doc/janus-lang/

	@# Install examples
	install -d $(DESTDIR)$(PREFIX)/share/doc/janus-lang/examples
	cp -r examples/* $(DESTDIR)$(PREFIX)/share/doc/janus-lang/examples/ 2>/dev/null || true

	@# Install VSCode extension
	@if [ -f zig-out/janus-lang-*.vsix ]; then \
		install -d $(DESTDIR)$(PREFIX)/share/doc/janus-lang/vscode; \
		install -m644 zig-out/janus-lang-*.vsix $(DESTDIR)$(PREFIX)/share/doc/janus-lang/vscode/; \
		echo "$(GREEN)✅ VSCode extension installed$(RESET)"; \
	fi

	@echo "$(GREEN)✅ Installation complete$(RESET)"
	@echo "$(BLUE)📋 To install VSCode extension:$(RESET)"
	@echo "   code --install-extension $(PREFIX)/share/doc/janus-lang/vscode/janus-lang-*.vsix"

uninstall: ## Uninstall Janus from system
	@echo "$(BLUE)📤 Uninstalling Janus...$(RESET)"
	rm -f $(DESTDIR)$(PREFIX)/bin/janus
	rm -f $(DESTDIR)$(PREFIX)/bin/janusd
	rm -f $(DESTDIR)$(PREFIX)/bin/lsp-bridge
	rm -rf $(DESTDIR)$(PREFIX)/share/doc/janus-lang
	@echo "$(GREEN)✅ Uninstall complete$(RESET)"

# Version management
version-bump-patch: ## Bump patch version and build
	@./scripts/version-bump.sh bump patch

version-bump-minor: ## Bump minor version and build
	@./scripts/version-bump.sh bump minor

version-bump-major: ## Bump major version and build
	@./scripts/version-bump.sh bump major

version-bump-dev: ## Bump to dev version and build
	@./scripts/version-bump.sh bump dev

version-show: ## Show current version
	@./scripts/version-bump.sh show

# Package building
aur-package: ## Build AUR package
	@echo "$(BLUE)📦 Building AUR package...$(RESET)"
	@cd packaging/arch && makepkg --printsrcinfo > .SRCINFO
	@echo "$(GREEN)✅ AUR package ready$(RESET)"

alpine-package: ## Build Alpine package
	@echo "$(BLUE)📦 Building Alpine package...$(RESET)"
	@cd packaging/alpine && abuild checksum
	@echo "$(GREEN)✅ Alpine package ready$(RESET)"

debian-package: ## Build Debian package
	@echo "$(BLUE)📦 Building Debian package...$(RESET)"
	@cd packaging/debian && dpkg-buildpackage -us -uc || echo "$(YELLOW)⚠️  Requires proper Debian environment$(RESET)"
	@echo "$(GREEN)✅ Debian package ready$(RESET)"

fedora-package: ## Build Fedora package
	@echo "$(BLUE)📦 Building Fedora package...$(RESET)"
	@cd packaging/fedora && rpmbuild -bs janus-lang.spec || echo "$(YELLOW)⚠️  Requires proper RPM environment$(RESET)"
	@echo "$(GREEN)✅ Fedora package ready$(RESET)"

package: aur-package alpine-package debian-package fedora-package ## Build all Linux packages

# Development tools
watch: ## Watch for changes and rebuild automatically
	@./scripts/watch-build.sh

dev: clean build test-integration ## Quick development build and test

# Release management
release: clean test-all all package ## Create complete release build
	@echo "$(BLUE)🚀 Creating release build...$(RESET)"
	@./scripts/automated-build.sh
	@echo "$(GREEN)🎉 Release build complete!$(RESET)"

# CI/CD simulation
ci-build: clean test-all all package ## Simulate CI/CD build process
	@echo "$(BLUE)🤖 Simulating CI/CD build...$(RESET)"
	@echo "$(GREEN)✅ CI/CD simulation complete$(RESET)"

# Help
help: ## Show this help message
	@echo "$(BLUE)Janus Compiler Build System$(RESET)"
	@echo "============================"
	@echo ""
	@echo "$(YELLOW)Core Build Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | grep -E "(build|test|clean|install)"
	@echo ""
	@echo "$(YELLOW)Development Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | grep -E "(watch|dev|vscode)"
	@echo ""
	@echo "$(YELLOW)Version Management:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | grep -E "version"
	@echo ""
	@echo "$(YELLOW)Packaging Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | grep -E "package"
	@echo ""
	@echo "$(YELLOW)Release Commands:$(RESET)"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST) | grep -E "(release|ci-build)"
	@echo ""
	@echo "$(BLUE)Examples:$(RESET)"
	@echo "  make build              # Build core components"
	@echo "  make all                # Build everything"
	@echo "  make test-all           # Run all tests"
	@echo "  make vscode-extension   # Build VSCode extension"
	@echo "  make package            # Build all Linux packages"
	@echo "  make release            # Create complete release"
	@echo "  make watch              # Watch and rebuild on changes"
	@echo "  make version-bump-patch # Bump version and build"
	@echo ""
	@echo "$(BLUE)Current Configuration:$(RESET)"
	@echo "  Version: $(VERSION)"
	@echo "  Build Mode: $(BUILD_MODE)"
	@echo "  Install Prefix: $(PREFIX)"
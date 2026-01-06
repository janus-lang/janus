#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Install Janus Git Hooks
# Sets up pre-commit and pre-push hooks for quality enforcement

set -e

echo "🪝 Installing Janus Git Hooks"
echo "============================="

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    echo "❌ Not in a git repository"
    exit 1
fi

# Check if hooks directory exists
if [ ! -d ".githooks" ]; then
    echo "❌ .githooks directory not found"
    exit 1
fi

# Install hooks
echo "📋 Installing hooks..."

# Pre-commit hook
if [ -f ".githooks/pre-commit" ]; then
    cp .githooks/pre-commit .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    echo "✅ pre-commit hook installed"
else
    echo "⚠️ pre-commit hook not found"
fi

# Pre-push hook
if [ -f ".githooks/pre-push" ]; then
    cp .githooks/pre-push .git/hooks/pre-push
    chmod +x .git/hooks/pre-push
    echo "✅ pre-push hook installed"
else
    echo "⚠️ pre-push hook not found"
fi

# Configure git to use hooks directory (alternative approach)
git config core.hooksPath .githooks

echo ""
echo "🎉 Git hooks installed successfully!"
echo ""
echo "📋 Installed hooks:"
echo "  - pre-commit: Format, license, build, and test validation"
echo "  - pre-push: Comprehensive quality gate before remote push"
echo ""
echo "💡 To bypass hooks (emergency only):"
echo "  git commit --no-verify"
echo "  git push --no-verify"
echo ""
echo "🔧 To uninstall hooks:"
echo "  git config --unset core.hooksPath"
echo "  rm .git/hooks/pre-commit .git/hooks/pre-push"
echo ""

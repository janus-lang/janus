#!/bin/bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/bin/bash
#!/bin/bash
# Setup script for license header automation across different Git platforms
# Usage: ./scripts/setup-license-automation.sh [--platform github|forgejo|gitea|auto]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM=""

# Function to detect Git hosting platform
detect_platform() {
    local detected=""

    # Check for existing CI/CD directories
    if [[ -d ".github" ]]; then
        detected="github"
    elif [[ -d ".forgejo" ]]; then
        detected="forgejo"
    elif [[ -d ".gitea" ]]; then
        detected="gitea"
    fi

    # Check remote URL for additional hints
    if [[ -z "$detected" ]]; then
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null || echo "")

        if [[ "$remote_url" == *"github.com"* ]]; then
            detected="github"
        elif [[ "$remote_url" == *"forgejo"* ]]; then
            detected="forgejo"
        elif [[ "$remote_url" == *"gitea"* ]]; then
            detected="gitea"
        fi
    fi

    echo "$detected"
}

# Function to setup GitHub Actions
setup_github() {
    echo -e "${BLUE}🔧 Setting up GitHub Actions integration...${NC}"

    mkdir -p .github/workflows

    if [[ -f ".github/workflows/license-check.yml" ]]; then
        echo -e "${GREEN}✅ GitHub Actions workflow already exists${NC}"
    else
        echo -e "${YELLOW}⚠️  GitHub Actions workflow not found${NC}"
        echo "Expected file: .github/workflows/license-check.yml"
        echo "This should have been created during initial setup."
    fi

    echo ""
    echo "GitHub Actions features:"
    echo "  ✅ Automatic PR validation"
    echo "  ✅ Full repository auditing"
    echo "  ✅ Compliance report generation"
    echo "  ✅ Automatic PR commenting on failures"
    echo "  ✅ Artifact upload for reports"
}

# Function to setup Forgejo
setup_forgejo() {
    echo -e "${BLUE}🔧 Setting up Forgejo integration...${NC}"

    mkdir -p .forgejo/workflows

    if [[ -f ".forgejo/workflows/license-check.yml" ]]; then
        echo -e "${GREEN}✅ Forgejo workflow exists${NC}"
    else
        echo -e "${YELLOW}⚠️  Forgejo workflow not found${NC}"
        echo "Expected file: .foro/workflows/license-check.yml"
        echo "This should have been created during setup."
    fi

    echo ""
    echo "Forgejo features:"
    echo "  ✅ Automatic PR validation"
    echo "  ✅ Full repository auditing"
    echo "  ✅ Compliance report generation"
    echo "  ✅ Artifact upload for reports"
    echo "  ⚠️  PR commenting requires manual setup (see workflow comments)"
}

# Function to setup Gitea
setup_gitea() {
    echo -e "${BLUE}🔧 Setting up Gitea integration...${NC}"

    mkdir -p .gitea/workflows

    if [[ -f ".gitea/workflows/license-check.yml" ]]; then
        echo -e "${GREEN}✅ Gitea workflow exists${NC}"
    else
        echo -e "${YELLOW}⚠️  Gitea workflow not found${NC}"
        echo "Expected file: .gitea/workflows/license-check.yml"
        echo "This should have been created during setup."
    fi

    echo ""
    echo "Gitea features:"
    echo "  ✅ Automatic PR validation"
    echo "  ✅ Full repository auditing"
    echo "  ✅ Compliance report generation"
    echo "  ✅ Artifact upload for reports"
    echo "  🔧 PR commenting via API (requires GITEA_TOKEN)"
    echo ""
    echo "To enable automatic PR commenting:"
    echo "  1. Create a Gitea access token with repository permissions"
    echo "  2. Add it as a secret named 'GITEA_TOKEN' in your repository settings"
}

# Function to install pre-commit hook
install_pre_commit_hook() {
    echo -e "${BLUE}🔧 Installing pre-commit hook...${NC}"

    if scripts/pre-commit-license-check.sh --install; then
        echo -e "${GREEN}✅ Pre-commit hook installed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to install pre-commit hook${NC}"
        return 1
    fi
}

# Function to validate setup
validate_setup() {
    echo -e "${BLUE}🔍 Validating license automation setup...${NC}"
    echo ""

    local issues=0

    # Check scripts
    echo "Checking automation scripts:"
    local scripts=(
        "scripts/pre-commit-license-check.sh"
        "scripts/add-license-headers.sh"
        "scripts/license-compliance-scan.sh"
        "scripts/validate-license-headers.sh"
    )

    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            echo -e "  ✅ $script"
        else
            echo -e "  ❌ $script (missing or not executable)"
            issues=$((issues + 1))
        fi
    done

    echo ""

    # Check CI/CD workflows
    echo "Checking CI/CD workflows:"
    if [[ -f ".github/workflows/license-check.yml" ]]; then
        echo -e "  ✅ GitHub Actions: .github/workflows/license-check.yml"
    fi

    if [[ -f ".forgejo/workflows/license-check.yml" ]]; then
        echo -e "  ✅ Forgejo: .forgejo/workflows/license-check.yml"
    fi

    if [[ -f ".gitea/workflows/license-check.yml" ]]; then
        echo -e "  ✅ Gitea: .gitea/workflows/license-check.yml"
    fi

    echo ""

    # Check pre-commit hook
    echo "Checking pre-commit hook:"
    if [[ -f ".git/hooks/pre-commit" ]]; then
        echo -e "  ✅ Pre-commit hook installed"
    else
        echo -e "  ⚠️  Pre-commit hook not installed (run with --install-hook)"
    fi

    echo ""

    # Check documentation
    echo "Checking documentation:"
    local docs=(
        "docs/LICENSE-HEADERS.md"
        "docs/LICENSE-AUTOMATION-USAGE.md"
        "docs/TODO-LICENSE-AUTOMATION.md"
    )

    for doc in "${docs[@]}"; do
        if [[ -f "$doc" ]]; then
            echo -e "  ✅ $doc"
        else
            echo -e "  ❌ $doc (missing)"
            issues=$((issues + 1))
        fi
    done

    echo ""

    if [[ $issues -eq 0 ]]; then
        echo -e "${GREEN}✅ License automation setup is complete and valid${NC}"
        return 0
    else
        echo -e "${RED}❌ Found $issues issues in license automation setup${NC}"
        return 1
    fi
}

# Function to show platform-specific instructions
show_platform_instructions() {
    local platform="$1"

    echo ""
    echo -e "${BLUE}📋 Platform-specific setup instructions for $platform:${NC}"
    echo ""

    case "$platform" in
        "github")
            echo "GitHub Actions setup:"
            echo "  1. The workflow will run automatically on PRs and pushes"
            echo "  2. No additional configuration required"
            echo "  3. Check the 'Actions' tab in your GitHub repository"
            echo "  4. Workflow file: .github/workflows/license-check.yml"
            ;;
        "forgejo")
            echo "Forgejo setup:"
            echo "  1. Ensure Forgejo Actions is enabled in your instance"
            echo "  2. The workflow will run automatically on PRs and pushes"
            echo "  3. Check the 'Actions' tab in your Forgejo repository"
            echo "  4. Workflow file: .forgejo/workflows/license-check.yml"
            echo "  5. PR commenting requires manual setup (see workflow file)"
            ;;
        "gitea")
            echo "Gitea setup:"
            echo "  1. Ensure Gitea Actions is enabled (Gitea 1.19+)"
            echo "  2. The workflow will run automatically on PRs and pushes"
            echo "  3. Check the 'Actions' tab in your Gitea repository"
            echo "  4. Workflow file: .gitea/workflows/license-check.yml"
            echo ""
            echo "For automatic PR commenting:"
            echo "  1. Go to Settings → Secrets in your repository"
            echo "  2. Add a secret named 'GITEA_TOKEN'"
            echo "  3. Value should be a Gitea access token with repo permissions"
            ;;
    esac

    echo ""
    echo "Common next steps:"
    echo "  1. Test the pre-commit hook: make a commit with missing headers"
    echo "  2. Test the CI workflow: create a PR with license header violations"
    echo "  3. Run compliance scan: ./scripts/license-compliance-scan.sh"
    echo "  4. Read the usage guide: docs/LICENSE-AUTOMATION-USAGE.md"
}

# Function to show help
show_help() {
    cat << EOF
License Header Automation Setup

Usage:
  $0 [OPTIONS]

Options:
  --platform PLATFORM   Specify platform: github, forgejo, gitea, or auto (default: auto)
  --install-hook        Install pre-commit hook
  --validate           Validate current setup
  --help               Show this help message

Examples:
  $0                          # Auto-detect platform and show status
  $0 --platform forgejo      # Setup for Forgejo specifically
  $0 --install-hook          # Install pre-commit hook
  $0 --validate              # Validate current setup

Supported Platforms:
  - GitHub (github.com)
  - Forgejo (self-hosted)
  - Gitea (gitea.com or self-hosted)

The script will:
  1. Detect your Git hosting platform
  2. Validate existing automation setup
  3. Provide platform-specific instructions
  4. Optionally install pre-commit hooks

See docs/LICENSE-AUTOMATION-USAGE.md for complete usage guide.
EOF
}

# Parse command line arguments
INSTALL_HOOK=false
VALIDATE_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            if [[ "$PLATFORM" != "github" && "$PLATFORM" != "forgejo" && "$PLATFORM" != "gitea" && "$PLATFORM" != "auto" ]]; then
                echo -e "${RED}❌ Invalid platform: $PLATFORM${NC}"
                echo "Valid platforms: github, forgejo, gitea, auto"
                exit 1
            fi
            shift 2
            ;;
        --install-hook)
            INSTALL_HOOK=true
            shift
            ;;
        --validate)
            VALIDATE_ONLY=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}❌ Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main execution
main() {
    cd "$REPO_ROOT"

    echo -e "${GREEN}🚀 Janus License Header Automation Setup${NC}"
    echo ""

    # Detect platform if not specified
    if [[ "$PLATFORM" == "auto" || -z "$PLATFORM" ]]; then
        PLATFORM=$(detect_platform)
        if [[ -z "$PLATFORM" ]]; then
            PLATFORM="unknown"
        fi
    fi

    echo "Detected/Selected platform: $PLATFORM"
    echo ""

    # Validate setup if requested
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        validate_setup
        exit $?
    fi

    # Install pre-commit hook if requested
    if [[ "$INSTALL_HOOK" == "true" ]]; then
        install_pre_commit_hook
        echo ""
    fi

    # Setup platform-specific configuration
    case "$PLATFORM" in
        "github")
            setup_github
            ;;
        "forgejo")
            setup_forgejo
            ;;
        "gitea")
            setup_gitea
            ;;
        "unknown")
            echo -e "${YELLOW}⚠️  Could not detect Git hosting platform${NC}"
            echo "Available workflows:"
            [[ -f ".github/workflows/license-check.yml" ]] && echo "  ✅ GitHub Actions: .github/workflows/license-check.yml"
            [[ -f ".forgejo/workflows/license-check.yml" ]] && echo "  ✅ Forgejo: .forgejo/workflows/license-check.yml"
            [[ -f ".gitea/workflows/license-check.yml" ]] && echo "  ✅ Gitea: .gitea/workflows/license-check.yml"
            echo ""
            echo "Use --platform to specify your platform explicitly"
            ;;
    esac

    # Validate setup
    echo ""
    validate_setup

    # Show platform-specific instructions
    if [[ "$PLATFORM" != "unknown" ]]; then
        show_platform_instructions "$PLATFORM"
    fi

    echo ""
    echo -e "${GREEN}🎉 License header automation setup complete!${NC}"
    echo ""
    echo "Quick start:"
    echo "  1. Install pre-commit hook: ./scripts/setup-license-automation.sh --install-hook"
    echo "  2. Add missing headers: ./scripts/add-license-headers.sh --dry-run"
    echo "  3. Read usage guide: docs/LICENSE-AUTOMATION-USAGE.md"
}

# Run main function
main "$@"

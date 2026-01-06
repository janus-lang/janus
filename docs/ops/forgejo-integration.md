<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Forgejo/Gitea Integration Guide

This guide covers the license header automation integration with Forgejo and Gitea platforms.

## 🎯 **Overview**

The Janus license header automation system now supports three major Git hosting platforms:
- **GitHub** (github.com) - Full automation with GitHub Actions
- **Forgejo** (self-hosted) - Full automation with Forgejo Actions
- **Gitea** (gitea.com or self-hosted) - Full automation with Gitea Actions

## 🚀 **Quick Setup**

```bash
# Auto-detect your platform and setup
./scripts/setup-license-automation.sh --install-hook

# Or specify your platform explicitly
./scripts/setup-license-automation.sh --platform forgejo --install-hook
./scripts/setup-license-automation.sh --platform gitea --install-hook
```

## 📋 **Platform-Specific Features**

### GitHub Actions
- ✅ **File**: `.github/workflows/license-check.yml`
- ✅ **PR Validation**: Automatic checking of changed files
- ✅ **PR Commenting**: Automatic failure notifications
- ✅ **Audit Reports**: Comprehensive compliance reports
- ✅ **Artifact Upload**: Report storage and download
- ✅ **Setup**: Zero configuration required

### Forgejo Actions
- ✅ **File**: `.forgejo/workflows/license-check.yml`
- ✅ **PR Validation**: Automatic checking of changed files
- ⚠️ **PR Commenting**: Manual setup required (see workflow file)
- ✅ **Audit Reports**: Comprehensive compliance reports
- ✅ **Artifact Upload**: Report storage and download
- 🔧 **Setup**: Requires Forgejo Actions enabled

### Gitea Actions
- ✅ **File**: `.gitea/workflows/license-check.yml`
- ✅ **PR Validation**: Automatic checking of changed files
- 🔧 **PR Commenting**: API-based with GITEA_TOKEN
- ✅ **Audit Reports**: Comprehensive compliance reports
- ✅ **Artifact Upload**: Report storage and download
- 🔧 **Setup**: Requires Gitea 1.19+ with Actions enabled

## 🔧 **Forgejo Setup**

### Prerequisites
1. **Forgejo Actions**: Ensure Actions are enabled in your Forgejo instance
2. **Runner**: At least one Forgejo Actions runner configured
3. **Permissions**: Repository must allow Actions

### Setup Steps
1. **Install the workflow**:
   ```bash
   ./scripts/setup-license-automation.sh --platform forgejo
   ```

2. **Verify workflow file**: `.forgejo/workflows/license-check.yml`

3. **Test the integration**:
   - Create a PR with missing license headers
   - Check the Actions tab for workflow execution
   - Verify compliance reports are generated

### PR Commenting (Manual Setup)
Forgejo doesn't have built-in PR commenting like GitHub. To enable:

1. **Check workflow logs** for PR comment content
2. **Manually post comments** using the generated content
3. **Consider API integration** for automated commenting (custom implementation)

## 🔧 **Gitea Setup**

### Prerequisites
1. **Gitea Version**: 1.19.0 or later (for Actions support)
2. **Actions Enabled**: Actions must be enabled in Gitea configuration
3. **Runner**: At least one Gitea Actions runner configured

### Setup Steps
1. **Install the workflow**:
   ```bash
   ./scripts/setup-license-automation.sh --platform gitea
   ```

2. **Verify workflow file**: `.gitea/workflows/license-check.yml`

3. **Configure PR commenting** (optional):
   - Go to **Settings → Secrets** in your repository
   - Add secret named `GITEA_TOKEN`
   - Value: Gitea access token with repository permissions

4. **Test the integration**:
   - Create a PR with missing license headers
   - Check the Actions tab for workflow execution
   - Verify PR comments appear (if token configured)

### Creating a Gitea Access Token
1. Go to **Settings → Applications** in your Gitea account
2. Click **Generate New Token**
3. Select scopes: `repo` (full repository access)
4. Copy the token and add it as `GITEA_TOKEN` secret

## 📊 **Workflow Comparison**

| Feature | GitHub | Forgejo | Gitea |
|---------|--------|---------|-------|
| **PR Validation** | ✅ Auto | ✅ Auto | ✅ Auto |
| **PR Commenting** | ✅ Auto | ⚠️ Manual | 🔧 Token |
| **Audit Reports** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Artifact Upload** | ✅ Yes | ✅ Yes | ✅ Yes |
| **Setup Complexity** | 🟢 None | 🟡 Medium | 🟡 Medium |
| **Actions Version** | v4 | v4 | v3 |

## 🔍 **Troubleshooting**

### Forgejo Issues

**Actions not running:**
- Check if Forgejo Actions is enabled: `app.ini` → `[actions] ENABLED = true`
- Verify runner is connected and active
- Check repository Actions permissions

**Workflow file not found:**
- Ensure file is at `.forgejo/workflows/license-check.yml`
- Check file permissions and syntax
- Verify branch protection rules allow Actions

### Gitea Issues

**Actions not available:**
- Upgrade to Gitea 1.19.0 or later
- Enable Actions in configuration: `app.ini` → `[actions] ENABLED = true`
- Restart Gitea service

**PR commenting not working:**
- Verify `GITEA_TOKEN` secret is set correctly
- Check token permissions (needs `repo` scope)
- Review workflow logs for API errors

**Workflow syntax errors:**
- Gitea uses actions/checkout@v3 (not v4)
- Some GitHub Actions may not be compatible
- Check Gitea Actions documentation for supported features

### Common Issues

**Pre-commit hook not working:**
```bash
# Reinstall the hook
./scripts/pre-commit-license-check.sh --install

# Check hook permissions
ls -la .git/hooks/pre-commit
```

**Scripts not executable:**
```bash
# Fix permissions
chmod +x scripts/*.sh
```

**Platform detection issues:**
```bash
# Force platform detection
./scripts/setup-license-automation.sh --platform gitea --validate
```

## 📚 **Additional Resources**

### Forgejo Documentation
- [Forgejo Actions](https://forgejo.org/docs/latest/user/actions/)
- [Workflow Syntax](https://forgejo.org/docs/latest/user/actions/#workflow-syntax)
- [Runner Setup](https://forgejo.org/docs/latest/admin/actions/)

### Gitea Documentation
- [Gitea Actions](https://docs.gitea.io/en-us/usage/actions/overview/)
- [Workflow Syntax](https://docs.gitea.io/en-us/usage/actions/syntax/)
- [Runner Configuration](https://docs.gitea.io/en-us/usage/actions/act-runner/)

### Janus Documentation
- [LICENSE-AUTOMATION-USAGE.md](LICENSE-AUTOMATION-USAGE.md) - Complete usage guide
- [LICENSE-HEADERS.md](LICENSE-HEADERS.md) - Header templates and requirements
- [TODO-LICENSE-AUTOMATION.md](TODO-LICENSE-AUTOMATION.md) - Implementation tracking

## 🎉 **Success Validation**

After setup, validate your integration:

```bash
# 1. Validate setup
./scripts/setup-license-automation.sh --validate

# 2. Test pre-commit hook
# (Create a file without license header and try to commit)

# 3. Test CI workflow
# (Create a PR with license header violations)

# 4. Check compliance
./scripts/license-compliance-scan.sh --format markdown
```

Expected results:
- ✅ Pre-commit hook prevents commits with missing headers
- ✅ CI workflow runs on PRs and provides feedback
- ✅ Compliance reports show 100% compliance
- ✅ All automation tools work seamlessly

## 🚀 **Migration from GitHub**

If migrating from GitHub to Forgejo/Gitea:

1. **Copy workflows**:
   ```bash
   # The workflows are already created, just verify they exist
   ls -la .forgejo/workflows/license-check.yml
   ls -la .gitea/workflows/license-check.yml
   ```

2. **Update platform detection**:
   ```bash
   ./scripts/setup-license-automation.sh --platform forgejo
   ```

3. **Test integration**:
   ```bash
   ./scripts/setup-license-automation.sh --validate
   ```

The license header automation system provides seamless migration between platforms with identical functionality across GitHub, Forgejo, and Gitea! 🎯

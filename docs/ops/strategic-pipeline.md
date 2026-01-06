<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Strategic Release Pipeline

**The Assembly Line for Digital Dominance**

Every branch has a job, an ROI, and clear rules. No ambiguity, no excuses.

## 🏗️ **Branch Architecture**

### 🧪 **experimental/*** - The Sandbox
- **Purpose:** Raw innovation. The "what if" zone for new ideas, PoCs, and wild experiments
- **Rule:** Short-lived branches. Prove concept → merge to unstable, or die
- **Quality:** Speed > Perfection. Most experiments will fail, and that's efficient
- **CI:** Fast build + smoke tests only
- **Analogy:** Quarantined lab for mad scientists

### 🔥 **unstable** - The Forge (Alpha)
- **Purpose:** Integration and stabilization. Where proven experimental features are forged
- **Rule:** Primary target for feature branches. Expected to be broken frequently
- **Quality:** Continuous Integration runs relentlessly. Unit + integration tests mandatory
- **CI:** Full build + comprehensive testing
- **Analogy:** Factory floor - noisy, messy, constantly in motion

### 🛡️ **testing** - The Crucible (Beta)
- **Purpose:** Quality assurance and user validation. Always deployable for QA and beta testers
- **Rule:** Merges only from unstable when feature set complete and passes all checks
- **Quality:** Rigorous regression testing, performance analysis, security scanning
- **CI:** Multi-platform build matrix + full test suite + security scans
- **Analogy:** Wind tunnel and crash test facility

### 🏰 **main** - The Fortress (Production)
- **Purpose:** Production. What the customer has. Sacred, stable, secure, performant
- **Rule:** Only merges from testing or critical hotfixes. Every merge is tagged release
- **Quality:** Impeccably stable. GPG signature required (Markus only)
- **CI:** Full production pipeline + signed packages + deployment
- **Analogy:** The vault - locked down, audited, pristine assets only

### 🗿 **lts/*** - The Bedrock (Enterprise)
- **Purpose:** Monetizable stability for enterprise, embedded, regulated industries
- **Rule:** Branched from stable main. Only critical security patches and major bug fixes
- **Quality:** No new features. Ever. Predictability over novelty
- **CI:** Enterprise-grade validation + long-term support packages
- **Analogy:** Foundational pillar - doesn't change, which is its value

## 🔒 **Security & Access Control**

### GPG-Based Master Protection
- **Only Self Sovereign Society Foundation** can commit to main branch
- **GPG signature verification** enforced via git hooks
- **Commit message format** validation required
- **Force push protection** - history is immutable

### Branch Protection Rules
```bash
# Pre-receive hook validates:
✅ GPG signature from authorized key
✅ Commit message format compliance
✅ No force pushes to main
✅ Linear history preservation
```

## 🚀 **Release Process**

### Promotion Pipeline
```
experimental/* → unstable → testing → main → lts/*
```

### Quality Gates
Each promotion requires:
- ✅ All tests passing
- ✅ Security scans clean
- ✅ Performance benchmarks met
- ✅ Code review approved
- ✅ Documentation updated

### Automated Packaging
- **Alpha (unstable):** Linux packages only
- **Beta (testing):** All platforms (deb, rpm, msi, dmg)
- **Production (main):** Signed packages + artifact repository
- **LTS:** Enterprise packages + extended support

## 🛠️ **Usage**

### Strategic Release Script
```bash
# Build for specific branch
./scripts/strategic-release.sh build unstable

# Create packages
./scripts/strategic-release.sh package testing

# Promote between branches
./scripts/strategic-release.sh promote unstable testing

# Create production release
./scripts/strategic-release.sh release 0.1.1

# Check pipeline status
./scripts/strategic-release.sh status
```

### Manual Operations
```bash
# Create experimental branch
git checkout -b experimental/new-feature

# Promote to unstable
git checkout unstable
git merge --no-ff experimental/new-feature

# Only Markus can do this (GPG required):
git checkout main
git merge --no-ff testing
git tag -a v0.1.1 -m "Release v0.1.1"
```

## 📊 **CI/CD Pipeline**

### Forgejo Workflows
- **`.forgejo/workflows/strategic-pipeline.yml`** - Main pipeline
- **Branch-specific jobs** for each stage
- **Matrix builds** for multi-platform support
- **Artifact management** and deployment

### Integration with Existing Systems
- **Uses existing packaging/** directory structure
- **Leverages test-packaging.sh** for all package builds
- **Maintains current Linux/Windows/macOS** support
- **Preserves existing build system** (no reinvention)

## 🎯 **Quality Metrics**

### Success Criteria
- **0% false positives** in promotion decisions
- **< 5 minutes** average build time per stage
- **100% test coverage** for production releases
- **Zero security vulnerabilities** in main branch
- **Deterministic builds** across all platforms

### Monitoring
- **Build success rates** per branch
- **Promotion frequency** and success
- **Package download metrics**
- **Security scan results**
- **Performance regression tracking**

## 🚨 **Emergency Procedures**

### Hotfix Process
```bash
# Critical production fix (Markus only)
git checkout main
git checkout -b hotfix/critical-fix
# Make minimal fix
git checkout main
git merge --no-ff hotfix/critical-fix
git tag -a v0.1.1-hotfix.1 -m "Critical hotfix"
```

### Rollback Process
```bash
# Revert to previous release
git checkout main
git revert <commit-hash>
git tag -a v0.1.1-rollback -m "Emergency rollback"
```

## 📈 **Business Impact**

This pipeline is not just development process - it's business strategy:

- **Faster time to market** through parallel development
- **Higher quality releases** through systematic validation
- **Enterprise revenue** through LTS branches
- **Developer productivity** through clear processes
- **Customer confidence** through predictable releases

**The Result:** A ruthlessly efficient machine that prints money and pushes reliable code.

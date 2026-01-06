# Security Policy

**Janus Security Doctrine:** Radical transparency, verifiable security, and zero-trust supply chain management.

---

## Supported Versions

| Version | Support Status | Security Updates |
|---------|---------------|------------------|
| 0.x.x (pre-alpha) | ✅ Active Development | All security issues addressed |
| Future 1.x.x | 🔄 Planned | LTS security support |

**Current Status:** Pre-alpha development with security-first design principles.

---

## Security Architecture

### Core Security Principles

1. **Radical Transparency**: All security decisions are documented and auditable
2. **Verifiable Supply Chain**: Content-addressed everything with BLAKE3 hashing
3. **Capability-Based Security**: Explicit permissions for all system access
4. **Sandboxed Execution**: Comptime VM runs in hermetic environment
5. **Zero-Trust Dependencies**: All dependencies verified and vendored by default

### Security Features

#### 🔒 Comptime Sandbox
- **Hermetic Execution**: No network, filesystem, or environment access by default
- **Explicit Capability Grants**: All permissions must be declared in project policy
- **Auditable Grants**: All capabilities recorded in `JANUS.lock` for review
- **Deterministic Builds**: Reproducible compilation with content addressing

#### 🛡️ Memory Safety
- **Explicit Allocators**: No hidden memory allocations
- **Bounds Checking**: Configurable safety levels (`raw|checked|owned`)
- **Zero Memory Leaks**: Comprehensive testing with leak detection
- **Safe FFI**: C interop with explicit safety boundaries

#### 🔐 Effect System
- **Capability-Based I/O**: All I/O requires explicit capability tokens
- **Effect Tracking**: Function signatures declare all side effects
- **Least Privilege**: Context injection with minimal required permissions
- **Audit Trail**: All capability usage is traceable

---

## Software Bill of Materials (SBOM)

### The Janus Way: Trust Through Verification

**Philosophy**: We provide mechanisms, not policies. Users define their own security requirements.

**Core Commitment**: Every Janus release includes comprehensive SBOMs for complete supply chain transparency.

**Community Packages**: We make SBOM generation frictionless but don't mandate it. Instead:
1. **Frictionless Generation**: `janus build --generate-sbom` creates SBOMs automatically
2. **Visible Trust**: Packages with verified SBOMs get "Verified" badges in janus-ledger
3. **User Sovereignty**: Consumers set their own security policies in `janus.pkg`

#### CycloneDX SBOM
- **Format**: CycloneDX 1.5+ JSON format
- **Scope**: Core compiler (`libjanus`) and standard library (`std`)
- **Contents**:
  - All dependencies with versions and hashes
  - Vulnerability analysis integration
  - License compliance information
  - Build environment details
- **Location**: `dist/janus-{version}-cyclonedx.json`

#### SPDX Manifest
- **Format**: SPDX 2.3+ JSON format
- **Purpose**: License compliance and legal analysis
- **Contents**:
  - Complete license inventory
  - Copyright information
  - File-level license declarations
  - Dependency license compatibility
- **Location**: `dist/janus-{version}-spdx.json`

### SBOM Generation Process

```bash
# Generate SBOMs for current build
janus build --generate-sbom

# Verify SBOM integrity
janus verify-sbom dist/janus-{version}-cyclonedx.json

# Validate against known vulnerabilities
janus security-scan --sbom dist/janus-{version}-cyclonedx.json

# Check dependencies against user-defined security policies
janus build policy-check
```

### User-Defined Security Policies

**The Janus Way**: Instead of mandating security requirements, we empower users to define their own policies in `janus.pkg`:

```kdl
policy {
    // SBOM Requirements - YOU decide
    require_sbom "production"  // Options: "none", "production", "all"
    sbom_formats ["cyclonedx", "spdx"]

    // Exceptions for trusted packages
    sbom_exceptions ["std/collections", "crypto/blake3"]

    // Security thresholds - YOUR standards
    min_security_score 7.0
    max_vulnerability_severity "medium"

    // License compliance - YOUR legal requirements
    allowed_licenses ["Apache-2.0", "MIT", "BSD-3-Clause"]
    forbidden_licenses ["GPL-3.0", "AGPL-3.0"]

    // Supply chain verification - YOUR trust model
    require_signature true
    require_reproducible_builds true
}
```

**Policy Enforcement**:
- Policies are enforced at build time by `janus build policy-check`
- Clear error messages with remediation suggestions
- Strict mode fails builds on policy violations
- Flexible exemption system for trusted packages

### Supply Chain Verification

#### Content Addressing
- **BLAKE3 Hashing**: All sources, IR, and objects are content-addressed
- **Reproducible Builds**: Identical inputs produce identical outputs
- **Tamper Detection**: Any modification breaks content addressing
- **Audit Trail**: Complete build provenance tracking

#### Dependency Management
- **Vendor-by-Default**: All dependencies included in repository
- **Version Pinning**: Exact versions with cryptographic hashes
- **Security Scanning**: Automated vulnerability detection
- **License Compliance**: Automated license compatibility checking

---

## Vulnerability Reporting

### Reporting Security Issues

**🚨 CRITICAL**: Do not report security vulnerabilities through public GitHub issues.

#### Preferred Reporting Method
- **Email**: security@janus-lang.org
- **PGP Key**: Available at https://janus-lang.org/security/pgp-key.asc
- **Response Time**: 48 hours acknowledgment, 7 days initial assessment

#### Alternative Reporting
- **GitHub Security Advisories**: Use private vulnerability reporting
- **Direct Contact**: Reach out to core maintainers privately

### What to Include

Please provide as much information as possible:

1. **Vulnerability Description**
   - Clear description of the security issue
   - Potential impact and severity assessment
   - Affected versions and components

2. **Reproduction Steps**
   - Minimal code example demonstrating the issue
   - Environment details (OS, Zig version, LLVM version)
   - Build configuration and flags used

3. **Proposed Solution** (if available)
   - Suggested fix or mitigation
   - Alternative approaches considered
   - Backward compatibility considerations

### Example Report Template

```
Subject: [SECURITY] Vulnerability in libjanus semantic resolution

## Summary
Brief description of the vulnerability

## Impact
- Severity: Critical/High/Medium/Low
- Affected Components: libjanus, janusd, std library
- Affected Versions: 0.x.x to current

## Reproduction
1. Create file with content: [minimal example]
2. Compile with: janus build --profile=full
3. Observe: [unexpected behavior]

## Environment
- OS: Linux/macOS/Windows
- Zig Version: 0.13.x
- LLVM Version: 17/18
- Janus Version: 0.x.x

## Proposed Fix
[If available]
```

---

## Security Response Process

### Response Timeline

1. **Acknowledgment**: 48 hours
2. **Initial Assessment**: 7 days
3. **Fix Development**: 14-30 days (depending on severity)
4. **Security Advisory**: Published with fix
5. **CVE Assignment**: If applicable

### Severity Classification

#### Critical (CVSS 9.0-10.0)
- Remote code execution
- Privilege escalation
- Complete system compromise
- **Response**: Immediate hotfix release

#### High (CVSS 7.0-8.9)
- Significant data exposure
- Authentication bypass
- Denial of service
- **Response**: Priority fix within 14 days

#### Medium (CVSS 4.0-6.9)
- Limited information disclosure
- Minor privilege escalation
- **Response**: Fix in next regular release

#### Low (CVSS 0.1-3.9)
- Minimal impact issues
- **Response**: Fix when convenient

### Security Advisories

All security advisories are published at:
- **GitHub**: https://github.com/janus-lang/janus/security/advisories
- **Website**: https://janus-lang.org/security/advisories/
- **Mailing List**: security-announce@janus-lang.org

---

## Security Best Practices

### For Janus Developers

#### Secure Coding Guidelines
1. **Memory Safety**: Always use explicit allocators and bounds checking
2. **Input Validation**: Validate all external inputs at boundaries
3. **Capability Discipline**: Never bypass the capability system
4. **Error Handling**: Use error unions, never ignore failures
5. **Testing**: Include security-focused test cases

#### Code Review Requirements
- **Security Review**: All PRs reviewed for security implications
- **Capability Audit**: Changes to capability system require extra scrutiny
- **Dependency Updates**: Security impact assessment for all dependency changes
- **SBOM Updates**: Ensure SBOMs are updated with changes

### For Janus Users

#### Secure Development
1. **Profile Selection**: Use appropriate safety profile for your use case
2. **Capability Minimization**: Grant only necessary capabilities
3. **Dependency Auditing**: Review all dependencies and their licenses
4. **Build Verification**: Verify SBOM integrity for production builds

#### Production Deployment
1. **SBOM Validation**: Always validate SBOMs in CI/CD pipelines
2. **Vulnerability Scanning**: Regular security scans of dependencies
3. **Update Management**: Timely application of security updates
4. **Monitoring**: Monitor for security advisories and CVEs

---

## Security Tools and Integration

### Built-in Security Tools

#### SBOM Generation
```bash
# Generate comprehensive SBOM
janus build --generate-sbom --format=cyclonedx,spdx

# Validate SBOM integrity
janus verify-sbom --file=dist/janus-cyclonedx.json

# Security scan with SBOM
janus security-scan --sbom=dist/janus-cyclonedx.json
```

#### Capability Auditing
```bash
# Audit capability usage
janus audit-capabilities --project=.

# Validate capability grants
janus verify-capabilities --lock=JANUS.lock

# Generate capability report
janus capability-report --format=json,html
```

#### Build Security
```bash
# Reproducible build verification
janus build --verify-reproducible

# Content addressing validation
janus verify-cas --all

# Dependency security scan
janus scan-dependencies --severity=high
```

### Third-Party Integration

#### Vulnerability Databases
- **GitHub Advisory Database**: Automated scanning
- **OSV Database**: Open source vulnerability tracking
- **NVD/CVE**: National Vulnerability Database integration
- **Snyk**: Commercial vulnerability scanning (optional)

#### CI/CD Integration
- **GitHub Actions**: Security scanning workflows
- **GitLab CI**: SBOM generation and validation
- **Jenkins**: Security pipeline integration
- **Custom**: API for security tool integration

---

## Compliance and Certifications

### Standards Compliance
- **NIST Cybersecurity Framework**: Aligned security practices
- **OWASP SAMM**: Software assurance maturity model
- **SLSA**: Supply chain levels for software artifacts
- **SPDX**: Software package data exchange standard

### Future Certifications
- **Common Criteria**: Planned for 1.0 release
- **FIPS 140-2**: Cryptographic module validation
- **SOC 2**: Service organization controls (for hosted services)

---

## Security Contacts

### Core Security Team
- **Security Lead**: security-lead@janus-lang.org
- **SBOM Maintainer**: sbom@janus-lang.org
- **Vulnerability Coordinator**: vuln-coord@janus-lang.org

### Community Security
- **Security Working Group**: security-wg@janus-lang.org
- **Security Discussions**: https://github.com/janus-lang/janus/discussions/categories/security
- **Security Mailing List**: security@janus-lang.org

---

## Acknowledgments

We thank the security research community for their contributions to Janus security. Responsible disclosure helps make Janus safer for everyone.

### Hall of Fame
*Security researchers who have responsibly disclosed vulnerabilities will be listed here.*

---

**Last Updated**: August 21, 2025
**Next Review**: September 21, 2025

---

*This security policy is a living document and will be updated as the Janus project evolves. All changes are tracked in the project's version control system.*
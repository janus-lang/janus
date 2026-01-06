Name:           janus-lang
Version: 0.1.2
Release:        1%{?dist}
Summary:        Systems language with precise incremental compilation

License:        LSL-1.0
URL:            https://github.com/janus-lang/janus
Source0:        https://github.com/janus-lang/janus/archive/v%{version}.tar.gz#/%{name}-%{version}.tar.gz

BuildRequires:  zig >= 0.14.0
BuildRequires:  git
BuildRequires:  glibc-devel
Requires:       glibc

# Provide janus command
Provides:       janus = %{version}-%{release}

%description
Janus is a revolutionary systems programming language that features:

* Precise incremental compilation with mathematical guarantees
* Progressive complexity profiles (min/go/full)
* Content-addressed storage (CAS) for deterministic builds
* ASTDB architecture for advanced tooling capabilities
* Capability-based security system
* Zero-cost abstractions with honest performance characteristics

The language is designed to solve the adoption paradox in systems programming
by providing familiar patterns that progressively unlock advanced features
without breaking changes.

%package doc
Summary:        Documentation for Janus programming language
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}

%description doc
This package contains comprehensive documentation for the Janus programming
language, including language specifications, API documentation, architecture
documentation, and tutorials.

%package examples
Summary:        Example programs for Janus programming language
BuildArch:      noarch
Requires:       %{name} = %{version}-%{release}

%description examples
This package contains example programs and case studies for the Janus
programming language, including the canonical case study demonstrating
the progressive profile system.

%prep
%autosetup -n janus-%{version}

%build
# Build with Zig using ReleaseSafe optimization
zig build -Doptimize=ReleaseSafe

%check
# Run basic functionality tests
./zig-out/bin/janus version
./zig-out/bin/janus profile show
# Test core CAS functionality
./zig-out/bin/janus test-cas

%install
# Install main executable
install -Dm755 zig-out/bin/janus %{buildroot}%{_bindir}/janus

# Install documentation
install -dm755 %{buildroot}%{_docdir}/%{name}/
install -m644 README.md %{buildroot}%{_docdir}/%{name}/
install -m644 CONTRIBUTING.md %{buildroot}%{_docdir}/%{name}/
install -m644 SECURITY.md %{buildroot}%{_docdir}/%{name}/
install -m644 errors.md %{buildroot}%{_docdir}/%{name}/

# Install specifications
cp -r docs/specs %{buildroot}%{_docdir}/%{name}/

# Install examples
cp -r examples %{buildroot}%{_docdir}/%{name}/

%files
%license LICENSE
%doc README.md
%{_bindir}/janus

%files doc
%{_docdir}/%{name}/CONTRIBUTING.md
%{_docdir}/%{name}/SECURITY.md
%{_docdir}/%{name}/errors.md
%{_docdir}/%{name}/specs/

%files examples
%{_docdir}/%{name}/examples/

%changelog
* Mon Aug 26 2025 Janus Development Team <maintainer@janus-lang.org> - 0.1.0-1
- Initial release of Janus programming language
- Features precise incremental compilation with mathematical guarantees
- Implements progressive complexity profiles (min/go/full)
- Includes ASTDB architecture for advanced tooling
- Provides capability-based security system
- Supports content-addressed storage for deterministic builds
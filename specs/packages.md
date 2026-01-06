<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Packages & Ecosystem (v0)

**Prime Directive: The Ledger, Not the Registry**

Janus rejects centralized, trust-based package managers. We do not have a *registry*; we have a verifiable **ledger**. The ecosystem is built on cryptographic proof, explicit policy, and sovereign control.

* **Identity is the content.** Every dependency is pinned by a BLAKE3 tree hash (**CID**). No version ranges in builds. No global installs.
* **Policy is explicit.** Capabilities for **comptime** and runtime are granted in project policy, recorded in the lockfile, and diffed on update.
* **Transport is pluggable.** Git, IPFS, OCI, HTTPS tarballs — the transport layer is an *untrusted commodity*. We verify bytes against the CID.
* **Isolation by default.** Source is vendored into a per-project, content-addressed store. Dependency hell is engineered out of existence.

---

## Quick start (what happens, exactly?)

```bash
# 1) You declare intent
janus add git+https://git.example/x/xxhash@v0.8.2

# 2) Client fetches bytes, normalizes them, computes the CID, and asks you
#    to approve any new comptime capabilities the package requests
#    (cap delta preview)
# 3) Lockfile is written; sources are vendored into .janus/cas/<algo>/<hash>/
# 4) Compiler reads only the lockfile when building
```

Flow at a glance:

```
manifest (intent) ──resolve+fetch──► normalized archive ──BLAKE3──► CID
      │                                                     │
      ├──cap prompts & policy checks◄───────────────────────┤
      ▼                                                     ▼
  JANUS.lock (truth) ──► vendored CAS ──► reproducible builds
```

---

## Core concepts

### CIDs (Content IDs)

* Format: `blake3:<hex-64>`, the BLAKE3 hash of the **normalized** source archive’s Merkle root.
* The hash covers file contents **and** layout. No identity by “name\@version”.

### CAS (Content-Addressed Store)

* Default layout: `.janus/cas/blake3/<hh>/<hash>/` (first 2 hex as shard).
* Multiple packages with identical bytes dedupe automatically.

### Normalization (deterministic packaging)

When computing a CID or packing a tarball:

* Strip VCS noise (`.git`, `.hg`, `.svn`), editor temp files, and platform metadata.
* Normalize: permissions (files `0644`, dirs `0755`, exec bits preserved when present), timestamps (`mtime=0`), user/group ids (`0:0`), path separators, entry ordering (byte-wise lexicographic).
* Preserve symlinks as symlinks (no follow).
* Root marker: archive must contain a single top-level directory with `janus.pkg`.

If bytes differ after normalization, the CID **must** differ.

---

## Artifacts

### `janus.pkg` — Manifest (human-authored, **KDL**)

Declarative intent. Readable. Source of **policy proposals**.

```kdl
// janus.pkg
name "nexus/xxhash"
license "Apache-2.0"

dependencies {
  "nexus/blake3" ref="git+https://git.example/x/blake3@9e1f…" tag="v1.4.1"
  "std/http"     ref="janus://std/http@v0.1.0"
}

features { simd true }

comptime {
  policy {
    // Default deny; explicit least-privilege grants:
    fs_read "schemas/*.json"
    net false
    env                       // grant empty env list
  }
}
```

**Notes**

* `license` is mandatory (SPDX id).
* `ref` is a transport URL; `tag` is author convenience only. The resolver pins to a **CID**.
* Local dev convenience: `path://../lib` is allowed in the manifest, but the **lockfile** will store the resolved **CID** (no path refs in locks).

### `JANUS.lock` — Lockfile (machine-authoritative, **JSON**)

**Law:** The compiler reads **only** the lockfile. The manifest is for authors; the lockfile is for builds.

```jsonc
{
  "graph": {
    "nexus/blake3": {
      "cid": "blake3:adf3…",
      "ref": "git+…@9e1f…",
      "caps": { "fs_read": ["schemas/*.json"], "net": false, "env": [] }
    },
    "std/http": {
      "cid": "blake3:77b2…",
      "ref": "janus://std/http@v0.1.0",
      "caps": {}
    }
  },
  "attestations": {
    "nexus/blake3": {
      "sig": "minisign:RWTx…",
      "repro": ["builder1@commit:abc", "builder2@commit:def"]
    }
  }
}
```

Lockfile invariants:

* Every node has a `cid` and normalized `ref`.
* Capabilities are **frozen**. Changes show up as a “capabilities delta”.
* Optional `sig` and `repro` entries record signatures and reproducible build attestations.

---

## CLI (verbs of sovereignty)

```bash
# Add a dependency: resolves tag → exact CID, previews new comptime caps
janus add git+https://…/xxhash@v0.8.2

# Update: shows code diff and capability delta; you must approve
janus update nexus/xxhash --to v0.8.3

# Vendor sources into project-local CAS (default)
janus vendor

# Verify supply chain: hashes, signatures, attestations, SBOM
janus verify

# Show supply-chain delta since last lockfile commit
janus audit

# Grant or revoke build capabilities (edits manifest; lock records final state)
janus cap grant  nexus/xxhash fs_read:schemas/*.json
janus cap revoke nexus/xxhash net
```

**Sample cap-delta output**

```
Package: nexus/xxhash  (blake3:9f32… → blake3:a7c1…)
New files: 3  |  Deleted: 1  |  Diff size: +14 KB

Comptime capabilities:
  - fs_read: ["schemas/*.json"]      (UNCHANGED)
  - net:     false → true            (NEW NETWORK ACCESS)  ❗
Approve? [y/N]
```

---

## Transport & discovery

* **Transports:** `git+https`, `https+tar`, `ipfs`, `oci` (ORAS). Transport is untrusted.
* **Discovery:** Optional, *untrusted* indexes may map **name → ref** (like a phonebook). Client **always** verifies fetched content against the expected CID.
* **Mirrors:** `janus mirror add corp://mirror` lets orgs serve immutable, CID-addressed blobs with zero egress.

---

## Trust & verification

* **Content addressing:** BLAKE3 Merkle tree of the normalized archive. (Root → CID.)
* **Signatures:** Minisign/age or Sigstore (fulcio/rekor). Optional; recorded in lockfile.
* **Transparency log (optional):** append-only Merkle log of `(name, ref, cid, caps)`. Client can verify inclusion to detect stealth yanks or swaps.
* **Reproducibility:** Packages may ship reproducible build attestations; you can require **N-of-M** independent attestations to accept an update.
* **Policy gates:** Organization policy can enforce: allowed licenses (SPDX allowlist), maximum capability sets, mandatory signatures/attestations, max transitive depth.

---

## Capability model (build vs run)

* **Build-time (`comptime`):** **deny-all by default**. Grants declared in `janus.pkg` → frozen in `JANUS.lock`.
* **Run-time:** Libraries are inert; applications pass capabilities (`CapFsRead`, `CapNetHttp`, …) via **Context**. Function signatures reveal effects.
* **Auditable updates:** `janus update` prints a capabilities delta and will not proceed without explicit approval.

---

## Versioning & conflict strategy

* **No ranges in lockfiles.** Manifests may use tags; the resolver pins to a single CID.
* **Multi-version by design.** Different CIDs can coexist; CAS dedupes identical bytes; imports are namespaced by package, not a global solver.
* **Zero global solver.** With identity = content and vendoring by default, diamond conflicts are structurally impossible.

---

## Publishing

```bash
# Create a normalized source archive (deterministic)
janus pack ./my-lib > my-lib-<cid>.tar.zst

# Publish over any supported transport
janus publish --to git+https://…         # pushes tag + archive
janus publish --to oci://registry/x/y    # ORAS artifact
janus publish --to ipfs://…              # pins to IPFS
```

* **SBOM:** `janus sbom` emits SPDX/CycloneDX with CIDs, capabilities, and licenses.

---

## Example project flow

```bash
janus init --lib nexus/xxhash
git init && git commit -m "scaffold"

# add a dep (tag → CID; review cap prompts)
janus add git+https://git.maiwald.work/NexusLabs/blake3@v1.4.1

janus verify
janus audit
janus vendor
janus build
```

---

## License policy: mechanism over policy

We don’t mandate a license. We provide **mechanisms** to enforce **your** policy.

### Mandatory license field

```kdl
// janus.pkg
name "markus/json-parser"
version "1.0.0"
license "CC0-1.0"  // SPDX
```

### Organization policy (example)

```kdl
// .janus/policy.kdl
license {
  allow ["CC0-1.0" "MIT" "Apache-2.0"]
  warn  ["LSL-1.0"]
  deny  ["AGPL-3.0-only"]
}
caps {
  deny net            # prohibit network at comptime globally
  max_fs_read 8       # cap count of distinct fs_read globs
}
```

**Commands**

```bash
janus license check       # validate current graph vs policy
janus license summary     # show license mix
janus license audit       # show license deltas vs last lock
janus license report --format spdx
```

---

## Failure modes & diagnostics (selected)

* **E2601\_BAD\_CID** — fetched bytes don’t match expected CID (transport untrusted).
* **E2602\_LOCK\_STALE** — `JANUS.lock` references unknown package or CID missing in CAS.
* **E2603\_CAP\_DELTA\_DENIED** — update introduces new capabilities and the user/policy rejected it.
* **E2604\_SIG\_REQUIRED** — org policy requires a signature/attestation that’s missing.
* **E2605\_POLICY\_VIOLATION** — license/cap/depth exceeds policy.
* **E2606\_NORMALIZE\_MISMATCH** — archive not canonical after normalization (report offending entries).
* **E2607\_TRANSPORT\_UNSUPPORTED** — attempted transport not enabled by policy.

Each diagnostic includes remediation (e.g., “run `janus verify --fix`” / “add to `.janus/policy.kdl`”).

---

## FAQ

**Why no registry?**
Registries become a single point of failure and trust. The ledger model—CID + signatures + optional transparency—removes that trust anchor.

**Can I develop against local paths?**
Yes (`path://…` in the manifest). The lockfile resolves them to a CID; paths never appear in `JANUS.lock`.

**How do I ensure hermetic `comptime`?**
Grant only the minimal caps in `janus.pkg`. `janus verify` ensures `JANUS.lock` reflects those exact grants; the compiler enforces deny-by-default.

**How are transitive deps handled?**
Every node in `graph` is content-addressed. Multiple versions can coexist; no global solver.

---

## Why this doesn’t suck

* **No dependency hell:** per-project CAS + exact CIDs.
* **100% verification:** every byte hashed; signatures/attestations optional but supported.
* **Determinism:** lockfile + hermetic `comptime`; identical inputs → identical outputs.
* **Security by ergonomics:** capability prompts on add/update and a clear “cap delta” at review.

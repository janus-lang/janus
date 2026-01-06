<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# The Doctrine of Discoverability

Languages like C and Python, with their hidden functions, dynamic typing, and reliance on ambient state, are hostile to modern tooling. They force the developer—and the IDE—to guess.

Janus is architecturally incapable of this ambiguity.

1.  **Syntactic Honesty Forbids Hiddenness:** Our doctrines of **Syntactic Honesty** and **Revealed Complexity** forbid the very things that break the left-to-right flow. There are no hidden, free-floating functions. There is no implicit global state. If a function or method exists, it exists within an explicitly imported, discoverable module or as a method on a statically-known type. There is no other way.

2.  **Uniform Call Syntax is the Mechanism:** Our consistent `object.method(args)` and `module.function(args)` syntax is the mechanical foundation of discoverability. The type of the entity on the left of the `.` operator deterministically defines the valid set of identifiers that can appear on the right.

---
## The Janus Advantage: The Oracle Conduit

But we go further. Other languages like Rust and JavaScript achieve this through their compiler's frontend analysis and type system. This is good, but it is conventional.

Janus achieves this through the **ASTDB and the Oracle**. Our `lsp-bridge` does not need to guess or maintain a complex, in-memory model of your code. It is a thin client that sends a precise, semantic query to the `janusd` daemon, such as:

`Q.PublicMembersOf(type_cid: "blake3:...")`

The daemon, with its complete, live, and granite-solid understanding of your codebase, returns a perfect, cryptographically-verified list of available methods and fields.

This means our autocomplete and real-time error checking are not just a feature of the language server; they are **database queries**. They are faster, more accurate, and more resilient to code changes than any conventional approach.

The developer's editor becomes a direct, real-time terminal to the semantic truth of the codebase. It is not an afterthought; it is the core of the experience.

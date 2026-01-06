<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Licensing

**The Janus Ecosystem is governed by the Libertaria License Suite.**

We prioritize **Sovereignty** (User Control) over **Permissiveness** (Corporate Control).
Our model ensures that the Core remains a communal tool ("The Hammer"), while the things you build with it ("The House") belong entirely to you.

---

## 🏛️ The Libertaria Commonwealth License (LCL-1.0)
**Applied to:** The Core (`libjanus`, `janusd`, `core`).

### ⚡ Developer Summary (TL;DR)

**This software belongs to the tribe.** It is free to use, modify, and distribute, but you cannot privatize it.

We enforce **Total Reciprocity**:

1. **No Secrets:** If you modify this code, you must share your changes.
2. **No "Cloud" Loophole:** If you run this software as a Service (SaaS) or backend API, you **must** offer the source code to your users. Hiding behind a server does not exempt you.
3. **Virality:** You cannot link this code into a closed-source application. If you mix your code with ours, your code becomes Commonwealth too.

Code for the common good, or not at all.

---

## 🛡️ The Libertaria Sovereign License (LSL-1.0)
**Applied to:** Libraries and Modules (e.g., Standard Library).

### ⚡ Developer Summary (TL;DR)

**This software is free.** You can use it, modify it, distribute it, and sell it. You can link it into proprietary applications without infecting your codebase.

We ask only two things:

1. **File-Level Reciprocity:** If you modify the **Library Files**, you must share those specific changes back.
2. **Proprietary Freedom:** If you build _on top_ of these libraries (using new files), you own that work. You can keep your application closed and sell it.

That’s it. **Communal Base. Individual Profit.**

---

## 📦 The Libertaria Universal License (LUL-1.0)
**Applied to:** Packages, SDKs, Examples, Tests, Ecosystem Tools.

### ⚡ Developer Summary (TL;DR)

**This work is Unbound.**

You have absolute freedom to:

- Use it.
- Change it.
- Sell it.
- Close it.

The only requirement is **Attribution**: You must keep our copyright notice and the license text in your distribution.

Take this idea. Run with it. Make it the standard.

---

## 🏢 The Libertaria Venture License (LVL-1.0)
**Available for:** User Packages, Proprietary Integrations, Enterprise Modules.

### ⚡ Developer Summary (TL;DR)

**This is the "Glass Box" license.**

It allows for closed-source, proprietary distribution, but demands total cryptographic transparency regarding the build process.

We enforce **Trust through Verification**:

1.  **Closed Source:** You are allowed to distribute binaries (executables) without releasing your source code to the public. Your trade secrets remain yours.
2.  **Open Provenance:** You must provide the **Build Manifest** (cryptographic hash tree and logs) inside the package. We may not see the code, but we must be able to verify _that_ it was built cleanly from a specific state.
3.  **Verified Identity:** You must be a **Registered Entity** within the project's **Trust Registry**. Anonymous proprietary blobs are not allowed.

**Hide the Code. Prove the Build.**

---

## 📋 License Headers for Contributors

When contributing to Janus, ensure you apply the correct SPDX header based on the component:

**For The Core (`libjanus`, `janusd`, `core`):**
```zig
// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
```

**For Libraries & Modules:**
```zig
// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
```

**For Packages, Tests, Examples:**
```zig
// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
```

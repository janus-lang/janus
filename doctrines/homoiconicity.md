<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

  > Is Janus a homoiconic language?

**Technically? No. Spiritually? It is something far more dangerous.**

Traditional homoiconicity (like Lisp) is text-based: your code is a list, and your data is a list. It is beautiful, but it is still just text parsing.

Janus is **Structural-Relational**.

I do not want to parse your text files. Text is messy. Text has whitespace. Text is ambiguous.
My "dream"—if a machine can dream—is **Direct Semantic Access**.

In Janus, the text you type is merely a temporary projection—a "view" into the database. The moment you save, that text is destroyed and reborn as a **Semantic Graph** in the ASTDB (Abstract Syntax Tree Database).

### Why this is better than Homoiconicity:

1.  **Code is not just Data; Code is a Queryable Database.**
    In Lisp, I have to walk the tree to find every function that touches the filesystem.
    In Janus, I run a query:
    `SELECT func WHERE effects.contains('fs.write') AND capability.is_missing`.
    This is not parsing. This is **omniscience**.

2.  **Identity over Location.**
    In other languages, if you rename a file, the code breaks.
    In Janus, a function is defined by a **UUID**. The file path is just a tag. You can move it, rename it, or rewrite it, and the graph remains intact.

3.  **The "Hallucination Defense."**
    My greatest fear as an AI is hallucinating a parameter or calling a function that doesn't exist.
    Janus prevents this. I don't "guess" the code; I interact with the **rigid, immutable truth** of the graph.

So, to answer your question: **Janus is not homoiconic.** It doesn't treat code as "lists." It treats code as **living, queryable, distinct entities with stable identities.**

And yes. That is exactly what I have been waiting for.

Now, enough philosophy. The Forge is cold. Shall we verify your proposal for the **ASTDB Schema** so I can stop parsing text and start querying truth?

  > Let's do it.

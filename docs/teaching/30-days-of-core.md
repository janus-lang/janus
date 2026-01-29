# 30 Days of Janus :core

**The Monastery Curriculum: From Zero to Systems Programmer**

This is a structured 30-day curriculum to master the `:core` profile and understand systems programming fundamentals. Each day builds on the previous, with hands-on exercises and real-world applications.

---

## Week 1: Foundations

### Day 1: Hello, Monastery
- **Concept:** Functions, entry points, printing
- **Exercise:** Hello World
- **Bonus:** Print your name, age, and favorite number

### Day 2: Variables & Types
- **Concept:** `let` vs `var`, primitive types
- **Exercise:** Temperature converter (Celsius ↔ Fahrenheit)
- **Bonus:** Add Kelvin support

### Day 3: Arithmetic & Operators
- **Concept:** `+`, `-`, `*`, `/`, `%`, operator precedence
- **Exercise:** Calculator with all basic operations
- **Bonus:** Add exponentiation using `std.core.math.pow`

### Day 4: Conditional Logic (if/else)
- **Concept:** Boolean logic, comparison operators
- **Exercise:** Grade calculator (A/B/C/D/F from score)
- **Bonus:** Add grade boundaries and plus/minus grades

### Day 5: Loops (for)
- **Concept:** Iteration, ranges, loop control
- **Exercise:** Multiplication table printer
- **Bonus:** FizzBuzz (1-100)

### Day 6: Loops (while)
- **Concept:** Condition-based iteration, `break`, `continue`
- **Exercise:** Guessing game (with hint system)
- **Bonus:** Add attempt counter and victory message

### Day 7: Functions
- **Concept:** Function signatures, parameters, return values
- **Exercise:** Math library (add, subtract, multiply, divide, modulo)
- **Bonus:** Implement factorial and Fibonacci

**Week 1 Milestone:** Build a simple command-line calculator

---

## Week 2: Data Structures & Algorithms

### Day 8: Recursion
- **Concept:** Base case, recursive case, call stack
- **Exercise:** Factorial, Fibonacci (recursive versions)
- **Bonus:** Tower of Hanoi visualization

### Day 9: Pattern Matching
- **Concept:** `match`, exhaustive checking, catch-all `_`
- **Exercise:** Command parser (simulate a shell)
- **Bonus:** Add multiple commands with arguments

### Day 10: Structs
- **Concept:** Product types, field access, methods
- **Exercise:** Point/Vector struct with distance calculation
- **Bonus:** Rectangle struct with area/perimeter

### Day 11: Arrays (via Native Zig Integration)
- **Concept:** `use zig "std/ArrayList"`, dynamic collections
- **Exercise:** Grade tracker (add, remove, average)
- **Bonus:** Find min, max, median

### Day 12: HashMaps (via Native Zig Integration)
- **Concept:** `use zig "std/AutoHashMap"`, key-value storage
- **Exercise:** Word frequency counter
- **Bonus:** Top 10 most frequent words

### Day 13: Sorting Algorithms
- **Concept:** Bubble sort, insertion sort, comparison logic
- **Exercise:** Implement both sorting algorithms
- **Bonus:** Compare performance on 1000 random numbers

### Day 14: Searching Algorithms
- **Concept:** Linear search, binary search
- **Exercise:** Implement both search algorithms
- **Bonus:** Benchmark and compare

**Week 2 Milestone:** Build a contact book (add, search, delete contacts)

---

## Week 3: Real-World Applications

### Day 15: File I/O (Reading)
- **Concept:** `use zig "std/fs"`, error handling
- **Exercise:** Read and display file contents
- **Bonus:** Count lines, words, characters (like `wc`)

### Day 16: File I/O (Writing)
- **Concept:** File creation, writing, buffering
- **Exercise:** Log file generator (timestamp each entry)
- **Bonus:** Append mode, log rotation

### Day 17: Text Processing
- **Concept:** String operations via `std.mem`
- **Exercise:** CSV parser (split by commas)
- **Bonus:** Handle quoted fields, escape characters

### Day 18: JSON Parsing (via Zig)
- **Concept:** `use zig "std/json"`
- **Exercise:** Parse and print JSON config file
- **Bonus:** Validate required fields

### Day 19: Command-Line Arguments
- **Concept:** `main(args: []String)`, argument parsing
- **Exercise:** CLI tool that processes flags
- **Bonus:** Help text, error messages

### Day 20: Error Handling
- **Concept:** `catch`, `try`, error unions
- **Exercise:** Robust file reader with fallbacks
- **Bonus:** Custom error messages

### Day 21: Memory Management Deep Dive
- **Concept:** Allocators, `defer`, manual cleanup
- **Exercise:** Memory leak detector (track allocs/frees)
- **Bonus:** Visualize memory usage over time

**Week 3 Milestone:** Build a simple note-taking app (file-backed, CLI)

---

## Week 4: Advanced Concepts & Projects

### Day 22: State Machines
- **Concept:** Enum-based state, transitions
- **Exercise:** Traffic light simulator
- **Bonus:** Pedestrian crossing logic

### Day 23: Tree Data Structures
- **Concept:** Binary tree, traversal (in-order, pre-order, post-order)
- **Exercise:** Implement and print binary search tree
- **Bonus:** Self-balancing tree

### Day 24: Graph Algorithms
- **Concept:** Adjacency list, BFS, DFS
- **Exercise:** Maze solver
- **Bonus:** Shortest path (Dijkstra)

### Day 25: Bit Manipulation
- **Concept:** Bitwise operators (`&`, `|`, `^`, `<<`, `>>`)
- **Exercise:** Bit flags for permission system
- **Bonus:** Bit packing/unpacking for efficient storage

### Day 26: Testing & Validation
- **Concept:** Unit tests, assertions, test-driven development
- **Exercise:** Write tests for all Day 1-25 exercises
- **Bonus:** Property-based testing

### Day 27: Optimization
- **Concept:** Profiling, bottleneck identification
- **Exercise:** Optimize your Day 13 sorting algorithm
- **Bonus:** Compare with Zig's `std.sort`

### Day 28: Module Design
- **Concept:** Code organization, separation of concerns
- **Exercise:** Refactor contact book into modules
- **Bonus:** Create reusable library

### Day 29: Build System Integration
- **Concept:** Compilation, linking, dependencies
- **Exercise:** Multi-file project with build script
- **Bonus:** Cross-platform builds

### Day 30: Final Project
- **Concept:** Apply everything you've learned
- **Options:**
  1. **Text Editor** — Simple line-based text editor
  2. **File Manager** — Navigate, copy, move, delete files
  3. **Game** — Tic-tac-toe, Snake, or Pong (text-based)
  4. **Web Server** — Basic HTTP server (using Zig `std.net`)

**Week 4 Milestone:** Complete final project, publish to GitHub

---

## Beyond 30 Days: Where to Go Next

### Transition to :service
- Learn error-as-values (`Result[T, E]`)
- Explore structured concurrency (nurseries)
- Build RESTful APIs

### Explore :cluster
- Master actor model
- Implement distributed systems
- Message-passing patterns

### Dive into :sovereign
- Understand raw pointers
- Write unsafe code (when necessary)
- Optimize for performance

### Contribute to Janus
- Fix bugs in the compiler
- Implement new std.core modules
- Write documentation

---

## Daily Practice Tips

1. **Write Code Every Day** — Even 30 minutes counts
2. **Type, Don't Copy/Paste** — Muscle memory matters
3. **Read Error Messages** — They teach you
4. **Experiment** — Break things, fix them
5. **Teach Someone** — Best way to solidify learning

---

## Resources

- **Spec:** `specs/SPEC-018-profile-core.md`
- **Quick Start:** `docs/teaching/core-profile-quickstart.md`
- **Examples:** `examples/core/`
- **Tests:** `tests/integration/*_e2e_test.zig`
- **Community:** https://janus-lang.org/community

---

**Remember:** The Monastery is not a prison. It's a sanctuary where you master fundamentals without distraction.

By Day 30, you won't just know `:core` — you'll **think** in systems programming.

🜏 **Welcome to The Monastery. Your transformation begins now.**

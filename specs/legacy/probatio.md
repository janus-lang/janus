<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# PROBATIO: The Proving Grounds

**The Janus Philosophy of Integrated Verification**

> *"A test is not a chore. It is a theorem. And every theorem deserves a proof."*

---

## The Core Insight

Most languages treat testing as an afterthought—a separate tool, a different syntax, a library you import. This creates a subtle but devastating psychological divide: **code is real, tests are optional.**

Janus rejects this. In PROBATIO:

- **`test` is a keyword**, not a library.  
- **`assert` is a compiler intrinsic**, not a function.  
- **Verification is structural proof**, not bureaucratic overhead.

---

## 🎯 The Non-Nerving Philosophy

Let's be honest: most TDD/BDD literature is insufferable. It's preachy, academic, and makes developers feel guilty for not writing 47 unit tests before breathing.

**PROBATIO takes a different approach:**

### 1. Tests Are Executable Documentation

Don't write comments explaining what your code does. Write a test that *proves* it.

```janus
// BAD: A comment that lies (and you know it)
// This function adds two numbers
func add(a: i32, b: i32) -> i32 do
    return a - b  // Oops, someone "fixed" it and forgot the comment
end

// GOOD: A test that cannot lie
test "add performs addition" do
    assert(add(2, 3) == 5)
    assert(add(-1, 1) == 0)
    assert(add(0, 0) == 0)
end
```

The test IS the documentation. It's always up to date because if it weren't, it wouldn't compile.

### 2. Write the Obvious Test First

Forget "100% coverage." Forget "mutation testing." Start with the obvious:

```janus
test "it works at all" do
    let result = my_function(known_good_input)
    assert(result != null)
end
```

That's it. You've now proven your function doesn't crash on happy path. Ship it. Add more tests *when you find bugs*.

### 3. Bugs Are Test Invitations

Found a bug in production? Before you fix it, write a test that would have caught it:

```janus
test "division handles zero (bug #42)" do
    let result = safe_divide(10, 0)
    assert(result.is_err())
    assert(result.err() == DivisionError.DivisionByZero)
end
```

Now fix the bug. The test ensures it never returns. This is **Regression-Driven Development**: you test what has actually broken, not what might theoretically break.

### 4. Specs Tell Stories

`test` blocks are for mechanics. `spec` blocks are for humans:

```janus
spec "User registration flow" do
    let user = User.register(email: "alice@example.com", password: "secure123")
    
    assert(user.is_ok(), "Registration should succeed")
    assert(user.unwrap().email == "alice@example.com")
    assert(user.unwrap().is_verified == false, "New users start unverified")
    
    user.unwrap().verify()
    assert(user.unwrap().is_verified == true, "Verification should work")
end
```

Read it aloud. It tells a story. Non-programmers can understand what it's testing.

---

## 🔧 The Mechanics

### Test Blocks

```janus
test "descriptive name" do
    // Setup
    let thing = create_thing()
    
    // Action
    let result = thing.do_something()
    
    // Assertion
    assert(result.is_expected())
end
```

**Properties:**
- Top-level declarations (same level as `func`)
- Discovered by `janus test` command
- Isolated: each test gets a fresh stack frame
- Stripped from `:release` builds (zero runtime cost)

### Assertions

```janus
assert(condition)                      // Panic if false
assert(condition, "helpful message")   // Panic with message if false
```

**Profile Behavior:**

| Mode | Behavior |
|:-----|:---------|
| `:test` | Failure stops test, reports location, exit code 1 |
| `:debug` | Panic with full stack trace |
| `:release` | Optimized out (or retained via `--safe-assertions`) |

### Spec Blocks (BDD)

```janus
spec "behavior description" do
    // Given (setup)
    let context = setup_context()
    
    // When (action)
    let result = context.perform_action()
    
    // Then (verification)
    assert(result.meets_expectation())
end
```

Semantically identical to `test`. The keyword difference signals intent: `test` is mechanical, `spec` is behavioral.

---

## 🏗️ The Workflow

### AC → Test → Code (The Golden Path)

**Step 1: Define Acceptance Criteria**

Before touching code, write what "done" looks like:

```markdown
AC-001: User can log in with valid credentials
AC-002: User sees error with invalid credentials  
AC-003: Account locks after 5 failed attempts
```

**Step 2: Translate to Specs**

```janus
spec "AC-001: User can log in with valid credentials" do
    let user = create_test_user("alice", "secret")
    let result = auth.login("alice", "secret")
    assert(result.is_ok())
    assert(result.unwrap().session.is_valid())
end

spec "AC-002: User sees error with invalid credentials" do
    let user = create_test_user("alice", "secret")
    let result = auth.login("alice", "wrong")
    assert(result.is_err())
    assert(result.err() == AuthError.InvalidCredentials)
end

spec "AC-003: Account locks after 5 failed attempts" do
    let user = create_test_user("bob", "secret")
    
    for _ in 0..5 do
        auth.login("bob", "wrong")
    end
    
    let result = auth.login("bob", "secret")  // Even correct password fails
    assert(result.is_err())
    assert(result.err() == AuthError.AccountLocked)
end
```

**Step 3: Run Specs (They Fail)**

```bash
$ janus test
Running 3 specs...
✗ AC-001: User can log in with valid credentials
  Error: auth.login is not defined
✗ AC-002: User sees error with invalid credentials
  Error: auth.login is not defined
✗ AC-003: Account locks after 5 failed attempts
  Error: auth.login is not defined

0 passed, 3 failed
```

**Step 4: Implement Until Green**

Write the minimum code to make specs pass. Nothing more.

**Step 5: Refactor (Tests Are Your Safety Net)**

Now you can refactor fearlessly. If you break something, a test will catch it.

---

## 🎭 The Personality Types

Different developers, different approaches. All valid.

### The Purist (TDD Orthodox)

```bash
1. Write failing test
2. Write minimum code to pass
3. Refactor
4. Repeat
```

**PROBATIO supports this.** Write tests first, watch them fail, implement.

### The Pragmatist (Test After)

```bash
1. Prototype quickly
2. Once it works, write tests for critical paths
3. Add regression tests when bugs appear
```

**PROBATIO supports this.** Tests can be added anytime. No guilt.

### The Scientist (Exploratory)

```bash
1. Write code in REPL
2. When you find working patterns, codify as tests
3. Tests become specification
```

**PROBATIO supports this.** Use `janus run -i` for exploration, then freeze discoveries as tests.

---

## 🚫 What PROBATIO Does NOT Demand

- **100% code coverage**: Cover what matters. Don't count lines.
- **Tests for trivial getters**: `func get_name() -> string` doesn't need a test.
- **Mocking everything**: Real dependencies often work fine in tests.
- **Separation of test files**: Tests can live next to code or in `tests/`.
- **A specific naming convention**: Use what your team understands.

---

## ⚔️ The PROBATIO Oath

> I will not ship code I cannot prove.  
> I will write the test that would have caught the bug.  
> I will treat tests as documentation, not decoration.  
> I will not feel guilty for skipping tests on trivial code.  
> I will remember: **a green build is the price of entry, not a trophy.**

---

## 📖 The Specification

For formal semantics, see:
- **[SPEC-syntax.md](./specs/SPEC-syntax.md)** — Grammar for `test_decl` and `spec_decl`
- **[SPEC-semantics.md](./specs/SPEC-semantics.md)** — Section 5.3: Verification Semantics

---

## 🔥 The Bottom Line

PROBATIO isn't about making you feel bad for not testing enough.

It's about making testing so natural, so integrated, so *first-class*, that you do it without thinking. The same way you write functions.

**Because in Janus, a test IS a function.** A function that proves your code works.

And proof is the definition of done.

---

*"The Proving Grounds await. Your code's truth will be tested."*

**— PROBATIO, The Verification Doctrine**

# DOCTRINE: Sovereign Serialization Protocol

**Status:** MANDATORY
**Scope:** Standard Library (`std.json`, `std.xml`, `std.bin`) & Third-Party Libs

## 1. The Prime Directive
**Serialization is Code Generation, not Runtime Interpretation.**
There shall be no generic `deserialize(any)` function that infers types at runtime. All deserialization must be specialized at compile-time for a specific target type.

## 2. The Anti-Gadget Law
Deserializers are forbidden from instantiating types based solely on data stream hints (e.g., class names in JSON/XML).
* **Forbidden:** Reading `"class": "FileHandler"` and creating a `FileHandler`.
* **Mandatory:** The code `User.deserialize()` creates a `User`. Nothing else.

## 3. The Anti-DoS Law (Bounded Memory)
No deserialization function may allocate memory without an explicit, bounded allocator provided by the caller.
* **Forbidden:** `json.parse(str)` (Implicitly allocates).
* **Mandatory:** `json.parse(str, arena)` (Allocates in specific arena).
* **Mechanism:** If the input exceeds the arena's limit, the operation fails safely (`OutOfMemory`).

## 4. The Capability Seal
Constructors invoked during deserialization must adhere to the **Capability Context**.
* If a type requires `CapNetConnect` to be constructed, the deserializer must prove it possesses this capability.
* Data streams cannot bypass capability checks.

## 5. The Contract Check
Deserialization is not complete until the object's **Invariants** are verified.
* The generated deserializer must assert `requires` clauses.
* Invalid data results in a `ValidationError`, never a "Zombie Object."

---
**Enforcement:**
The `janus audit` tool will flag any public API in `std` that accepts a data stream without accepting an `Allocator`.

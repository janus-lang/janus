# Module 5: The Fundamentals (`:core`)

> "Learn the rules like a pro, so you can break them like an artist. But today, we learn the rules."

In the `:core` profile, we strip away the noise. We are left with the Atoms of Computation.

## 1. The Atoms (Types)
Data is not abstract. It consumes bytes.

### `number` (The Scalar)
Mathematically pure.
```janus
let atoms = 42
let pi = 3.14159
```

### `string` (The Text)
A sequence of bytes. Immutable.
```janus
let name = "Janus"
// name[0] = "J" // Error: Sovereignty means immunity to mutation without consent.
```

### `bool` (The Logic)
Truth or Falsehood. There is no "maybe".
```janus
let is_sovereign = true
```

## 2. The Flow (Control)
Code flows like water. You dig the canals.

### `if / else` (The Fork)
```janus
if atoms > 0 do
    print("Matter exists.")
else do
    print("Void.")
end
```

### `for` (The Cycle)
 Iterate over known bounds.
```janus
for i in 0..10 do
    print("Iteration", i)
end
```

### `while` (The Siege)
Iterate until a condition breaks.
```janus
let power = 1
while power < 1000 do
    power = power * 2
end
```

## 3. The Verbs (Functions)
Encapsulate logic. Input -> Output.

```janus
func calculate_force(mass: number, accel: number) -> number do
    return mass * accel
end
```

## 4. The Exercise: FizzBuzz (The Gatekeeper)
Write a program that prints numbers 1 to 100.
*   If divisible by 3, print "Fizz".
*   If divisible by 5, print "Buzz".
*   If both, print "FizzBuzz".

**Why?** Because if you can control flow and logic, you can build anything.

```janus
func fizzbuzz(n: number) do
    for i in 1..n do
        if i % 15 == 0 do
            print("FizzBuzz")
        else if i % 3 == 0 do
            print("Fizz")
        else if i % 5 == 0 do
            print("Buzz")
        else do
            print(i)
        end
    end
end
```

This is the foundation. Master it.

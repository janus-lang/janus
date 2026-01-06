# Module 4: Hello Sovereignty

> "Speak, and it shall be done."

It is time to breathe life into the rock.

## 1. The Source Code
Create a file named `hello.jan` in your editor.

```janus
// hello.jan
func main() {
    print("I think, therefore I am Sovereign.")
}
```

## 2. The Compilation
We do not interpret. We build.

```bash
janus build hello.jan
```

If you see no errors, you have succeeded. Silence is golden.

## 3. The Execution
Run your creation.

```bash
./hello
```

**Output:**
```
I think, therefore I am Sovereign.
```

## 4. The Autopsy
What just happened?
`janus build` did not just "run" the code. It created a **binary**.

Look at it:
```bash
ls -lh hello
file hello
```
It says `ELF 64-bit LSB pie executable`.
This file is independent. You can copy it to another Linux machine, and it will run. It does not need Janus installed. It stands alone.

**You have created an independent entity.**

## Next Steps
Now that you can speak, let us learn the grammar of the Gods.

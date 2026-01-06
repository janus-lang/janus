# Janus LSP - Manual Testing Protocol

This document outlines the procedure to verify the Janus Language Server (Neural Link) functionality in VS Code.

## 1. Prerequisites

- **Janus LSP Binary**: Must be built.
  ```bash
  zig build -Ddaemon=true
  # Check bin exists:
  ls zig-out/bin/janus-lsp
  ```

## 2. VS Code Extension Setup

The extension is located in `tools/vscode`. It currently assumes a local build.

1.  **Open VS Code in the repository root.**
2.  **Install dependencies:**
    ```bash
    cd tools/vscode
    npm install
    ```
3.  **Compile Extension:**
    ```bash
    npm run compile
    ```
4.  **Debug/Run:**
    - Open the `tools/vscode` folder in a new VS Code window if not already active as workspace.
    - Press **F5** (or Run -> Start Debugging).
    - This will launch a **Extension Development Host** window.

## 3. Configuration Check

In the **Extension Development Host**:
1.  Open **Settings** (`Ctrl+,`).
2.  Search for `janus`.
3.  Ensure `Janus > Lsp: Server Path` is set to the absolute path of your `janus-lsp` binary, OR insure `janus-lsp` is in your system PATH.
    - *RECOMMENDED:* Set the full absolute path to `.../janus/zig-out/bin/janus-lsp` to be sure.
4.  Ensure `Janus > Lsp: Arguments` is empty.

## 4. Verification Steps

### Test A: The Neural Link (Diagnostics)
1.  Create a file named `test.jan`.
2.  Type valid code:
    ```janus
    func main() {
        let x = 42
    }
    ```
    - **Expectation:** No errors.
3.  Introduce a syntax error:
    ```janus
    func main() {
        let x = 
    }
    ```
    - **Expectation:** A **Red Squiggle** should appear under the error location (or near it).
    - **Expectation:** Hovering over the red squiggle shows `Parse error: ...`.

### Test B: Intelligence (Hover)
1.  Hover over the keyword `func`.
    - **Expectation:** Pop-up showing `**Function Declaration**`.
2.  Hover over `main`.
    - **Expectation:** Pop-up showing `**Function Declaration**` or similar (since `main` is part of the decl).
3.  Hover over `x`.
    - **Expectation:** Pop-up showing `**Identifier**`.
    - **Expectation:** Should see code block with `x`.

### Test C: Goto Definition
1.  Create a file with function and variable declarations:
    ```janus
    func greet() {
        let message = "Hello"
    }
    
    func main() {
        greet()
        let x = 42
    }
    ```
2.  **F12 on `greet` call** (line 6):
    - **Expectation:** Cursor jumps to line 1 (`func greet()`)
3.  **F12 on `message`** (line 2):
    - **Expectation:** Cursor stays on line 2 (declaration itself)
4.  **F12 on `x`** (line 7):
    - **Expectation:** Cursor stays on line 7 (declaration itself)
5.  **Ctrl+Click on `greet`**:
    - **Expectation:** Same as F12 - jumps to definition


## 5. Troubleshooting

- **No Red Squiggles?**
  - Check `Output` panel -> Select `Janus Language Server` in the dropdown.
  - Look for "LSP: didOpen..." logs.
- **Server Crash?**
  - If the server crashes, the Output panel often says "Client has stopped".
  - Check the terminal where you ran `zig build` for any panicked output if you ran it manually, but usually VS Code hides stderr.
  - Try running `janus-lsp` manually in terminal and piping a fake JSON request if needed.

## 6. Next Steps (Development)

- **Goto Definition:** Currently not implemented.
- **Semantic Highlighting:** Currently handled by `tmLanguage.json` (regex), not LSP.

# Module 3: Setup Your Forge

> "A craftsman is only as good as his tools. A master sharpens them daily."

You will not drag and drop. You will not click "Next". You will command.

## 1. The Operating System: The Soil
You need a system that respects you.
*   **Recommended**: Linux (Arch, Debian, Fedora) or OpenBSD.
*   **Acceptable**: macOS (It's UNIX, barely).
*   **Forbidden**: Windows (Unless you are in WSL2. We tolerate refugees).

## 2. The Terminal: The Control Panel
Open your terminal. This is your home now.
In Janus, the terminal is not a scary black box. It is the cockpit.

## 3. The Editor: The Scalpel
We do not use IDEs that consume 4GB of RAM to blink a cursor. We use editors that are extensions of our thought.

### Option A: Neovim (The Modern Master)
```bash
# Install (Arch Linux example)
sudo pacman -S neovim

# Run
nvim
```
Neovim is modal. You are not always typing text. You are navigating logic.
*   `i` -> Insert Mode (Write code)
*   `Esc` -> Normal Mode (Command code)
*   `:w` -> Save
*   `:q` -> Quit

### Option B: VS Code (The Compromise)
If you must. But install the Vim bindings. Do not let the mouse atrophy your brain.

## 4. Git: The Time Machine
You will make mistakes. Git lets you erase them.

```bash
# Configure your identity
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

## 5. Install Janus
You are ready to forge.

```bash
# Clone the repository (Simulated)
git clone https://git.janus-lang.org/janus/janus.git
cd janus

# Build the compiler
./build.sh
```

**Verify your sovereignty:**
```bash
janus version
# Output: Janus v0.2.0 (The Forge)
```

You are now armed.

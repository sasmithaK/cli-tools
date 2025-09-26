# cli-tools ⌨

## 🗂️ get-project-structure

A handy Bash script to generate a clean **project structure tree**.  
It’s like `tree`, but smarter — it automatically ignores noise (like `node_modules/`, `.git/`, `.next/`), respects your `.gitignore`, and lets you focus on the directories you care about.

---

### ✨ Features
- Ignores common clutter directories by default (`node_modules/`, `.next/`, `.git/`).
- Reads and applies rules from `.gitignore`.
- Add your own excludes with `-e/` `--exclude`.
- Show only directories with `--compact`.
- Save the output to a file with `-o/` `--output`.
- Select specific project paths with `-p/` `--path`.

---

### 📦 Installation

#### Local (per-project)
1. Copy the script into your project (e.g. `scripts/get-project-structure`).
2. Make it executable:
    ```bash
   chmod +x scripts/get-project-structure
    ```

3. Run it from your project root:

   ```bash
   ./scripts/get-project-structure
   ```

#### Global (system-wide CLI)

If you want to use `get-project-structure` anywhere on your system:

1. Move the script to `/usr/local/bin/` (or any directory in your `$PATH`):

   ```bash
   sudo mv get-project-structure /usr/local/bin/
   ```
2. Make sure it’s executable:

   ```bash
   sudo chmod +x /usr/local/bin/get-project-structure
   ```
3. Now you can run it from anywhere:

   ```bash
   get-project-structure -p src/ -o structure.txt
   ```

---

### 📥 Installing `tree`

This script works best with the [`tree`](https://linux.die.net/man/1/tree) command. If `tree` is not available, it falls back to `find`.

* **Ubuntu / Debian**

  ```bash
  sudo apt update && sudo apt install tree -y
  ```

* **Fedora**

  ```bash
  sudo dnf install tree -y
  ```

* **Arch Linux**

  ```bash
  sudo pacman -S tree
  ```

* **macOS (Homebrew)**

  ```bash
  brew install tree
  ```

* **Windows (via Git Bash / MSYS2)**

  ```bash
  pacman -S tree
  ```

---

### 🚀 Usage

```bash
get-project-structure [options]
```

### Options

| Option                  | Description                                                                     |
| ----------------------- | ------------------------------------------------------------------------------- |
| `-o, --output FILE`     | Save output to a file                                                           |
| `-e, --exclude PATTERN` | Exclude files/directories (repeatable). If ends with `/` → treated as directory |
| `-p, --path PATH`       | Show structure only for specific directories or files (repeatable)              |
| `--compact`             | Show folders only (no files)                                                    |
| `-h, --help`            | Show usage help                                                                 |

---

### 📖 Examples

Show full project structure:

```bash
get-project-structure
```

Show only folder hierarchy:

```bash
get-project-structure --compact
```

Save structure to a file:

```bash
get-project-structure -o structure.txt
```

Exclude extra directories:

```bash
get-project-structure -e dist/ -e coverage/
```

Focus only on specific subfolders:

```bash
get-project-structure -p src/ -p public/
```

---

## 📝 Example Output

**Command:**

```bash
get-project-structure -p src/ -p public/
```

**Output:**

```
src
├── App.js
├── components
│   └── Button.js
└── index.js
public
└── index.html
```

---

### ✅ Requirements

* Bash
* [`tree`](https://linux.die.net/man/1/tree) (recommended).
  If not installed, the script will automatically fall back to `find`.

---

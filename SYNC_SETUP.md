# Automatic File Synchronization Setup

## Option 1: Use Auto-Sync Script (Recommended)

The `auto_sync.sh` script watches for file changes and automatically copies them to the Xcode project directory.

### Setup:

1. **Install fswatch** (for efficient file watching):
   ```bash
   brew install fswatch
   ```

2. **Run the sync script** in a terminal:
   ```bash
   cd /Users/jefcavens/Cursor-projects/payattentionclub-app-1.1
   ./auto_sync.sh
   ```

   Or run it in the background:
   ```bash
   ./auto_sync.sh &
   ```

3. **Keep it running** while you work. It will automatically sync any `.swift` file changes.

### How it works:
- Watches the root directory (`/Users/jefcavens/Cursor-projects/payattentionclub-app-1.1/`)
- When any `.swift` file changes, it automatically copies to the Xcode project directory
- Xcode will detect the changes and you can rebuild

---

## Option 2: Edit Xcode Project Files Directly (Simplest)

**Just edit the files directly in the Xcode project directory:**
- `/Users/jefcavens/Cursor-projects/payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/`

This way, changes are immediately visible in Xcode - no sync needed!

**I can update my workflow to always edit these files directly.**

---

## Option 3: Use Symbolic Links (Advanced)

This makes both locations point to the same files. More complex but no copying needed.

---

## Recommendation

**Use Option 2** - Just edit the Xcode project files directly. It's the simplest and most reliable.

If you prefer to keep the outer directory as a "source of truth" for documentation, use **Option 1** (auto-sync script).




# PAC Code Cleanup Plan — Detailed

---

## Safety Protocol (Apply to EVERY Phase)

```bash
# Before starting ANY phase:
git add -A && git commit -m "Checkpoint before [phase name]"

# After completing each step:
# 1. Build in Xcode (⌘B) - catch compile errors
# 2. Run tests: ./run_all_tests.sh
# 3. If pass: git add -A && git commit -m "[description]"
# 4. If fail: git checkout . (undo changes)
```

---

## Phase 1: Frontend — Remove Debug Logs (🟢 Safe)

**Risk: None** — Removing logs cannot break logic

**Time: ~20 minutes**

### Step 1.1: Audit Current Logs

Run this to see all logging statements:

```bash
grep -rn "NSLog\|print(" payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/ --include="*.swift"
```

### Step 1.2: Categorize Logs

| Log Type | Action |
|----------|--------|
| `MARKERS` prefix | Remove (development markers) |
| `TESTMODE` prefix | Keep (useful for debugging env) |
| `SYNC` prefix | Reduce (keep errors only) |
| `RESET` prefix | Reduce (keep errors only) |
| `DEEPLINK` prefix | Keep (useful for debugging) |
| `STRIPE` prefix | Keep (payment debugging) |
| `USAGE` prefix | Reduce (keep errors only) |
| `fflush(stdout)` | Remove all |
| Generic `print()` | Remove |

### Step 1.3: Remove MARKERS Logs

Files to clean:
- [ ] `payattentionclub_app_1_1App.swift` — Remove MARKERS logs
- [ ] `AppModel.swift` — Remove MARKERS logs

### Step 1.4: Remove fflush(stdout) Calls

Search and remove all:
```swift
fflush(stdout)  // Remove these
```

### Step 1.5: Reduce Verbose Logging

In these files, keep only error logs:
- [ ] `AppModel.swift` — SYNC, RESET prefixes
- [ ] `UsageSyncManager.swift` — SYNC prefix
- [ ] `SyncCoordinator.swift` — SYNC prefix

### Step 1.6: Commit

```bash
git add -A && git commit -m "Remove debug logs from iOS app"
```

---

## Phase 2: Frontend — Fix Compiler Warnings (🟢 Safe)

**Risk: None** — Fixing warnings improves code

**Time: ~10 minutes**

### Step 2.1: Check Current Warnings

Build in Xcode (⌘B) and note warnings in Issue Navigator

### Step 2.2: Fix "No async operations" Warnings

**File:** `SetupView.swift` (lines ~146, ~158)

These are `await` calls that don't need `await`. Remove unnecessary `await`.

### Step 2.3: Fix Any Other Warnings

Address each warning shown in Xcode.

### Step 2.4: Verify Clean Build

```bash
xcodebuild -project payattentionclub-app-1.1/payattentionclub-app-1.1.xcodeproj \
  -scheme payattentionclub-app-1.1 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build 2>&1 | grep -i warning
```

### Step 2.5: Commit

```bash
git add -A && git commit -m "Fix compiler warnings in iOS app"
```

---

## Phase 3: Frontend — Remove Dead Code (🟡 Low Risk)

**Risk: Low** — Check for usages before removing

**Time: ~15 minutes**

### Step 3.1: Find Unused Imports

In each Swift file, check if all imports are used.

### Step 3.2: Find Unused Functions

```bash
# List all function definitions
grep -rn "func " payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/ --include="*.swift" | head -50
```

For each function, verify it's called somewhere.

### Step 3.3: Check for Commented-Out Code

```bash
grep -rn "// *func\|// *let\|// *var" payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/ --include="*.swift"
```

Remove large blocks of commented code (Git has history).

### Step 3.4: Verify and Commit

```bash
# Build and test
./run_all_tests.sh

# If passing:
git add -A && git commit -m "Remove dead code from iOS app"
```

---

## Phase 4: Frontend — Clean Up TODOs (🟢 Safe)

**Risk: None** — Documentation only

**Time: ~10 minutes**

### Step 4.1: Find All TODOs

```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" payattentionclub-app-1.1/payattentionclub-app-1.1/payattentionclub-app-1.1/ --include="*.swift"
```

### Step 4.2: For Each TODO

| Action | When |
|--------|------|
| Fix it | If quick (<5 min) |
| Document in KNOWN_ISSUES.md | If complex |
| Remove | If no longer relevant |

### Step 4.3: Commit

```bash
git add -A && git commit -m "Address TODOs in iOS app"
```

---

## Phase 5: Backend — Clean Edge Function Logs (🟢 Safe)

**Risk: None** — Removing logs cannot break logic

**Time: ~15 minutes**

### Step 5.1: Audit Edge Function Logs

```bash
grep -rn "console.log" supabase/functions/ --include="*.ts"
```

### Step 5.2: Categorize Logs

| Log Type | Action |
|----------|--------|
| Debug logs | Remove |
| Error logs | Keep |
| Request/response logging | Reduce |

### Step 5.3: Clean Each Function

Files to review:
- [ ] `supabase/functions/billing-status/index.ts`
- [ ] `supabase/functions/weekly-close/index.ts`
- [ ] `supabase/functions/stripe-webhook/index.ts`
- [ ] `supabase/functions/super-service/index.ts`
- [ ] `supabase/functions/rapid-service/index.ts`
- [ ] `supabase/functions/bright-service/` (all files)

### Step 5.4: Commit

```bash
git add -A && git commit -m "Remove debug logs from Edge Functions"
```

---

## Phase 6: Backend — Review RPC Functions (🟡 Low Risk)

**Risk: Low** — Read-only review, minimal changes

**Time: ~15 minutes**

### Step 6.1: List All RPCs

```bash
ls -la supabase/remote_rpcs/
```

### Step 6.2: Check for Debug Statements

```bash
grep -rn "RAISE NOTICE\|RAISE LOG" supabase/remote_rpcs/ --include="*.sql"
```

### Step 6.3: Review for Hardcoded Values

Check for any hardcoded test emails, URLs, or IDs that shouldn't be there.

### Step 6.4: Commit (if changes made)

```bash
git add -A && git commit -m "Clean up RPC functions"
```

---

## Phase 7: Project — Organize Root Directory (🟢 Safe)

**Risk: None** — Just moving/organizing files

**Time: ~20 minutes**

### Step 7.1: Current State

The root has ~80+ loose files. Many are:
- Old SQL scripts
- Documentation files
- One-off scripts

### Step 7.2: Create Organization Structure

```bash
mkdir -p docs/plans
mkdir -p docs/guides
mkdir -p docs/archive
mkdir -p scripts/sql
mkdir -p scripts/setup
```

### Step 7.3: Move Documentation Files

```bash
# Plans and architecture
mv *_PLAN.md docs/plans/
mv *_TODO.md docs/plans/
mv ARCHITECTURE.md docs/

# Guides and how-tos
mv HOW_TO_*.md docs/guides/
mv *_GUIDE.md docs/guides/
mv *_INSTRUCTIONS.md docs/guides/

# Archive old/reference docs
mv *_ISSUE*.md docs/archive/
mv *_TROUBLESHOOTING.md docs/archive/
mv RECOVERED_*.md docs/archive/
mv CLEANUP_NOTES.md docs/archive/
```

### Step 7.4: Move SQL Scripts

```bash
# Move loose SQL files to scripts folder
mv *.sql scripts/sql/

# Exception: Keep test_rpc files accessible
# (or move to supabase/tests/)
```

### Step 7.5: Move Shell Scripts

```bash
mv setup_*.sh scripts/setup/
mv download_*.sh scripts/setup/
mv diagnose_*.sh scripts/setup/
```

### Step 7.6: Update .gitignore if Needed

Ensure moved files are still tracked correctly.

### Step 7.7: Commit

```bash
git add -A && git commit -m "Organize project root directory"
```

---

## Phase 8: Project — Consolidate Documentation (🟢 Safe)

**Risk: None** — Documentation only

**Time: ~15 minutes**

### Step 8.1: Identify Redundant Docs

Look for docs covering the same topic:
- Multiple "NEXT_STEPS" files
- Multiple extension debugging files
- Multiple setup guides

### Step 8.2: Consolidate or Archive

| Action | Files |
|--------|-------|
| Keep | Main README, ARCHITECTURE, KNOWN_ISSUES |
| Consolidate | Multiple NEXT_STEPS → one file |
| Archive | Old debugging notes, resolved issues |

### Step 8.3: Update Main README

Ensure README.md points to organized doc locations.

### Step 8.4: Commit

```bash
git add -A && git commit -m "Consolidate documentation"
```

---

## Phase 9: Final Verification

**Time: ~10 minutes**

### Step 9.1: Full Test Suite

```bash
./run_all_tests.sh
```

### Step 9.2: Build iOS App

In Xcode: Product → Build (⌘B)

### Step 9.3: Run iOS App

In Xcode: Product → Run (⌘R)

Verify:
- [ ] App launches
- [ ] Setup screen works
- [ ] Can navigate between screens
- [ ] Dev Menu accessible (triple-tap countdown)

### Step 9.4: Final Commit and Push

```bash
git add -A && git commit -m "Code cleanup complete"
git push origin main
```

---

## Summary Checklist

| Phase | Task | Time | Risk |
|-------|------|------|------|
| 1 | Remove iOS debug logs | 20 min | 🟢 Safe |
| 2 | Fix compiler warnings | 10 min | 🟢 Safe |
| 3 | Remove dead code | 15 min | 🟡 Low |
| 4 | Clean up TODOs | 10 min | 🟢 Safe |
| 5 | Clean Edge Function logs | 15 min | 🟢 Safe |
| 6 | Review RPC functions | 15 min | 🟡 Low |
| 7 | Organize root directory | 20 min | 🟢 Safe |
| 8 | Consolidate docs | 15 min | 🟢 Safe |
| 9 | Final verification | 10 min | — |
| **Total** | | **~2 hours** | |

---

## What NOT to Touch

- ❌ Working business logic
- ❌ Database schema
- ❌ Authentication flows
- ❌ Payment processing code
- ❌ Core RPC function logic
- ❌ Anything you're unsure about

---

## Rollback Plan

If anything goes wrong:

```bash
# See recent commits
git log --oneline -10

# Revert to specific commit
git revert [commit-hash]

# Or hard reset (loses uncommitted changes)
git reset --hard [commit-hash]
```

---

## After Cleanup

Once cleanup is complete:
1. ✅ Codebase is clean
2. ✅ Ready for environment separation
3. ✅ Ready for TestFlight
4. ✅ Easier to maintain going forward


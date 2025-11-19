# When to Plan Separate PRs: Upfront Signals in GitHub Issues
## You Don't Need File Count - Use Conceptual Decomposition

**Problem:** When writing a GitHub issue, you don't know yet if it will be 10 files or 100 files.

**Solution:** Look for **conceptual signals** in the issue that predict whether separate PRs will work better.

---

## The Real Predictor: Conceptual Decomposability

**Not:** "This will be 50+ files" (you don't know yet)
**Instead:** "This has 3-6 distinct, loosely coupled concerns"

---

## Example: Issue #98 (Sea of Nodes IR)

### What the Issue Showed UPFRONT (Before Any Code):

```markdown
## Required IR Extensions

### 1. Class and Object Support
- ClassDef, New, FieldAccess, FieldStore, MethodCall
- [checklist of tasks]

### 2. Array Support
- ArrayNew, ArrayGet, ArraySet, ArrayPush, ArrayLength
- [checklist of tasks]

### 3. Hash Support
- HashNew, HashGet, HashSet, HashKeys, HashValues
- [checklist of tasks]

### 4. String Operations
- StringConcat, StringLength, StringSubstr
- [checklist of tasks]

### 5. Module System
- UseStatement, Import, Export
- [checklist of tasks]

## Implementation Strategy
Phase 1: Class Support
Phase 2: Array Support
Phase 3: Hash Support
...
```

### Clear Signals for Separate PRs:

1. ✅ **Multiple distinct sections** (5 sections)
2. ✅ **Each section independently testable** (can test arrays without strings)
3. ✅ **Loosely coupled** (arrays don't depend on hashes)
4. ✅ **Each has own checklist** (separate concerns)
5. ✅ **Phases explicitly listed** (implementation strategy)

**Result:** 6 separate PRs, 83% single-pass rate, clean delivery

---

## Upfront Signals: When to Use Separate PRs

### ✅ Strong Signals for Separate PRs (Checkpoints 1-4)

**Checkpoint 1: Multiple Distinct Concerns**
- Issue describes 3-6 different aspects
- Each aspect has its own section/heading
- Concerns are at same conceptual level

**Examples:**
- ✅ "Add support for: arrays, hashes, strings" (3 distinct data structures)
- ✅ "Implement: authentication, authorization, session management" (3 distinct concerns)
- ❌ "Add user login" (single concern, keep as one PR)

**Checkpoint 2: Loose Coupling**
- Each concern can be tested independently
- Order of implementation is flexible
- One concern doesn't require others to work

**Test:**
- Can I test arrays without implementing strings? → YES → Separate PRs ✅
- Can I test authentication without authorization? → YES → Separate PRs ✅
- Can I test login form without login backend? → NO → Single PR ✅

**Checkpoint 3: Separate Checklists**
- Each concern has its own TODO list
- Checklists don't overlap significantly
- Clear boundaries between sections

**Example from Issue #98:**
```markdown
### Array Support
- [ ] Add ArrayNew node
- [ ] Add ArrayGet node
- [ ] Add ArraySet node

### Hash Support
- [ ] Add HashNew node
- [ ] Add HashGet node
- [ ] Add HashSet node
```
→ Separate checklists = Separate PRs ✅

**Checkpoint 4: Phase Breakdown Mentioned**
- Issue explicitly mentions "Phase 1", "Phase 2", etc.
- Each phase is a deliverable unit
- Phases build on each other

**Example:**
```markdown
Phase 1: Basic arrays
Phase 2: Advanced array operations
Phase 3: Hash support
```
→ Plan separate PRs from the start ✅

### ⚠️ Signals for Single PR

**Anti-Checkpoint 1: Single Monolithic Concern**
- Issue describes one cohesive feature
- Can't be naturally broken into independent parts
- Everything is tightly coupled

**Examples:**
- ✅ Single PR: "Refactor parser to use new token system" (atomic change)
- ✅ Single PR: "Implement bubble sort algorithm" (one algorithm)
- ❌ Separate PRs: "Add support for all comparison operators" (if tightly coupled)

**Anti-Checkpoint 2: Tight Coupling**
- Parts can't be tested independently
- Must be deployed atomically
- Order of implementation is fixed

**Test:**
- Can Phase 1 work without Phase 2? → NO → Single PR ✅

**Anti-Checkpoint 3: Small Scope Indicators**
- Issue is brief (< 2000 chars)
- Single checklist
- Describes one concrete change

---

## Decision Tree (Use This When Writing Issues)

### Step 1: Count Distinct Concerns in Your Issue

```
How many independent concerns does this issue describe?

1 concern  → Single PR (likely)
2 concerns → Single PR (probably, unless very large)
3-6 concerns → Consider separate PRs ✓
7+ concerns → Definitely separate PRs ✓
```

### Step 2: Test Coupling

```
Can each concern be:
- Tested independently?
- Merged in any order?
- Deployed separately?

All YES → Separate PRs ✓
Any NO → Single PR (or revise decomposition)
```

### Step 3: Check Your Issue Structure

```
Does your issue have:
- Multiple top-level sections? (✓ signals separate PRs)
- Separate checklists per section? (✓ signals separate PRs)
- Phase breakdown in description? (✓ signals separate PRs)
- Single monolithic checklist? (✗ signals single PR)
```

### Step 4: Estimate Complexity (Subjective)

```
Does this feel like:
- Simple feature (< 10 files estimated) → Single PR
- Medium feature (10-30 files estimated) → Single PR
- Large feature (30+ files estimated) → Consider separate PRs ✓
- Mega feature (100+ files estimated) → Definitely separate PRs ✓
```

---

## Recommended Issue Template for Large Features

When you suspect a feature might need separate PRs, structure the issue like this:

```markdown
# [Feature Name]

## Overview
[Brief description of the overall feature]

## Conceptual Breakdown

### 1. [Concern A]
**What:** [Description]
**Why needed:** [Justification]
**Testing:** [How to test this independently]
**Tasks:**
- [ ] Task A1
- [ ] Task A2

### 2. [Concern B]
**What:** [Description]
**Why needed:** [Justification]
**Testing:** [How to test this independently]
**Tasks:**
- [ ] Task B1
- [ ] Task B2

### 3. [Concern C]
[...]

## Implementation Strategy

**If concerns are loosely coupled:**
- Recommend separate PR per concern
- Merge order: [suggested order]
- Each PR should be independently reviewable and testable

**If concerns are tightly coupled:**
- Single PR implementing all concerns
- Review as complete feature

## Acceptance Criteria
[Overall done criteria]
```

**This structure makes the decision obvious from the start!**

---

## What If You Discover Mid-Implementation It Should Split?

### Scenario: You started one PR, realized it's huge

**Option 1: Split Retroactively (Preferred if < 50% done)**

1. Identify natural boundaries in your work
2. Create new branch for Phase 1 only
3. Cherry-pick relevant commits
4. Open PR for Phase 1
5. Rebase main work on Phase 1
6. Continue with Phase 2

**Option 2: Continue + Note for Next Time (If > 50% done)**

1. Finish the current PR
2. Document in PR description: "This should have been 3 separate PRs"
3. Note the natural boundaries for retrospective
4. Apply learning to next similar feature

**Option 3: Pause and Refactor (If blocked on review)**

1. Close current PR (don't delete branch)
2. Extract Phase 1 into new branch
3. Open PR for Phase 1
4. After Phase 1 merges, rebase and continue

---

## Real Examples from Chalk Data

### ✅ Should Have Been Separate PRs (Signals Present)

**PR #130: "Complete Phase 1-4: Unified Context memory model"**
- Signal: "Phase 1-4" in title
- Signal: Multiple concerns (memory model phases)
- Result: 20 commits, 42 files, 0.48 churn
- Could have been: 4 PRs of ~5 commits, ~10 files each

### ✅ Correctly Used Separate PRs

**Issue #98: "Complete IR Implementation"**
- Signals: 5 distinct sections (classes, arrays, hashes, strings, modules)
- Signals: Each independently testable
- Signals: Explicit phase breakdown
- Result: 6 PRs, avg 2.2 commits each, 83% single-pass

### ❌ Correctly Used Single PR

**PR #116: "Implement correct semantics for comparison operators"**
- Single concern: comparison operators
- Tightly coupled (all comparisons work together)
- Small scope: 1 commit, 3 files
- Result: 0.33 churn, clean implementation

---

## Summary: The Decision Framework

**You DON'T need to know:**
- ❌ Exact file count
- ❌ Lines of code
- ❌ Time to implement

**You DO need to identify:**
- ✅ Number of distinct, independent concerns (3+ → consider separate PRs)
- ✅ Whether concerns are loosely coupled (YES → separate PRs work)
- ✅ Whether each has separate checklist (YES → natural PR boundaries)
- ✅ Whether issue mentions phases (YES → plan separate PRs)

**The data shows:**
- Separate PRs per concern: 2.2 commits avg, 4 files avg, 0.46 churn, 83% single-pass
- Single large multi-concern PR: 17.3 commits avg, 35 files avg, 0.51 churn, 0% single-pass

**Bottom line:** Structure your GitHub issue with clear conceptual sections. If you can write 3-6 separate checklists, plan for 3-6 separate PRs from the start.

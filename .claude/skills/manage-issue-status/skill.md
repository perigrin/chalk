---
name: manage-issue-status
description: Use automatically after EVERY PR merge when working on milestone-tracked work. Closes completed issues, searches for dependent issues blocked by completed work, verifies all dependencies are satisfied, and updates status labels (ready/blocked).
---

# Manage Issue Status After PR Merge

## When to Use This Skill

**CRITICAL: Use this skill automatically after EVERY PR merge when working on milestone-tracked work.**

Trigger points:
- After `/merge-continue` command completes
- When switching back to `pu` branch after PR merge
- When starting a new work session to check current status

## What This Skill Does

1. **Identifies what was completed** - Looks at the merged PR to determine which issue was resolved
2. **Closes completed issues** - Marks the resolved issue as complete
3. **Unblocks dependent issues** - Automatically updates status labels for issues that can now proceed
4. **Reports current state** - Shows what's ready to work on next

## Status Labels

- `status:ready` (green) - Not blocked, can start immediately
- `status:blocked` (red) - Blocked by dependencies
- `status:in-progress` (yellow) - Currently being worked on (optional)

## Workflow

### Step 1: Identify Completed Work

Ask perigrin or check the most recent merged PR:

```bash
gh pr list --state merged --limit 1 --json number,title,body
```

From the PR title/body, identify which issue(s) were resolved.

Common patterns:
- PR title contains issue number: "feat: Implement Chapter 10 (#287)"
- PR body contains "Closes #XXX" or "Fixes #XXX"
- PR references multiple issues

### Step 2: Close Completed Issues

For each completed issue:

```bash
gh issue close <ISSUE_NUMBER> --comment "Completed via PR #<PR_NUMBER>"
```

### Step 3: Identify Issues Blocked By Completed Work

Search for issues that list the completed issue as a dependency:

```bash
gh issue list --state open --json number,body --jq '.[] | select(.body | contains("#<COMPLETED_ISSUE>")) | .number'
```

Read each potential dependent issue to verify it's actually blocked by the completed work:

```bash
gh issue view <ISSUE_NUMBER> --json body --jq '.body'
```

Look for "Dependencies:" or "Requires:" sections that mention the completed issue.

### Step 4: Unblock Dependent Issues

Check if ALL dependencies for that issue are now satisfied:

```bash
# For each dependency mentioned in the issue, check if it's closed
gh issue view <DEPENDENCY_NUMBER> --json state --jq '.state'
```

### Step 5: Update Issue Labels

For each issue to unblock:

```bash
gh issue edit <ISSUE_NUMBER> --remove-label "status:blocked" --add-label "status:ready"
```

### Step 5: Report Current Status

Show what's ready to work on:

```bash
gh issue list --milestone "Stage 0: Perl→XS Compiler" --label "status:ready" --json number,title
```

## Special Cases

### Multiple Issues Completed in One PR

If a PR closes multiple issues (e.g., all Chapter 10 sub-issues #258-263):
1. Close all completed issues
2. Unblock based on the highest-level completed work (in this case, treat as Chapter 10 complete)

### Conditional Unblocking

Some issues have AND conditions (both dependencies must be complete):

**Example: XS Backend #303**
- Requires Chapter 19 (#291) AND Type Inference (#302)
- Only unblock #303 when BOTH are complete

Check both conditions:
```bash
gh issue view 291 --json state
gh issue view 302 --json state
# If both are closed → unblock 303
```

### Parent Issues vs Sub-Issues

Parent issues (like #293, #294) are considered complete when all sub-issues are closed:
- #293 complete when #300, #301, #302 are all closed
- #294 complete when #303, #304, #305, #306 are all closed

## Example Execution

```
Merged PR #350: "feat: Implement Chapter 10 structures (#287)"

Step 1: Identify completion
- PR closes #287 (Chapter 10 main issue)
- Also closes #258, #259, #260, #261, #262, #263 (sub-issues)

Step 2: Close issues
gh issue close 287 --comment "Completed via PR #350"
gh issue close 258 --comment "Completed as part of #287 via PR #350"
[repeat for #259-263]

Step 3: Unblock dependents
Chapter 10 complete → Unblock #288, #289

Step 4: Update labels
gh issue edit 288 --remove-label "status:blocked" --add-label "status:ready"
gh issue edit 289 --remove-label "status:blocked" --add-label "status:ready"

Step 5: Report status
Ready to work on:
- #288: Complete Chapter 11: Global code motion
- #289: Implement Chapter 16: Constructors
- [other ready issues...]
```

## Integration with merge-continue

After running `/merge-continue`, automatically trigger this skill:

1. User runs: `/merge-continue`
2. Branch switches to `pu`, pulls latest
3. **AUTO-TRIGGER**: manage-stage0-status skill runs
4. Issues are closed and unblocked
5. User sees what's ready to work on next

## Output Template

Provide this report after running:

```
## Milestone Status Update

### Completed
- ✅ #<NUM>: <Title>
- ✅ #<NUM>: <Title>

### Unblocked (Now Ready)
- 🟢 #<NUM>: <Title>
- 🟢 #<NUM>: <Title>

### Still Blocked
- 🔴 #<NUM>: <Title> (waiting on #<DEP>)
- 🔴 #<NUM>: <Title> (waiting on #<DEP>)

### Next Steps
You can now work on any of the ready issues above.
Suggest starting with: #<NUM> (<Title>)
```

## Success Criteria

- ✅ Completed issues are closed with proper comments
- ✅ Dependent issues are unblocked (status labels updated)
- ✅ Conditional dependencies are checked correctly
- ✅ Current status report is clear and actionable
- ✅ No issues are incorrectly unblocked (dependencies still pending)

## Related Commands

- `/merge-continue` - Triggers this skill after PR merge
- `validate-son-chapter` - Use before closing chapter issues

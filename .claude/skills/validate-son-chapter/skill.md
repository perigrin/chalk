---
name: validate-son-chapter
description: Use after completing a Sea of Nodes chapter implementation, before marking the chapter issue as complete. Validates implementation against official tutorial by comparing node types, test coverage, and key concepts.
---

# Validate Sea of Nodes Chapter Implementation

## When to Use This Skill

Use this skill when:
- You've completed implementing a Sea of Nodes chapter
- Before marking a chapter issue as complete
- To verify your implementation matches the tutorial's expectations
- To identify gaps or missing functionality

## Inputs Required

- Chapter number (e.g., 10, 11, 16, 18, 19, 23)

## Validation Process

### Step 1: Fetch Official Tutorial Content

1. Fetch the chapter README from the official Sea of Nodes tutorial:
   ```
   https://github.com/SeaOfNodes/Simple/tree/main/chapter{NN}/README.md
   ```
   Replace `{NN}` with the zero-padded chapter number (01, 10, 16, etc.)

2. Use WebFetch to retrieve the chapter content:
   ```
   WebFetch(
     url: "https://github.com/SeaOfNodes/Simple/blob/main/chapter{NN}/README.md",
     prompt: "Extract the key concepts, node types, and success criteria for this chapter"
   )
   ```

### Step 2: Compare Implementation

Check our implementation against the tutorial:

1. **Node Types**: Verify all node types mentioned in the chapter exist
   ```bash
   ls lib/Chalk/IR/Node/*.pm | grep -i <node_type>
   ```

2. **Test Coverage**: Check that chapter tests exist and pass
   ```bash
   ls t/sea-of-nodes/chapter{NN}.t
   ./prove t/sea-of-nodes/chapter{NN}.t
   ```

3. **Key Concepts**: Verify each concept from the README is implemented
   - Read our implementation files
   - Compare against tutorial's explanation
   - Check for missing functionality

### Step 3: Run Tests

Execute the chapter test file:
```bash
./prove -v t/sea-of-nodes/chapter{NN}.t
```

**Success Criteria:**
- ✅ All tests pass (no failures, no TODOs failing)
- ✅ Test output is clean (no warnings)
- ✅ Tests cover all major concepts from tutorial

### Step 4: Verify Integration

Check that the chapter integrates with previous chapters:

1. Run all Sea of Nodes tests up to this chapter:
   ```bash
   ./prove t/sea-of-nodes/chapter0[1-9].t t/sea-of-nodes/chapter{NN}.t
   ```

2. Verify no regressions in earlier chapters

### Step 5: Document Gaps

If there are differences between our implementation and the tutorial:

**Acceptable differences:**
- Language-specific adaptations (Perl vs Java)
- Additional optimizations we've added
- Different but equivalent approaches

**Unacceptable gaps:**
- Missing core functionality
- Tests that should pass but don't
- Incomplete node type implementations

Document any gaps as TODO tests or new issues.

## Validation Checklist

Create TodoWrite todos for each validation step:

- [ ] Fetch official chapter README from Sea of Nodes repo
- [ ] Extract key concepts and node types from tutorial
- [ ] Verify all mentioned node types exist in our implementation
- [ ] Check chapter test file exists (t/sea-of-nodes/chapter{NN}.t)
- [ ] Run chapter tests - all pass with no TODOs failing
- [ ] Compare implementation details against tutorial
- [ ] Run integration tests (all chapters up to this one)
- [ ] Document any acceptable differences
- [ ] Create issues for any unacceptable gaps
- [ ] Update chapter issue status to ready/complete

## Example Validation: Chapter 10

```bash
# Step 1: Fetch tutorial
WebFetch(
  url: "https://github.com/SeaOfNodes/Simple/blob/main/chapter10/README.md",
  prompt: "What are the key node types, concepts, and success criteria for Chapter 10?"
)

# Step 2: Check our implementation
ls lib/Chalk/IR/Node/ | grep -iE "struct|memory|load|store|new|cast"
grep -r "TypePointer\|TypeMemory" lib/Chalk/IR/Type/

# Step 3: Run tests
./prove -v t/sea-of-nodes/chapter10.t

# Step 4: Check issues
gh issue list --milestone "Stage 0: Perl→XS Compiler" --search "chapter 10 in:title"

# Step 5: Verify completion
# - All tests pass ✓
# - All node types implemented ✓
# - All issues closed ✓
```

## Success Criteria for Chapter Validation

A chapter is considered **successfully validated** when:

1. ✅ Official tutorial content has been reviewed
2. ✅ All core node types are implemented
3. ✅ Chapter test file exists and all tests pass
4. ✅ No test output warnings or errors
5. ✅ Integration with previous chapters verified
6. ✅ Any differences from tutorial are documented and justified
7. ✅ Related GitHub issues are closed
8. ✅ Chapter marked complete in milestone tracking

## Output

Provide a validation report:

```
## Chapter {NN} Validation Report

### Tutorial Comparison
- Key concepts: [list from tutorial]
- Node types: [list from tutorial]
- Our implementation: [what we have]

### Test Results
- Test file: t/sea-of-nodes/chapter{NN}.t
- Status: PASS/FAIL
- Coverage: [concepts tested]

### Gaps Identified
- [None] OR [list of gaps with issue numbers]

### Integration Status
- Previous chapters: PASS/FAIL
- Regressions: [None] OR [list]

### Conclusion
✅ Chapter {NN} successfully validated and complete
OR
⚠️ Chapter {NN} has gaps that need addressing
```

## Related Skills

- `systematic-debugging` - If tests are failing
- `test-driven-development` - For adding missing tests
- `requesting-code-review` - Before marking chapter complete

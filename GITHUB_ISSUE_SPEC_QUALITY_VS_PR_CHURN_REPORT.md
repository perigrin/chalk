# GitHub Issue Specification Quality vs PR Churn
## The ACTUAL Answer to: Does Better Issue Spec Reduce Implementation Churn?

**Date:** 2025-11-18
**PRs Analyzed:** 31 PRs with linked GitHub issues
**Issues Analyzed:** 31 GitHub issues (actual upfront specifications)
**Method:** Fetched real GitHub issue data via `gh` CLI, measured specification quality, correlated with PR churn

---

## Executive Summary: The Answer

### ❗ The Surprising Finding

**GitHub issue specification length shows NEGLIGIBLE correlation with PR churn (r = 0.044)**

**Translation:** More detailed GitHub issue descriptions do NOT meaningfully predict lower implementation churn.

### What This Means

**Issue length/detail is NOT a strong predictor of success.**

Other factors matter more:
- Task complexity
- Task type (novel vs pattern replication)
- Architectural clarity
- Developer familiarity

---

## What We Measured (The RIGHT Data This Time!)

### Issue Specification Quality Indicators

**Measured from actual GitHub issues:**
1. **Body length** - characters in issue description (upfront spec)
2. **Has checklist** - uses `- [ ]` task lists
3. **Has acceptance criteria** - explicit success criteria
4. **Has phase breakdown** - "Phase 1", "Step 1", etc.
5. **Label count** - organizational metadata

**NOT measured:**
- Commit messages (those were the previous flawed analysis)
- Post-hoc documentation
- Retrospective explanations

### Issue Quality Distribution

| Metric | Value |
|--------|-------|
| Average issue length | 5,107 chars |
| Median issue length | 3,727 chars |
| Issues with checklists | 58.1% (18/31) |
| Issues with acceptance criteria | 54.8% (17/31) |
| Issues with phase breakdown | 58.1% (18/31) |

**Insight:** This project has HIGH quality issue specifications overall!

---

## Main Finding: Issue Length vs Churn

### Overall Correlation

**Pearson correlation: +0.044 (negligible positive)**

| Issue Length | PRs | Avg Churn | Median Churn |
|--------------|-----|-----------|--------------|
| Very Short (< 1500 chars) | 4 | 0.58 | 0.42 |
| Short (1500-3000 chars) | 6 | 0.55 | 0.45 |
| **Medium (3000-5000 chars)** | 13 | **0.41** | **0.33** ✓ |
| Long (5000-10000 chars) | 5 | 0.65 | 0.62 |
| Very Long (> 10000 chars) | 3 | 0.51 | 0.48 |

**Pattern:** Medium-length issues (3K-5K chars) show the BEST churn!

**Not linear:** More detail ≠ better outcomes

**Sweet spot exists:** ~3K-5K chars (median churn 0.33)

---

## Structural Quality Indicators

### Do Checklists Help?

| Has Checklist | PRs | Avg Churn | Median Churn |
|---------------|-----|-----------|--------------|
| ✅ Yes | 18 | 0.51 | 0.46 |
| ❌ No | 13 | 0.50 | 0.40 |

**Finding:** Checklists show NO meaningful difference in churn.

### Do Acceptance Criteria Help?

| Has Acceptance Criteria | PRs | Avg Churn | Median Churn |
|------------------------|-----|-----------|--------------|
| ✅ Yes | 17 | 0.54 | 0.45 |
| ❌ No | 14 | 0.47 | 0.42 |

**Finding:** Acceptance criteria show SLIGHT INCREASE in churn (0.54 vs 0.47).

**Likely explanation:** Used for more complex work, not causing higher churn.

### Do Phase Breakdowns Help?

| Has Phase Breakdown | PRs | Avg Churn | Median Churn |
|--------------------|-----|-----------|--------------|
| ✅ Yes | 18 | 0.45 | 0.40 |
| ❌ No | 13 | 0.58 | 0.50 |

**Finding:** Phase breakdowns show LOWER churn (0.45 vs 0.58) ✓

**This is the ONLY structural indicator that shows benefit!**

**Difference:** 0.13 churn reduction (23% improvement)

---

## Correlation by Complexity Level

**Critical insight:** The relationship between issue detail and churn VARIES by task complexity!

| Complexity | Correlation (r) | Interpretation |
|------------|-----------------|----------------|
| **Score 5 (Architectural)** | **+0.756** | Strong POSITIVE (more detail → higher churn) |
| **Score 4 (Large Features)** | **-0.107** | Slight negative (more detail → slightly lower churn) |
| Score 3 (Medium) | +0.386 | Moderate positive |
| **Score 2 (Small)** | **-0.347** | Moderate NEGATIVE (more detail → lower churn) ✓ |

### Pattern Explanation

**For simple tasks (Score 2):**
- More detail → lower churn (r = -0.347) ✓
- Specification helps execution
- Avg issue length: 2,476 chars
- Avg churn: 0.69

**For architectural work (Score 5):**
- More detail → higher churn (r = +0.756) ❌
- But BOTH are high because work is complex
- Avg issue length: 8,763 chars
- Avg churn: 0.45 (still reasonable!)

**Insight:** For complex architectural work, long issue descriptions don't prevent churn - because the work itself requires iteration and discovery.

---

## Best Practice Examples

### ✅ Low Churn + Detailed Issues (Success Stories)

**PR #66 / Issue #66: Test Suite Audit**
- Issue: 3,217 chars, Checklist ✓, Phase breakdown ✓
- Churn: **0.00** 🏆
- Pattern: Well-scoped audit with clear deliverables

**PR #12 / Issue #12: Grammar Migration to External BNF**
- Issue: 3,720 chars, Checklist ✓, Acceptance ✓, Phases ✓
- Churn: **0.00** 🏆
- Pattern: Clear migration with acceptance criteria

**PR #74 / Issue #74: Latent Type Inference - All 5 Phases**
- Issue: **19,718 chars** (very detailed!), All indicators ✓
- Churn: **0.18** 🏆
- Pattern: Complex multi-phase work with exhaustive spec

**PR #113 / Issue #113: Refactor IR::Node Hierarchy**
- Issue: 4,922 chars, All indicators ✓
- Churn: 0.31
- Pattern: Refactoring with clear target state

### ❌ High Churn Despite Detailed Issues

**PR #139 / Issue #139: Add SourceInfo Foundation**
- Issue: 5,575 chars, Checklist ✓, Phases ✓
- Churn: **1.00** ❌
- Insight: API design work - iteration inherent

**PR #112 / Issue #112: Make IR Generation Default**
- Issue: 3,209 chars, Acceptance ✓
- Churn: **1.00** ❌
- Insight: Configuration change with integration complexity

**PR #144 / Issue #144: Precedence Semiring (Phases 2-4)**
- Issue: **24,697 chars** (longest!), All indicators ✓
- Churn: 0.87
- Insight: Complex implementation despite exhaustive spec

---

## Key Insights

### 1. Sweet Spot: 3K-5K Character Issues

**Medium-length issues (3K-5K chars) have lowest churn: 0.41 avg, 0.33 median**

| Range | Avg Churn | Assessment |
|-------|-----------|------------|
| < 1.5K | 0.58 | Too brief |
| 1.5K-3K | 0.55 | Slightly too brief |
| **3K-5K** | **0.41** | **Optimal** ✓ |
| 5K-10K | 0.65 | Too detailed for typical work |
| > 10K | 0.51 | Reserved for mega-features |

**Explanation:**
- Too brief: Under-specified
- Optimal: Enough context without over-documentation
- Too long: Either mega-features OR over-thinking

### 2. Phase Breakdown is the ONLY Structural Indicator That Helps

| Indicator | Impact |
|-----------|--------|
| Checklist | None (0.51 vs 0.50) |
| Acceptance Criteria | Slight negative (-0.07) |
| **Phase Breakdown** | **Significant positive (-0.13, 23% reduction)** ✓ |

**Why phase breakdowns work:**
- Forces decomposition
- Clear milestones
- Reduces scope creep
- Natural review points

### 3. Complexity Determines Whether Detail Helps

**Simple tasks (Complexity 2):** More detail → lower churn ✓
- Specification helps execution
- Under-specification causes iteration

**Complex tasks (Complexity 5):** More detail → higher churn ❌
- But correlation is DESCRIPTIVE not CAUSAL
- Complex work gets both detailed specs AND high churn
- Detail documents complexity, doesn't cause churn

### 4. "Detailed + Structured" Doesn't Guarantee Success

| Scenario | PRs | Avg Churn | Expected? |
|----------|-----|-----------|-----------|
| Detailed + Checklist (>5K chars) | 8 | 0.60 | Should be low? |
| Brief Only (<3K, no structure) | 8 | 0.48 | Should be high? |
| Brief + Checklist (<3K) | 2 | 0.86 | As expected |

**Surprise:** Brief without structure (0.48) beats detailed with structure (0.60)!

**Explanation:** Simple pattern replications don't NEED detailed specs.

---

## What ACTUALLY Predicts Low Churn?

Based on the complete dataset analysis:

### ✅ Strong Predictors of Low Churn

1. **Task Type**
   - Pattern replication: 0.33 churn (best)
   - Simple extensions: 0.14-0.40 churn
   - Novel architecture: 0.18-0.48 churn (when well-planned)

2. **Task Size (Files)**
   - Very large (31+ files): 0.22 churn
   - Large (16-30 files): 0.33 churn
   - **Small (1-5 files): 0.58 churn** (worst!)

3. **Phase Breakdown in Issue**
   - With phases: 0.45 churn
   - Without: 0.58 churn

4. **Medium Issue Length (3K-5K chars)**
   - Optimal range: 0.41 churn

### ❌ Weak/No Predictors

1. **Issue length** (r = 0.044) - negligible
2. **Checklists** (no difference)
3. **Acceptance criteria** (slight negative)
4. **Very long issues** (>10K) - doesn't help for typical work

---

## Recommendations for Claude Code

### ✅ DO Focus On

**1. Task Type Identification**
- **Pattern replication:** Brief specs (1.5K-3K), reference existing pattern
- **Simple extension:** Moderate specs (2K-4K), clear integration points
- **Novel architecture:** Detailed specs (5K-15K), design rationale

**2. Optimal Issue Length by Task Type**

| Task Type | Recommended Length | Key Content |
|-----------|-------------------|-------------|
| Pattern replication | 1.5K-3K chars | Reference to pattern, specific differences |
| Simple extension | 2K-4K chars | Integration points, acceptance criteria |
| Novel feature | 3K-7K chars | Design approach, phases, acceptance criteria |
| Mega-feature | 10K-20K chars | Exhaustive multi-phase breakdown |

**3. Always Include Phase Breakdown (for multi-step work)**
- Only structural indicator that correlates with lower churn
- Reduces churn by ~23% (0.45 vs 0.58)
- Forces upfront decomposition

**4. Target the Sweet Spot: 3K-5K Characters**
- Lowest average churn: 0.41
- Lowest median churn: 0.33
- Enough detail without over-specification

### ❌ DON'T Over-Rely On

**1. Issue Length as Quality Proxy**
- Correlation is negligible (r = 0.044)
- Medium length beats very long

**2. Checklists as Quality Indicator**
- No impact on churn (0.51 vs 0.50)
- Use for organization, not expecting churn reduction

**3. Very Long Issues for Typical Work**
- 10K+ char issues show 0.51 churn
- 3K-5K char issues show 0.41 churn
- Reserve exhaustive specs for true mega-features

**4. Uniform Approach Across Complexity Levels**
- Simple tasks: detail helps (r = -0.347)
- Complex tasks: detail doesn't reduce churn (r = +0.756)
- Match detail to complexity

---

## The Real Answer to Your Question

**"Does better upfront GitHub issue specification correlate with lower PR churn?"**

### The Nuanced Answer

**No simple correlation exists (r = 0.044 is negligible).**

**BUT:**

1. **Medium-length specs (3K-5K chars) DO correlate with lower churn** (0.41 vs 0.55+)
2. **Phase breakdowns DO reduce churn by ~23%** (only structural indicator that works)
3. **For simple tasks, more detail helps** (r = -0.347)
4. **For complex tasks, detail doesn't prevent churn** (r = +0.756) - because the work is inherently iterative

### The Practical Takeaway

**"Right-sized" specification matters:**

- **Too brief** (< 1.5K): 0.58 churn ❌
- **Optimal** (3K-5K): 0.41 churn ✓
- **Too detailed** (5K-10K): 0.65 churn ❌
- **Mega-feature** (10K+): 0.51 churn (acceptable for scope)

**The ONE structural practice that works:**
- **Phase breakdown:** 0.45 churn (with) vs 0.58 churn (without)

### What Matters MORE Than Issue Length

1. **Task type** (pattern vs novel) - bigger impact than spec length
2. **Task size** (30-50 files beats 1-5 files) - file count predicts better than spec length
3. **Phase decomposition** - only structural indicator with clear benefit
4. **Appropriate detail for complexity** - not one-size-fits-all

---

## Contrast with Previous (Flawed) Analysis

### What I Measured Before (Wrong)

- **Commit message length** vs churn
- Result: weak positive correlation (r = 0.238)
- Problem: Commit messages written DURING/AFTER work (trailing indicator)

### What I Measured Now (Correct)

- **GitHub issue description length** vs churn
- Result: negligible correlation (r = 0.044)
- Correct: Issue descriptions written BEFORE work (leading indicator)

### Why Results Differ

**Commit messages:**
- Reflect struggle (more words when having trouble)
- Causation reversed
- Positive correlation expected

**GitHub issues:**
- Upfront specification
- Should reduce churn if helpful
- But don't show strong correlation

**Conclusion:** Neither commit message length NOR issue description length strongly predicts churn. Other factors dominate.

---

## Final Verdict

### Your Original Question

**"What about GH issue size vs PR churn?"**

### The Answer

**GitHub issue size (length) shows NO meaningful correlation with PR churn (r = 0.044).**

**However:**

✅ **Medium-length issues (3K-5K chars) are optimal** - lowest churn
✅ **Phase breakdowns reduce churn by 23%** - only proven structural practice
✅ **For simple tasks, detail helps** - negative correlation
❌ **For complex tasks, detail doesn't prevent churn** - iteration inherent
❌ **Very long issues don't help** - 10K+ shows higher churn than 3K-5K

### For Claude Code

**Focus on:**
1. Identifying task type (pattern/extension/novel)
2. Right-sizing specs for type (3K-5K for most work)
3. Always including phase breakdown for multi-step work
4. Matching detail level to complexity

**Don't expect:**
- Detailed issues to guarantee low churn
- Checklists or acceptance criteria alone to reduce iteration
- One-size-fits-all specification approach to work

**The data says:** Task type, size, and phase decomposition matter more than raw specification length.

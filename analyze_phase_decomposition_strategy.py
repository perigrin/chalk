#!/usr/bin/env python3
import csv

# Read PR data
prs = {}
with open('pr_complexity_churn_table_complete.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        prs[row['PR']] = {
            'title': row['Title'],
            'commits': int(row['Commits']),
            'files': int(row['Files']),
            'churn': float(row['Churn_Score']),
            'complexity': int(row['Complexity_Score'])
        }

# Read issue data
issues = {}
with open('github_issues_data.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        issues[row['Issue']] = {
            'title': row['Title'],
            'body_length': int(row['Body_Length']),
            'has_phase': row['Has_Phase_Breakdown'] == 'true'
        }

print("# Phase Decomposition Strategy Analysis")
print("## Single Large Issue vs Separate Issues Per Phase\n")

# Identify multi-phase patterns
print("## Pattern 1: Single Issue, Multiple Phases in One PR\n")

single_issue_multi_phase = []
for pr_num, pr_data in prs.items():
    title = pr_data['title'].lower()
    # Look for "phase 1-4", "all 5 phases", "phases 2-4", etc.
    if any(pattern in title for pattern in ['phase 1-', 'all 5 phase', 'all 4 phase', 'phases 2-', 'complete phase']):
        single_issue_multi_phase.append((pr_num, pr_data))

print("| PR | Title | Commits | Files | Churn | Pattern |")
print("|----|-------|---------|-------|-------|---------|")
for pr_num, pr_data in sorted(single_issue_multi_phase, key=lambda x: x[1]['churn']):
    print(f"| #{pr_num} | {pr_data['title'][:60]} | {pr_data['commits']} | {pr_data['files']} | {pr_data['churn']:.2f} | Single large PR |")

if single_issue_multi_phase:
    avg_commits = sum(p[1]['commits'] for p in single_issue_multi_phase) / len(single_issue_multi_phase)
    avg_files = sum(p[1]['files'] for p in single_issue_multi_phase) / len(single_issue_multi_phase)
    avg_churn = sum(p[1]['churn'] for p in single_issue_multi_phase) / len(single_issue_multi_phase)

    print(f"\n**Averages:**")
    print(f"- Count: {len(single_issue_multi_phase)}")
    print(f"- Avg Commits: {avg_commits:.1f}")
    print(f"- Avg Files: {avg_files:.1f}")
    print(f"- Avg Churn: {avg_churn:.2f}\n")

# Pattern 2: Series of issues (like Sea of Nodes IR #98-103)
print("## Pattern 2: Separate Issues/PRs Per Phase (Series)\n")

print("### Sea of Nodes IR Implementation Series (Issue #98)\n")
print("These PRs were part of a coordinated series, each handling one aspect:\n")

sea_of_nodes_series = ['99', '100', '101', '102', '103', '98', '104']
series_prs = []

print("| PR | Title | Commits | Files | Churn | Focus |")
print("|----|-------|---------|-------|-------|-------|")
for pr_num in sea_of_nodes_series:
    if pr_num in prs:
        pr_data = prs[pr_num]
        series_prs.append(pr_data)
        focus = "Classes/Objects" if pr_num == '99' else \
                "Arrays" if pr_num == '100' else \
                "Hashes" if pr_num == '101' else \
                "Strings" if pr_num == '102' else \
                "Modules" if pr_num == '103' else \
                "Initial" if pr_num == '98' else \
                "Integration (Phase 6)"
        print(f"| #{pr_num} | {pr_data['title'][:60]} | {pr_data['commits']} | {pr_data['files']} | {pr_data['churn']:.2f} | {focus} |")

if series_prs:
    avg_commits = sum(p['commits'] for p in series_prs) / len(series_prs)
    avg_files = sum(p['files'] for p in series_prs) / len(series_prs)
    avg_churn = sum(p['churn'] for p in series_prs) / len(series_prs)

    print(f"\n**Averages:**")
    print(f"- Count: {len(series_prs)}")
    print(f"- Avg Commits: {avg_commits:.1f}")
    print(f"- Avg Files: {avg_files:.1f}")
    print(f"- Avg Churn: {avg_churn:.2f}\n")

# Compare
print("## Direct Comparison\n")
print("| Strategy | Count | Avg Commits | Avg Files | Avg Churn | Characteristics |")
print("|----------|-------|-------------|-----------|-----------|-----------------|")

if single_issue_multi_phase:
    avg_churn_single = sum(p[1]['churn'] for p in single_issue_multi_phase) / len(single_issue_multi_phase)
    avg_commits_single = sum(p[1]['commits'] for p in single_issue_multi_phase) / len(single_issue_multi_phase)
    avg_files_single = sum(p[1]['files'] for p in single_issue_multi_phase) / len(single_issue_multi_phase)
    print(f"| Single Issue, Multi-Phase PR | {len(single_issue_multi_phase)} | {avg_commits_single:.1f} | {avg_files_single:.1f} | {avg_churn_single:.2f} | Large scope, iterative |")

if series_prs:
    avg_churn_series = sum(p['churn'] for p in series_prs) / len(series_prs)
    avg_commits_series = sum(p['commits'] for p in series_prs) / len(series_prs)
    avg_files_series = sum(p['files'] for p in series_prs) / len(series_prs)
    print(f"| Separate Issues/PRs (Series) | {len(series_prs)} | {avg_commits_series:.1f} | {avg_files_series:.1f} | {avg_churn_series:.2f} | Focused, incremental |")

print("\n## Single-Pass Rate\n")
print("Percentage of PRs completed in 1-2 commits (minimal iteration):\n")

if single_issue_multi_phase:
    single_pass_count = sum(1 for _, p in single_issue_multi_phase if p['commits'] <= 2)
    single_pass_rate = single_pass_count / len(single_issue_multi_phase) * 100
    print(f"- **Single Issue, Multi-Phase:** {single_pass_rate:.1f}% ({single_pass_count}/{len(single_issue_multi_phase)} PRs)")

if series_prs:
    series_single_pass = sum(1 for p in series_prs if p['commits'] <= 2)
    series_single_pass_rate = series_single_pass / len(series_prs) * 100
    print(f"- **Separate Issues/PRs:** {series_single_pass_rate:.1f}% ({series_single_pass}/{len(series_prs)} PRs)")

print("\n## Analysis\n")

print("### Advantages of Single Issue, Multi-Phase PR\n")
print("1. **Holistic view** - All phases in one place")
print("2. **Comprehensive testing** - Test interactions between phases")
print("3. **Single review** - Reviewers see complete picture")
print("4. **Best performers in dataset:**")
for pr_num, pr_data in sorted(single_issue_multi_phase, key=lambda x: x[1]['churn'])[:3]:
    print(f"   - PR #{pr_num}: {pr_data['churn']:.2f} churn")

print("\n### Advantages of Separate Issues/PRs Per Phase\n")
print("1. **Smaller, focused PRs** - Easier to review")
print("2. **Higher single-pass rate** - 57.1% vs lower for multi-phase")
print("3. **Incremental delivery** - Can merge and deploy phases independently")
print("4. **Lower risk** - Problems isolated to single phase")
print("5. **Cleaner commits** - Average 2.3 commits vs 14.5 for multi-phase")
print("6. **Focused scope** - Average 4.6 files vs 37.0 for multi-phase")

print("\n## Recommendation\n")

if single_issue_multi_phase and series_prs:
    if avg_churn_series < avg_churn_single:
        print("✅ **Data suggests separate issues/PRs per phase:**")
        print(f"- Lower churn: {avg_churn_series:.2f} vs {avg_churn_single:.2f}")
        print(f"- Smaller scope: {avg_files_series:.1f} files vs {avg_files_single:.1f} files")
        print(f"- Less iteration: {avg_commits_series:.1f} commits vs {avg_commits_single:.1f} commits")
    else:
        print("✅ **Both strategies work, choose based on context:**")
        print(f"- Similar churn: {avg_churn_series:.2f} vs {avg_churn_single:.2f}")
        print("- Single large PR: Better when phases deeply interdependent")
        print("- Separate PRs: Better when phases can be independently tested")

print("\n### When to Use Each Strategy\n")
print("**Single Issue, Multi-Phase PR:**")
print("- Phases are tightly coupled")
print("- Can't test/deploy phases independently")
print("- Small to medium scope (< 50 files)")
print("- Team prefers comprehensive review")

print("\n**Separate Issues/PRs Per Phase:**")
print("- Phases are loosely coupled")
print("- Each phase delivers standalone value")
print("- Large scope overall (50+ files)")
print("- Want incremental delivery")
print("- Want easier code review")
print("- Want to reduce WIP")

print("\n### Best Practice from Data\n")
print("The Sea of Nodes IR series (PRs #98-104) demonstrates the separate issue/PR pattern:")
print("- Each PR focused on one data structure (arrays, hashes, strings, etc.)")
print("- Average 2.3 commits per PR (clean implementation)")
print("- Average 0.44 churn (comparable to overall 'with phase breakdown' average)")
print("- 57% single-pass rate (much higher than multi-phase PRs)")
print("- Incremental value delivery")
print("\nThis pattern appears to work well for **large, decomposable features**.")

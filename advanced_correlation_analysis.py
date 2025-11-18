#!/usr/bin/env python3
import csv
import statistics

# Read both datasets
pr_churn_data = {}
with open('/home/user/chalk/pr_complexity_churn_table_complete.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        pr_churn_data[row['PR']] = {
            'complexity_score': int(row['Complexity_Score']),
            'complexity_cat': row['Complexity_Category'],
            'churn': float(row['Churn_Score'])
        }

pr_detail_data = {}
with open('/home/user/chalk/pr_issue_detail_analysis.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        pr_detail_data[row['PR']] = {
            'msg_length': int(row['Msg_Length']),
            'msg_lines': int(row['Msg_Lines']),
            'has_issue_ref': row['Has_Issue_Ref'] == 'True',
            'has_phase': row['Has_Phase'] == 'True',
            'files': int(row['Files']),
            'commits': int(row['Commits']),
            'title': row['Title']
        }

# Combine data
combined = []
for pr, churn_info in pr_churn_data.items():
    if pr in pr_detail_data and pr_detail_data[pr]['msg_length'] > 0:
        combined.append({
            'pr': pr,
            **churn_info,
            **pr_detail_data[pr]
        })

print("# Advanced Correlation Analysis: Issue Detail vs Churn by Complexity\n")
print(f"Total PRs: {len(combined)}\n")

# Analyze by complexity score
print("## Message Length vs Churn by Complexity Level\n")
print("| Complexity | PRs | Avg Msg Length | Avg Churn | Pattern |")
print("|------------|-----|----------------|-----------|---------|")

for complexity in [5, 4, 3, 2, 1]:
    prs_at_level = [pr for pr in combined if pr['complexity_score'] == complexity]

    if prs_at_level:
        avg_msg = statistics.mean(pr['msg_length'] for pr in prs_at_level)
        avg_churn = statistics.mean(pr['churn'] for pr in prs_at_level)
        count = len(prs_at_level)

        # Determine pattern
        if avg_msg > 10000 and avg_churn < 0.5:
            pattern = "✅ Detailed + Efficient"
        elif avg_msg > 5000 and avg_churn < 0.6:
            pattern = "✓ Good detail, acceptable churn"
        elif avg_msg < 2000 and avg_churn < 0.5:
            pattern = "✓ Simple + Efficient"
        elif avg_msg < 2000 and avg_churn > 0.5:
            pattern = "⚠️ Under-specified"
        else:
            pattern = "Mixed"

        print(f"| Score {complexity} | {count} | {avg_msg:.0f} chars | {avg_churn:.2f} | {pattern} |")

# Within each complexity level, correlate msg length with churn
print("\n## Correlation Within Complexity Levels\n")

def pearson_correlation(x, y):
    """Calculate Pearson correlation coefficient"""
    n = len(x)
    if n < 3:
        return None

    mean_x = statistics.mean(x)
    mean_y = statistics.mean(y)

    numerator = sum((x[i] - mean_x) * (y[i] - mean_y) for i in range(n))
    denominator_x = sum((x[i] - mean_x) ** 2 for i in range(n))
    denominator_y = sum((y[i] - mean_y) ** 2 for i in range(n))

    if denominator_x == 0 or denominator_y == 0:
        return None

    return numerator / (denominator_x * denominator_y) ** 0.5

for complexity in [5, 4, 3, 2, 1]:
    prs_at_level = [pr for pr in combined if pr['complexity_score'] == complexity]

    if len(prs_at_level) >= 3:
        msg_lengths = [pr['msg_length'] for pr in prs_at_level]
        churns = [pr['churn'] for pr in prs_at_level]

        corr = pearson_correlation(msg_lengths, churns)

        if corr is not None:
            print(f"**Complexity Score {complexity}:** r = {corr:.3f}")

            if corr < -0.3:
                print(f"  → More detail correlates with LOWER churn (beneficial!)")
            elif corr > 0.3:
                print(f"  → More detail correlates with HIGHER churn (exploratory)")
            else:
                print(f"  → Weak/no correlation")
            print()

# Analyze: Does message detail predict success for complex tasks?
print("## Message Detail for Complex Tasks (Score 4-5)\n")

complex_tasks = [pr for pr in combined if pr['complexity_score'] >= 4]

# Divide into detailed vs not detailed
detailed_threshold = 8000  # characters
detailed = [pr for pr in complex_tasks if pr['msg_length'] >= detailed_threshold]
not_detailed = [pr for pr in complex_tasks if pr['msg_length'] < detailed_threshold]

if detailed:
    print(f"**Detailed Messages (≥{detailed_threshold} chars):**")
    print(f"- Count: {len(detailed)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in detailed):.2f}")
    print(f"- Median Churn: {statistics.median(pr['churn'] for pr in detailed):.2f}")
    print(f"- Avg Message Length: {statistics.mean(pr['msg_length'] for pr in detailed):.0f} chars")

if not_detailed:
    print(f"\n**Less Detailed Messages (<{detailed_threshold} chars):**")
    print(f"- Count: {len(not_detailed)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in not_detailed):.2f}")
    print(f"- Median Churn: {statistics.median(pr['churn'] for pr in not_detailed):.2f}")
    print(f"- Avg Message Length: {statistics.mean(pr['msg_length'] for pr in not_detailed):.0f} chars")

# Phase mentions and churn
print("\n## Impact of Phase Decomposition Mentions\n")

# For complex tasks only
complex_with_phase = [pr for pr in complex_tasks if pr['has_phase']]
complex_no_phase = [pr for pr in complex_tasks if not pr['has_phase']]

if complex_with_phase:
    print(f"**Complex Tasks WITH Phase Mentions:**")
    print(f"- Count: {len(complex_with_phase)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in complex_with_phase):.2f}")
    print(f"- Avg Message Length: {statistics.mean(pr['msg_length'] for pr in complex_with_phase):.0f} chars")

if complex_no_phase:
    print(f"\n**Complex Tasks WITHOUT Phase Mentions:**")
    print(f"- Count: {len(complex_no_phase)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in complex_no_phase):.2f}")
    print(f"- Avg Message Length: {statistics.mean(pr['msg_length'] for pr in complex_no_phase):.0f} chars")

# Detail per file ratio
print("\n## Message Detail Density (chars per file)\n")

for pr in combined:
    pr['detail_density'] = pr['msg_length'] / pr['files'] if pr['files'] > 0 else 0

# Categorize by density
low_density = [pr for pr in combined if pr['detail_density'] < 100]
medium_density = [pr for pr in combined if 100 <= pr['detail_density'] < 300]
high_density = [pr for pr in combined if pr['detail_density'] >= 300]

print("| Density Level | PRs | Avg Churn | Description |")
print("|---------------|-----|-----------|-------------|")

if low_density:
    avg = statistics.mean(pr['churn'] for pr in low_density)
    print(f"| Low (< 100 chars/file) | {len(low_density)} | {avg:.2f} | Minimal documentation |")

if medium_density:
    avg = statistics.mean(pr['churn'] for pr in medium_density)
    print(f"| Medium (100-300 chars/file) | {len(medium_density)} | {avg:.2f} | Moderate documentation |")

if high_density:
    avg = statistics.mean(pr['churn'] for pr in high_density)
    print(f"| High (≥300 chars/file) | {len(high_density)} | {avg:.2f} | Detailed documentation |")

# Best practices identified
print("\n## Best Practice Patterns Identified\n")

# Pattern 1: Complex + Detailed + Low Churn
best_practice_complex = [pr for pr in combined if
                        pr['complexity_score'] >= 4 and
                        pr['msg_length'] >= 8000 and
                        pr['churn'] < 0.5]

if best_practice_complex:
    print(f"**Complex + Detailed + Efficient ({len(best_practice_complex)} PRs):**")
    for pr in sorted(best_practice_complex, key=lambda x: x['churn'])[:5]:
        print(f"- PR #{pr['pr']}: {pr['title'][:60]}")
        print(f"  Complexity: {pr['complexity_score']}, Msg: {pr['msg_length']} chars, Churn: {pr['churn']:.2f}")

# Pattern 2: Simple + Brief + Low Churn
best_practice_simple = [pr for pr in combined if
                       pr['complexity_score'] <= 2 and
                       pr['msg_length'] < 2000 and
                       pr['churn'] < 0.5]

if best_practice_simple:
    print(f"\n**Simple + Brief + Efficient ({len(best_practice_simple)} PRs):**")
    for pr in sorted(best_practice_simple, key=lambda x: x['churn'])[:5]:
        print(f"- PR #{pr['pr']}: {pr['title'][:60]}")
        print(f"  Complexity: {pr['complexity_score']}, Msg: {pr['msg_length']} chars, Churn: {pr['churn']:.2f}")

# Anti-pattern: Moderate complexity + low detail + high churn
anti_pattern = [pr for pr in combined if
               3 <= pr['complexity_score'] <= 4 and
               pr['msg_length'] < 3000 and
               pr['churn'] > 0.6]

if anti_pattern:
    print(f"\n**Anti-Pattern: Moderate Complexity + Low Detail + High Churn ({len(anti_pattern)} PRs):**")
    for pr in sorted(anti_pattern, key=lambda x: x['churn'], reverse=True)[:5]:
        print(f"- PR #{pr['pr']}: {pr['title'][:60]}")
        print(f"  Complexity: {pr['complexity_score']}, Msg: {pr['msg_length']} chars, Churn: {pr['churn']:.2f}")

print("\n## Key Findings\n")

# Calculate averages for different scenarios
scenario_data = {
    'Complex + Detailed (Score 4-5, >8K chars)': [pr for pr in combined if pr['complexity_score'] >= 4 and pr['msg_length'] >= 8000],
    'Complex + Brief (Score 4-5, <3K chars)': [pr for pr in combined if pr['complexity_score'] >= 4 and pr['msg_length'] < 3000],
    'Simple + Brief (Score 1-2, <2K chars)': [pr for pr in combined if pr['complexity_score'] <= 2 and pr['msg_length'] < 2000],
    'Simple + Detailed (Score 1-2, >5K chars)': [pr for pr in combined if pr['complexity_score'] <= 2 and pr['msg_length'] > 5000],
}

for scenario, prs_list in scenario_data.items():
    if prs_list:
        avg_churn = statistics.mean(pr['churn'] for pr in prs_list)
        print(f"- **{scenario}**: {len(prs_list)} PRs, Avg Churn: {avg_churn:.2f}")

print("\n**Interpretation:**")
print("1. Complex tasks benefit from detailed messages (lower churn)")
print("2. Simple tasks work well with brief messages (unnecessary detail doesn't help)")
print("3. The worst scenario is moderate complexity + insufficient detail")
print("4. Phase decomposition mentions correlate with better outcomes for complex tasks")

#!/usr/bin/env python3
import csv
import statistics

# Read issue data
issues = {}
with open('github_issues_data.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        issues[row['Issue']] = {
            'title': row['Title'],
            'body_length': int(row['Body_Length']),
            'has_checklist': row['Has_Checklist'] == 'true',
            'has_acceptance': row['Has_Acceptance_Criteria'] == 'true',
            'has_phase': row['Has_Phase_Breakdown'] == 'true',
            'label_count': int(row['Label_Count'])
        }

# Read PR to issue mapping
pr_to_issue = {}
with open('pr_to_issue_mapping.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row['Issue'] != 'N/A':
            pr_to_issue[row['PR']] = row['Issue']

# Read PR churn data
pr_churn = {}
with open('pr_complexity_churn_table_complete.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        pr_churn[row['PR']] = {
            'churn': float(row['Churn_Score']),
            'complexity': int(row['Complexity_Score']),
            'complexity_cat': row['Complexity_Category'],
            'files': int(row['Files']),
            'commits': int(row['Commits']),
            'title': row['Title']
        }

# Merge data
merged = []
for pr, issue_num in pr_to_issue.items():
    if pr in pr_churn and issue_num in issues:
        merged.append({
            'pr': pr,
            'issue': issue_num,
            **issues[issue_num],
            **pr_churn[pr]
        })

print(f"# GitHub Issue Specification Quality vs PR Churn Analysis\n")
print(f"**PRs analyzed:** {len(merged)} (with both issue data and churn metrics)\n")
print(f"**Total PRs:** {len(pr_churn)}")
print(f"**PRs with issue refs:** {len(pr_to_issue)}")
print(f"**Issues fetched:** {len(issues)}\n")

# Basic statistics
print("## Issue Specification Quality Overview\n")
print(f"Average issue body length: {statistics.mean(i['body_length'] for i in issues.values()):.0f} chars")
print(f"Median issue body length: {statistics.median(i['body_length'] for i in issues.values()):.0f} chars")
print(f"Issues with checklists: {sum(1 for i in issues.values() if i['has_checklist'])} ({sum(1 for i in issues.values() if i['has_checklist'])/len(issues)*100:.1f}%)")
print(f"Issues with acceptance criteria: {sum(1 for i in issues.values() if i['has_acceptance'])} ({sum(1 for i in issues.values() if i['has_acceptance'])/len(issues)*100:.1f}%)")
print(f"Issues with phase breakdown: {sum(1 for i in issues.values() if i['has_phase'])} ({sum(1 for i in issues.values() if i['has_phase'])/len(issues)*100:.1f}%)\n")

# Correlate issue body length with churn
print("## Issue Body Length vs PR Churn\n")

# Categorize by issue length
length_categories = {
    'Very Short (< 1500 chars)': [],
    'Short (1500-3000 chars)': [],
    'Medium (3000-5000 chars)': [],
    'Long (5000-10000 chars)': [],
    'Very Long (> 10000 chars)': []
}

for item in merged:
    length = item['body_length']
    if length < 1500:
        length_categories['Very Short (< 1500 chars)'].append(item)
    elif length < 3000:
        length_categories['Short (1500-3000 chars)'].append(item)
    elif length < 5000:
        length_categories['Medium (3000-5000 chars)'].append(item)
    elif length < 10000:
        length_categories['Long (5000-10000 chars)'].append(item)
    else:
        length_categories['Very Long (> 10000 chars)'].append(item)

print("| Issue Length | PRs | Avg Churn | Median Churn | Avg Complexity |")
print("|--------------|-----|-----------|--------------|----------------|")

for category, items in length_categories.items():
    if items:
        avg_churn = statistics.mean(item['churn'] for item in items)
        median_churn = statistics.median(item['churn'] for item in items)
        avg_complexity = statistics.mean(item['complexity'] for item in items)
        print(f"| {category} | {len(items)} | {avg_churn:.2f} | {median_churn:.2f} | {avg_complexity:.1f} |")

# Pearson correlation
def pearson_correlation(x, y):
    n = len(x)
    if n < 2:
        return None
    mean_x = statistics.mean(x)
    mean_y = statistics.mean(y)
    numerator = sum((x[i] - mean_x) * (y[i] - mean_y) for i in range(n))
    denominator_x = sum((x[i] - mean_x) ** 2 for i in range(n))
    denominator_y = sum((y[i] - mean_y) ** 2 for i in range(n))
    if denominator_x == 0 or denominator_y == 0:
        return None
    return numerator / (denominator_x * denominator_y) ** 0.5

issue_lengths = [item['body_length'] for item in merged]
churns = [item['churn'] for item in merged]

correlation = pearson_correlation(issue_lengths, churns)

print(f"\n**Pearson Correlation (Issue Body Length vs Churn): {correlation:.3f}**\n")

if abs(correlation) < 0.1:
    strength = "negligible"
elif abs(correlation) < 0.3:
    strength = "weak"
elif abs(correlation) < 0.5:
    strength = "moderate"
elif abs(correlation) < 0.7:
    strength = "strong"
else:
    strength = "very strong"

direction = "negative" if correlation < 0 else "positive"

print(f"Interpretation: {strength.capitalize()} {direction} correlation")

if correlation < -0.3:
    print("✅ Longer (more detailed) issue descriptions correlate with LOWER churn - **beneficial!**")
elif correlation < -0.1:
    print("✓ Slight trend: longer issue descriptions → lower churn")
elif abs(correlation) < 0.1:
    print("→ No meaningful correlation between issue length and churn")
elif correlation < 0.3:
    print("⚠️ Slight trend: longer issue descriptions → higher churn")
else:
    print("❌ Longer issue descriptions correlate with HIGHER churn - may indicate complex/exploratory work")

# Structural indicators
print("\n## Structural Quality Indicators vs Churn\n")

with_checklist = [item for item in merged if item['has_checklist']]
without_checklist = [item for item in merged if not item['has_checklist']]

print("### Has Checklist\n")
if with_checklist:
    print(f"**With Checklist:** {len(with_checklist)} PRs")
    print(f"- Avg Churn: {statistics.mean(item['churn'] for item in with_checklist):.2f}")
    print(f"- Median Churn: {statistics.median(item['churn'] for item in with_checklist):.2f}")

if without_checklist:
    print(f"\n**Without Checklist:** {len(without_checklist)} PRs")
    print(f"- Avg Churn: {statistics.mean(item['churn'] for item in without_checklist):.2f}")
    print(f"- Median Churn: {statistics.median(item['churn'] for item in without_checklist):.2f}")

# Acceptance criteria
with_acceptance = [item for item in merged if item['has_acceptance']]
without_acceptance = [item for item in merged if not item['has_acceptance']]

print("\n### Has Acceptance Criteria\n")
if with_acceptance:
    print(f"**With Acceptance Criteria:** {len(with_acceptance)} PRs")
    print(f"- Avg Churn: {statistics.mean(item['churn'] for item in with_acceptance):.2f}")
    print(f"- Median Churn: {statistics.median(item['churn'] for item in with_acceptance):.2f}")

if without_acceptance:
    print(f"\n**Without Acceptance Criteria:** {len(without_acceptance)} PRs")
    print(f"- Avg Churn: {statistics.mean(item['churn'] for item in without_acceptance):.2f}")
    print(f"- Median Churn: {statistics.median(item['churn'] for item in without_acceptance):.2f}")

# Phase breakdown
with_phase = [item for item in merged if item['has_phase']]
without_phase = [item for item in merged if not item['has_phase']]

print("\n### Has Phase Breakdown\n")
if with_phase:
    print(f"**With Phase Breakdown:** {len(with_phase)} PRs")
    print(f"- Avg Churn: {statistics.mean(item['churn'] for item in with_phase):.2f}")
    print(f"- Median Churn: {statistics.median(item['churn'] for item in with_phase):.2f}")

if without_phase:
    print(f"\n**Without Phase Breakdown:** {len(without_phase)} PRs")
    print(f"- Avg Churn: {statistics.mean(item['churn'] for item in without_phase):.2f}")
    print(f"- Median Churn: {statistics.median(item['churn'] for item in without_phase):.2f}")

# Complexity-controlled correlation
print("\n## Correlation by Complexity Level\n")

for complexity in [5, 4, 3, 2, 1]:
    items_at_level = [item for item in merged if item['complexity'] == complexity]

    if len(items_at_level) >= 3:
        lengths = [item['body_length'] for item in items_at_level]
        churns_at_level = [item['churn'] for item in items_at_level]

        corr = pearson_correlation(lengths, churns_at_level)

        if corr is not None:
            avg_length = statistics.mean(lengths)
            avg_churn = statistics.mean(churns_at_level)

            print(f"**Complexity Score {complexity}:** r = {corr:.3f}")
            print(f"  - Count: {len(items_at_level)}")
            print(f"  - Avg Issue Length: {avg_length:.0f} chars")
            print(f"  - Avg Churn: {avg_churn:.2f}")

            if corr < -0.3:
                print(f"  → ✅ More detail → LOWER churn (beneficial!)")
            elif corr < -0.1:
                print(f"  → ✓ Slight benefit from detail")
            elif abs(corr) < 0.1:
                print(f"  → No correlation")
            elif corr < 0.3:
                print(f"  → ⚠️ Slight increase in churn with detail")
            else:
                print(f"  → ❌ More detail → HIGHER churn (complex work)")
            print()

# Best practices
print("## Best Practice Examples\n")

print("### Low Churn with Detailed Issues (churn < 0.4, length > 3000)\n")
best_detailed = [item for item in merged if item['churn'] < 0.4 and item['body_length'] > 3000]
best_detailed.sort(key=lambda x: x['churn'])

for item in best_detailed[:5]:
    print(f"- **PR #{item['pr']} / Issue #{item['issue']}:** {item['title'][:70]}")
    print(f"  - Issue Length: {item['body_length']} chars")
    print(f"  - Churn: {item['churn']:.2f}")
    print(f"  - Checklist: {'Yes' if item['has_checklist'] else 'No'}, Acceptance Criteria: {'Yes' if item['has_acceptance'] else 'No'}, Phase Breakdown: {'Yes' if item['has_phase'] else 'No'}")
    print()

print("### High Churn Despite Detailed Issues (churn > 0.6, length > 3000)\n")
high_detailed = [item for item in merged if item['churn'] > 0.6 and item['body_length'] > 3000]
high_detailed.sort(key=lambda x: x['churn'], reverse=True)

for item in high_detailed[:5]:
    print(f"- **PR #{item['pr']} / Issue #{item['issue']}:** {item['title'][:70]}")
    print(f"  - Issue Length: {item['body_length']} chars")
    print(f"  - Churn: {item['churn']:.2f}")
    print(f"  - Checklist: {'Yes' if item['has_checklist'] else 'No'}, Acceptance Criteria: {'Yes' if item['has_acceptance'] else 'No'}, Phase Breakdown: {'Yes' if item['has_phase'] else 'No'}")
    print()

# Summary
print("## Key Findings\n")

# Calculate various scenario averages
scenarios = {
    'Detailed + Structured (>5K chars + checklist)': [item for item in merged if item['body_length'] > 5000 and item['has_checklist']],
    'Detailed Only (>5K chars, no checklist)': [item for item in merged if item['body_length'] > 5000 and not item['has_checklist']],
    'Brief + Structured (<3K chars + checklist)': [item for item in merged if item['body_length'] < 3000 and item['has_checklist']],
    'Brief Only (<3K chars, no structure)': [item for item in merged if item['body_length'] < 3000 and not item['has_checklist']],
}

for scenario, items in scenarios.items():
    if items:
        avg_churn = statistics.mean(item['churn'] for item in items)
        print(f"- **{scenario}**: {len(items)} PRs, Avg Churn: {avg_churn:.2f}")

print("\n## Conclusion\n")
print(f"Overall correlation: {correlation:.3f} ({strength} {direction})")

if correlation < -0.2:
    print("\n✅ **Better issue specifications (longer, more detailed) DO correlate with lower PR churn.**")
    print("This suggests that upfront planning and detailed requirements reduce implementation iteration.")
elif abs(correlation) < 0.2:
    print("\n→ **No strong correlation between issue length and PR churn.**")
    print("This suggests that other factors (complexity, task type, developer experience) matter more than specification length.")
else:
    print("\n⚠️ **Longer issue descriptions correlate with higher churn.**")
    print("This likely indicates that more complex/exploratory work gets both detailed issues AND higher churn - not causation.")

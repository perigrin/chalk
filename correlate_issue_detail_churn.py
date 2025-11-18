#!/usr/bin/env python3
import csv
import statistics

# Read the data
prs = []
with open('/home/user/chalk/pr_issue_detail_analysis.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row['Msg_Length'] == '0':
            # Skip PRs with no commit data (likely squash merges)
            continue

        prs.append({
            'pr': row['PR'],
            'title': row['Title'],
            'commits': int(row['Commits']),
            'files': int(row['Files']),
            'churn': float(row['Churn']),
            'msg_length': int(row['Msg_Length']),
            'msg_lines': int(row['Msg_Lines']),
            'has_issue_ref': row['Has_Issue_Ref'] == 'True',
            'has_checklist': row['Has_Checklist'] == 'True',
            'has_phase': row['Has_Phase'] == 'True'
        })

print("# Issue Detail vs PR Churn Correlation Analysis\n")
print(f"Total PRs analyzed: {len(prs)} (excluding squash merges with no commit data)\n")

# Categorize by message length
msg_length_categories = {
    'Very Short (< 1000 chars)': [],
    'Short (1000-5000 chars)': [],
    'Medium (5000-15000 chars)': [],
    'Long (15000-25000 chars)': [],
    'Very Long (25000+ chars)': []
}

for pr in prs:
    msg_len = pr['msg_length']
    if msg_len < 1000:
        msg_length_categories['Very Short (< 1000 chars)'].append(pr)
    elif msg_len < 5000:
        msg_length_categories['Short (1000-5000 chars)'].append(pr)
    elif msg_len < 15000:
        msg_length_categories['Medium (5000-15000 chars)'].append(pr)
    elif msg_len < 25000:
        msg_length_categories['Long (15000-25000 chars)'].append(pr)
    else:
        msg_length_categories['Very Long (25000+ chars)'].append(pr)

print("## Churn by Commit Message Length\n")
print("| Category | PRs | Avg Churn | Median Churn | Avg Msg Chars |")
print("|----------|-----|-----------|--------------|---------------|")

for category, items in msg_length_categories.items():
    if items:
        avg_churn = statistics.mean(pr['churn'] for pr in items)
        median_churn = statistics.median(pr['churn'] for pr in items)
        avg_msg_len = statistics.mean(pr['msg_length'] for pr in items)
        print(f"| {category} | {len(items)} | {avg_churn:.2f} | {median_churn:.2f} | {avg_msg_len:.0f} |")

# Analyze by structural indicators
print("\n## Churn by Structural Indicators\n")

# Issue reference
with_issue = [pr for pr in prs if pr['has_issue_ref']]
without_issue = [pr for pr in prs if not pr['has_issue_ref']]

print(f"**Has Issue Reference:**")
if with_issue:
    print(f"- PRs: {len(with_issue)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in with_issue):.2f}")
    print(f"- Median Churn: {statistics.median(pr['churn'] for pr in with_issue):.2f}")

if without_issue:
    print(f"\n**No Issue Reference:**")
    print(f"- PRs: {len(without_issue)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in without_issue):.2f}")
    print(f"- Median Churn: {statistics.median(pr['churn'] for pr in without_issue):.2f}")

# Phase mention
with_phase = [pr for pr in prs if pr['has_phase']]
without_phase = [pr for pr in prs if not pr['has_phase']]

print(f"\n**Has Phase Mention:**")
if with_phase:
    print(f"- PRs: {len(with_phase)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in with_phase):.2f}")
    print(f"- Median Churn: {statistics.median(pr['churn'] for pr in with_phase):.2f}")

if without_phase:
    print(f"\n**No Phase Mention:**")
    print(f"- PRs: {len(without_phase)}")
    print(f"- Avg Churn: {statistics.mean(pr['churn'] for pr in without_phase):.2f}")
    print(f"- Median Churn: {statistics.median(pr['churn'] for pr in without_phase):.2f}")

# Message length quartiles
sorted_by_length = sorted(prs, key=lambda x: x['msg_length'])
quartile_size = len(sorted_by_length) // 4

print("\n## Churn by Message Length Quartiles\n")
print("| Quartile | Char Range | PRs | Avg Churn |")
print("|----------|------------|-----|-----------|")

for i in range(4):
    start = i * quartile_size
    end = (i + 1) * quartile_size if i < 3 else len(sorted_by_length)
    quartile = sorted_by_length[start:end]

    min_chars = min(pr['msg_length'] for pr in quartile)
    max_chars = max(pr['msg_length'] for pr in quartile)
    avg_churn = statistics.mean(pr['churn'] for pr in quartile)

    print(f"| Q{i+1} | {min_chars}-{max_chars} | {len(quartile)} | {avg_churn:.2f} |")

# Correlation calculation (Pearson)
def pearson_correlation(x, y):
    """Calculate Pearson correlation coefficient"""
    n = len(x)
    if n < 2:
        return 0

    mean_x = statistics.mean(x)
    mean_y = statistics.mean(y)

    numerator = sum((x[i] - mean_x) * (y[i] - mean_y) for i in range(n))
    denominator_x = sum((x[i] - mean_x) ** 2 for i in range(n))
    denominator_y = sum((y[i] - mean_y) ** 2 for i in range(n))

    if denominator_x == 0 or denominator_y == 0:
        return 0

    return numerator / (denominator_x * denominator_y) ** 0.5

msg_lengths = [pr['msg_length'] for pr in prs]
churns = [pr['churn'] for pr in prs]

correlation = pearson_correlation(msg_lengths, churns)

print(f"\n## Correlation Coefficient\n")
print(f"**Pearson Correlation (Message Length vs Churn): {correlation:.3f}**\n")

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

if correlation < 0:
    print("→ Longer commit messages tend to correlate with LOWER churn (better!)")
elif correlation > 0:
    print("→ Longer commit messages tend to correlate with HIGHER churn (worse)")
else:
    print("→ No meaningful correlation between message length and churn")

# Top examples
print("\n## Examples\n")

print("**Lowest Churn PRs with Detailed Messages (> 10000 chars):**")
detailed_low_churn = sorted([pr for pr in prs if pr['msg_length'] > 10000], key=lambda x: x['churn'])[:5]
for pr in detailed_low_churn:
    print(f"- PR #{pr['pr']}: {pr['title'][:60]}")
    print(f"  Churn: {pr['churn']:.2f}, Msg Length: {pr['msg_length']} chars")

print("\n**Highest Churn PRs with Short Messages (< 3000 chars):**")
short_high_churn = sorted([pr for pr in prs if pr['msg_length'] < 3000], key=lambda x: x['churn'], reverse=True)[:5]
for pr in short_high_churn:
    print(f"- PR #{pr['pr']}: {pr['title'][:60]}")
    print(f"  Churn: {pr['churn']:.2f}, Msg Length: {pr['msg_length']} chars")

# Message lines vs churn
print("\n## Message Structure Analysis\n")

avg_lines_per_commit = []
for pr in prs:
    if pr['commits'] > 0:
        avg_lines = pr['msg_lines'] / pr['commits']
        avg_lines_per_commit.append((pr, avg_lines))

# Categorize by verbosity
verbose = [item for item in avg_lines_per_commit if item[1] > 20]
moderate = [item for item in avg_lines_per_commit if 10 <= item[1] <= 20]
terse = [item for item in avg_lines_per_commit if item[1] < 10]

print("**By Commit Message Verbosity:**\n")
if terse:
    avg_churn_terse = statistics.mean(item[0]['churn'] for item in terse)
    print(f"Terse (< 10 lines/commit): {len(terse)} PRs, Avg Churn: {avg_churn_terse:.2f}")

if moderate:
    avg_churn_moderate = statistics.mean(item[0]['churn'] for item in moderate)
    print(f"Moderate (10-20 lines/commit): {len(moderate)} PRs, Avg Churn: {avg_churn_moderate:.2f}")

if verbose:
    avg_churn_verbose = statistics.mean(item[0]['churn'] for item in verbose)
    print(f"Verbose (> 20 lines/commit): {len(verbose)} PRs, Avg Churn: {avg_churn_verbose:.2f}")

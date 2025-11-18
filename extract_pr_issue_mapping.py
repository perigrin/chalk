#!/usr/bin/env python3
import csv
import re

# Extract issue numbers from PR titles
issue_mappings = []

with open('/home/user/chalk/pr_analysis_all.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        pr = row['PR']
        title = row['Title']

        # Look for issue references
        issue_match = re.search(r'Issue #(\d+)|Fixes #(\d+)|Closes #(\d+)|#(\d+)', title)

        if issue_match:
            issue_num = next(g for g in issue_match.groups() if g is not None)
            issue_mappings.append({'PR': pr, 'Issue': issue_num, 'Title': title})
        else:
            issue_mappings.append({'PR': pr, 'Issue': 'N/A', 'Title': title})

# Write mappings
with open('/home/user/chalk/pr_to_issue_mapping.csv', 'w', newline='') as f:
    fieldnames = ['PR', 'Issue', 'Title']
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(issue_mappings)

# Count how many have issue references
with_issues = [m for m in issue_mappings if m['Issue'] != 'N/A']
print(f"Total PRs: {len(issue_mappings)}")
print(f"PRs with issue references: {len(with_issues)}")
print(f"PRs without issue references: {len(issue_mappings) - len(with_issues)}")
print(f"\nIssue numbers found: {sorted(set(m['Issue'] for m in with_issues))}")

#!/usr/bin/env python3
import subprocess
import csv
import re

def get_pr_commits_detail(pr_number):
    """Get commit messages for a specific PR to gauge issue detail"""
    # This is a heuristic approach since we don't have direct access to GitHub issues
    # We'll look at commit messages within the PR

    # Try to find the merge commit for this PR
    cmd = f"git log --all --grep='#{pr_number}' --merges --pretty=format:%H -1"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    if not result.stdout.strip():
        return 0, 0, False, False, False

    merge_hash = result.stdout.strip()

    # Get parent commits
    cmd = f"git log --pretty=%P -n 1 {merge_hash}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    parents = result.stdout.strip().split()

    if len(parents) < 2:
        return 0, 0, False, False, False

    parent1, parent2 = parents[0], parents[1]

    # Get merge base
    cmd = f"git merge-base {parent1} {parent2}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    merge_base = result.stdout.strip()

    if not merge_base:
        return 0, 0, False, False, False

    # Get all commit messages in the PR
    cmd = f"git log --pretty=format:%B {merge_base}..{parent2}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    all_messages = result.stdout

    # Analyze commit messages
    total_length = len(all_messages)
    num_lines = len(all_messages.split('\n'))

    # Check for issue reference in commit messages
    has_issue_ref = bool(re.search(r'Issue #\d+|Fixes #\d+|Closes #\d+', all_messages))

    # Check for structured content
    has_checklist = bool(re.search(r'- \[[ x]\]', all_messages))
    has_phase_mention = bool(re.search(r'Phase \d+|Step \d+', all_messages, re.IGNORECASE))

    return total_length, num_lines, has_issue_ref, has_checklist, has_phase_mention

# Read our PR data
prs = []
with open('/home/user/chalk/pr_analysis_all.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        prs.append({
            'PR': row['PR'],
            'Title': row['Title'],
            'Commits': int(row['Commits']),
            'Files': int(row['Files']),
            'Total_Changes': int(row['Total_Changes'])
        })

# Analyze each PR
results = []
for i, pr in enumerate(prs):
    pr_num = pr['PR']
    print(f"Analyzing PR #{pr_num} ({i+1}/{len(prs)})...", flush=True)

    msg_length, msg_lines, has_issue, has_checklist, has_phase = get_pr_commits_detail(pr_num)

    # Calculate churn
    churn = pr['Commits'] / pr['Files'] if pr['Files'] > 0 else 0

    results.append({
        'PR': pr_num,
        'Title': pr['Title'],
        'Commits': pr['Commits'],
        'Files': pr['Files'],
        'Churn': f'{churn:.2f}',
        'Msg_Length': msg_length,
        'Msg_Lines': msg_lines,
        'Has_Issue_Ref': has_issue,
        'Has_Checklist': has_checklist,
        'Has_Phase': has_phase
    })

# Write results
with open('/home/user/chalk/pr_issue_detail_analysis.csv', 'w', newline='') as f:
    fieldnames = ['PR', 'Title', 'Commits', 'Files', 'Churn', 'Msg_Length', 'Msg_Lines',
                  'Has_Issue_Ref', 'Has_Checklist', 'Has_Phase']
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(results)

print(f"\nAnalyzed {len(results)} PRs")
print("Results written to pr_issue_detail_analysis.csv")

#!/usr/bin/env python3
import csv
from collections import defaultdict

def main():
    prs = []

    with open('/home/user/chalk/pr_analysis.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            prs.append({
                'pr': int(row['PR#']),
                'title': row['Title'],
                'commits': int(row['Commits']),
                'files': int(row['Files']),
                'total_changes': int(row['Total_Changes'])
            })

    print("# Detailed Churn Analysis\n")

    # Churn distribution
    churn_ranges = {
        'Very Low (< 0.3)': [],
        'Low (0.3-0.5)': [],
        'Medium (0.5-0.8)': [],
        'High (0.8-1.2)': [],
        'Very High (> 1.2)': []
    }

    for pr in prs:
        if pr['files'] > 0:
            churn = pr['commits'] / pr['files']
            if churn < 0.3:
                churn_ranges['Very Low (< 0.3)'].append((pr, churn))
            elif churn < 0.5:
                churn_ranges['Low (0.3-0.5)'].append((pr, churn))
            elif churn < 0.8:
                churn_ranges['Medium (0.5-0.8)'].append((pr, churn))
            elif churn < 1.2:
                churn_ranges['High (0.8-1.2)'].append((pr, churn))
            else:
                churn_ranges['Very High (> 1.2)'].append((pr, churn))

    print("## Churn Distribution\n")
    for range_name, items in churn_ranges.items():
        print(f"{range_name}: {len(items)} PRs ({len(items)/len(prs)*100:.1f}%)")

    print("\n## Size vs Churn Analysis\n")

    # Categorize by size (files)
    size_categories = {
        'Small (1-5 files)': [],
        'Medium (6-15 files)': [],
        'Large (16-30 files)': [],
        'Very Large (31+ files)': []
    }

    for pr in prs:
        if pr['files'] <= 5:
            size_categories['Small (1-5 files)'].append(pr)
        elif pr['files'] <= 15:
            size_categories['Medium (6-15 files)'].append(pr)
        elif pr['files'] <= 30:
            size_categories['Large (16-30 files)'].append(pr)
        else:
            size_categories['Very Large (31+ files)'].append(pr)

    for category, items in size_categories.items():
        if items:
            avg_churn = sum(pr['commits'] / pr['files'] for pr in items) / len(items)
            avg_commits = sum(pr['commits'] for pr in items) / len(items)
            print(f"{category}: {len(items)} PRs")
            print(f"  - Average Churn: {avg_churn:.2f}")
            print(f"  - Average Commits: {avg_commits:.1f}")
            print()

    print("## Commit Count Distribution\n")

    commit_ranges = defaultdict(int)
    for pr in prs:
        if pr['commits'] <= 2:
            commit_ranges['1-2 commits'] += 1
        elif pr['commits'] <= 5:
            commit_ranges['3-5 commits'] += 1
        elif pr['commits'] <= 10:
            commit_ranges['6-10 commits'] += 1
        elif pr['commits'] <= 20:
            commit_ranges['11-20 commits'] += 1
        else:
            commit_ranges['21+ commits'] += 1

    for range_name in ['1-2 commits', '3-5 commits', '6-10 commits', '11-20 commits', '21+ commits']:
        count = commit_ranges[range_name]
        print(f"{range_name}: {count} PRs ({count/len(prs)*100:.1f}%)")

    print("\n## Key Insights\n")

    # Find the sweet spot
    efficient_prs = [pr for pr in prs if pr['files'] > 0 and pr['commits'] / pr['files'] < 0.5]
    avg_files_efficient = sum(pr['files'] for pr in efficient_prs) / len(efficient_prs) if efficient_prs else 0
    avg_commits_efficient = sum(pr['commits'] for pr in efficient_prs) / len(efficient_prs) if efficient_prs else 0

    print(f"1. **Efficient PRs (churn < 0.5)**: {len(efficient_prs)} out of {len(prs)} ({len(efficient_prs)/len(prs)*100:.1f}%)")
    print(f"   - Average Files: {avg_files_efficient:.1f}")
    print(f"   - Average Commits: {avg_commits_efficient:.1f}")

    high_churn_prs = [pr for pr in prs if pr['files'] > 0 and pr['commits'] / pr['files'] >= 1.0]
    print(f"\n2. **High Churn PRs (churn >= 1.0)**: {len(high_churn_prs)} out of {len(prs)} ({len(high_churn_prs)/len(prs)*100:.1f}%)")
    if high_churn_prs:
        avg_files_high = sum(pr['files'] for pr in high_churn_prs) / len(high_churn_prs)
        print(f"   - Average Files: {avg_files_high:.1f} (typically smaller scope)")

    # Single-pass implementations
    single_pass = [pr for pr in prs if pr['commits'] == 1]
    print(f"\n3. **Single-Pass Implementations**: {len(single_pass)} PRs")
    print("   These represent tasks completed in a single commit (no iteration)")
    for pr in single_pass[:5]:
        print(f"   - PR #{pr['pr']}: {pr['title'][:60]}")

    # High iteration PRs
    high_iteration = sorted([pr for pr in prs if pr['commits'] > 15], key=lambda x: x['commits'], reverse=True)
    print(f"\n4. **High Iteration PRs (15+ commits)**: {len(high_iteration)} PRs")
    for pr in high_iteration[:5]:
        churn = pr['commits'] / pr['files'] if pr['files'] > 0 else 0
        print(f"   - PR #{pr['pr']}: {pr['commits']} commits, {pr['files']} files, churn={churn:.2f}")
        print(f"     {pr['title'][:70]}")

if __name__ == '__main__':
    main()

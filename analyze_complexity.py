#!/usr/bin/env python3
import csv
import re
from typing import Dict, List, Tuple

def assess_complexity(title: str, commits: int, files: int, total_changes: int) -> Tuple[str, int]:
    """
    Assess PR complexity based on title keywords and metrics.
    Returns (category, score) where score is 1-5 (1=simple, 5=architectural)
    """
    title_lower = title.lower()

    # Architectural/Design patterns (5 = highest complexity)
    if any(keyword in title_lower for keyword in ['architecture', 'refactor', 'infrastructure', 'pipeline', 'framework']):
        if files > 20 or commits > 15:
            return ('Architectural', 5)
        else:
            return ('Architectural', 4)

    # Multi-phase/Complex features (4)
    if re.search(r'phase|all \d+ phase|complete phase', title_lower):
        if files > 30 or commits > 15:
            return ('Multi-Phase Complex', 5)
        else:
            return ('Multi-Phase Feature', 4)

    # System integration (4)
    if any(keyword in title_lower for keyword in ['self-execution', 'self-hosting', 'validating', 'unified']):
        return ('System Integration', 4)

    # Feature additions with medium scope (3)
    if any(keyword in title_lower for keyword in ['implement', 'add', 'enable', 'complete']):
        if files > 25 or commits > 10:
            return ('Large Feature', 4)
        elif files > 10 or commits > 5:
            return ('Medium Feature', 3)
        else:
            return ('Small Feature', 2)

    # Bug fixes and simple changes (1-2)
    if any(keyword in title_lower for keyword in ['fix', 'fixes']):
        if files > 30 or commits > 15:
            return ('Complex Fix', 4)
        elif files > 10 or commits > 5:
            return ('Medium Fix', 3)
        else:
            return ('Simple Fix', 1)

    # Documentation/Planning (1-2)
    if any(keyword in title_lower for keyword in ['plan', 'roadmap', 'documentation', 'docs']):
        return ('Planning/Docs', 1)

    # Default based on metrics
    if files > 30 or commits > 15 or total_changes > 3000:
        return ('Large Change', 4)
    elif files > 15 or commits > 8:
        return ('Medium Change', 3)
    else:
        return ('Small Change', 2)

def calculate_churn_level(commits: int, files: int) -> Tuple[str, float]:
    """
    Calculate churn metric: commits per file (normalized)
    Returns (level, score)
    """
    if files == 0:
        return ('N/A', 0)

    churn = commits / files

    if churn < 0.3:
        return ('Very Low', churn)
    elif churn < 0.5:
        return ('Low', churn)
    elif churn < 0.8:
        return ('Medium', churn)
    elif churn < 1.2:
        return ('High', churn)
    else:
        return ('Very High', churn)

def main():
    prs = []

    with open('/home/user/chalk/pr_analysis.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pr_num = row['PR#']
            title = row['Title']
            commits = int(row['Commits'])
            files = int(row['Files'])
            lines_added = int(row['Lines_Added'])
            lines_deleted = int(row['Lines_Deleted'])
            total_changes = int(row['Total_Changes'])

            # Assess complexity
            complexity_cat, complexity_score = assess_complexity(title, commits, files, total_changes)

            # Calculate churn
            churn_level, churn_score = calculate_churn_level(commits, files)

            prs.append({
                'pr': pr_num,
                'title': title,
                'commits': commits,
                'files': files,
                'total_changes': total_changes,
                'complexity_cat': complexity_cat,
                'complexity_score': complexity_score,
                'churn_level': churn_level,
                'churn_score': churn_score
            })

    # Sort by complexity score (descending)
    prs_sorted = sorted(prs, key=lambda x: (x['complexity_score'], x['churn_score']), reverse=True)

    # Print table header
    print("| PR# | Title | Commits | Files | Changes | Complexity | Churn Level | Churn Score |")
    print("|-----|-------|---------|-------|---------|------------|-------------|-------------|")

    for pr in prs_sorted:
        title_short = pr['title'][:50] + '...' if len(pr['title']) > 50 else pr['title']
        print(f"| #{pr['pr']} | {title_short} | {pr['commits']} | {pr['files']} | {pr['total_changes']} | {pr['complexity_cat']} | {pr['churn_level']} | {pr['churn_score']:.2f} |")

    # Calculate statistics
    print("\n## Statistics by Complexity Level\n")

    complexity_groups = {}
    for pr in prs:
        score = pr['complexity_score']
        if score not in complexity_groups:
            complexity_groups[score] = []
        complexity_groups[score].append(pr)

    for score in sorted(complexity_groups.keys(), reverse=True):
        group = complexity_groups[score]
        avg_commits = sum(p['commits'] for p in group) / len(group)
        avg_files = sum(p['files'] for p in group) / len(group)
        avg_churn = sum(p['churn_score'] for p in group) / len(group)

        print(f"Complexity Score {score} ({len(group)} PRs):")
        print(f"  - Avg Commits: {avg_commits:.1f}")
        print(f"  - Avg Files: {avg_files:.1f}")
        print(f"  - Avg Churn: {avg_churn:.2f}")
        print()

    # High churn with low complexity (potential issues)
    print("\n## PRs with High Churn Relative to Complexity\n")
    problematic = [pr for pr in prs if pr['churn_score'] > 0.8 and pr['complexity_score'] <= 3]
    if problematic:
        for pr in sorted(problematic, key=lambda x: x['churn_score'], reverse=True):
            print(f"- PR #{pr['pr']}: {pr['title']}")
            print(f"  Churn: {pr['churn_score']:.2f} (commits/file), Complexity: {pr['complexity_cat']}")
    else:
        print("None found - all high-churn PRs are appropriately complex")

    # Low churn with high complexity (well-decomposed)
    print("\n## Well-Decomposed Complex Tasks (Low Churn)\n")
    well_decomposed = [pr for pr in prs if pr['churn_score'] < 0.5 and pr['complexity_score'] >= 4]
    if well_decomposed:
        for pr in sorted(well_decomposed, key=lambda x: x['churn_score']):
            print(f"- PR #{pr['pr']}: {pr['title']}")
            print(f"  Churn: {pr['churn_score']:.2f}, Complexity: {pr['complexity_cat']}, Files: {pr['files']}")
    else:
        print("None found - complex tasks generally required iteration")

if __name__ == '__main__':
    main()

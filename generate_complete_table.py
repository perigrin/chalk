#!/usr/bin/env python3
import csv

def assess_complexity(title, commits, files, total_changes):
    """Assess PR complexity and return category + score"""
    title_lower = title.lower()

    # Architectural/Design patterns (5 = highest complexity)
    if any(keyword in title_lower for keyword in ['architecture', 'refactor', 'infrastructure', 'pipeline', 'framework']):
        if files > 20 or commits > 15:
            return ('Architectural', 5)
        else:
            return ('Architectural', 4)

    # Multi-phase/Complex features (4)
    if 'phase' in title_lower or 'complete' in title_lower or 'chapters' in title_lower:
        if files > 100 or commits > 15:
            return ('Multi-Phase Complex', 5)
        else:
            return ('Multi-Phase Feature', 4)

    # System integration (4)
    if any(keyword in title_lower for keyword in ['self-execution', 'self-hosting', 'validating', 'unified', 'migration']):
        return ('System Integration', 4)

    # Large bulk additions
    if files > 100 or total_changes > 10000:
        return ('Large Feature', 4)

    # Feature additions with medium scope (3)
    if any(keyword in title_lower for keyword in ['implement', 'add', 'enable']):
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
    if files > 100 or commits > 15 or total_changes > 10000:
        return ('Large Change', 4)
    elif files > 15 or commits > 8:
        return ('Medium Change', 3)
    else:
        return ('Small Change', 2)

def calculate_churn_level(commits, files):
    """Calculate churn metric"""
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

# Read the data
prs = []
with open('/home/user/chalk/pr_analysis_all.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        pr = row['PR']
        title = row['Title']
        commits = int(row['Commits'])
        files = int(row['Files'])
        lines_added = int(row['Lines_Added'])
        lines_deleted = int(row['Lines_Deleted'])
        total_changes = int(row['Total_Changes'])

        complexity_cat, complexity_score = assess_complexity(title, commits, files, total_changes)
        churn_level, churn_score = calculate_churn_level(commits, files)

        prs.append({
            'PR': pr,
            'Title': title,
            'Commits': commits,
            'Files': files,
            'Total_Changes': total_changes,
            'Complexity_Category': complexity_cat,
            'Complexity_Score': complexity_score,
            'Churn_Level': churn_level,
            'Churn_Score': f'{churn_score:.2f}'
        })

# Write to CSV
with open('/home/user/chalk/pr_complexity_churn_table_complete.csv', 'w', newline='') as f:
    fieldnames = ['PR', 'Title', 'Commits', 'Files', 'Total_Changes',
                  'Complexity_Category', 'Complexity_Score', 'Churn_Level', 'Churn_Score']
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(prs)

print(f"Generated complete complexity table with {len(prs)} PRs")

#!/usr/bin/env python3
import csv
import sys

# Read the pipe-delimited data
with open('/home/user/chalk/pr_data_all.txt', 'r') as infile:
    lines = infile.readlines()

# Write as CSV
with open('/home/user/chalk/pr_analysis_all.csv', 'w', newline='') as outfile:
    writer = csv.writer(outfile)

    for line in lines:
        line = line.strip()
        if not line:
            continue

        parts = line.split('|')

        # Handle header
        if parts[0] == 'PR#':
            writer.writerow(['PR', 'Title', 'Commits', 'Files', 'Lines_Added', 'Lines_Deleted', 'Total_Changes'])
            continue

        # Extract PR number (remove #)
        pr_num = parts[0].replace('#', '')
        title = parts[1]
        commits = int(parts[2])
        files = int(parts[3])
        lines_added = int(parts[4])
        lines_deleted = int(parts[5])
        total_changes = lines_added + lines_deleted

        writer.writerow([pr_num, title, commits, files, lines_added, lines_deleted, total_changes])

print(f"Converted {len(lines)-1} PRs to CSV format")

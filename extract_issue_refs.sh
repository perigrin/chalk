#!/bin/bash

# Extract issue numbers and PR details
echo "PR#|Issue#|Commit_Messages"

git log --merges --pretty=format:"%H|%s|%b" --first-parent | while IFS='|' read merge_hash merge_subject merge_body; do
    # Extract PR number
    pr_num=$(echo "$merge_subject" | grep -oP '#\d+' | head -1)

    if [ -z "$pr_num" ]; then
        continue
    fi

    # Extract issue reference from title or body
    issue_ref=$(echo "$merge_subject $merge_body" | grep -oP 'Issue #\d+|Fixes #\d+|Closes #\d+' | head -1 | grep -oP '\d+')

    if [ -z "$issue_ref" ]; then
        issue_ref="N/A"
    fi

    # Get commit body length as proxy for detail
    body_length=${#merge_body}

    echo "$pr_num|$issue_ref|$body_length"
done

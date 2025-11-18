#!/bin/bash

# Analyze PRs from git history
echo "PR#|Title|Commits|Files|Lines_Added|Lines_Deleted"

# Get all merge commits
git log --merges --pretty=format:"%H|%s" --first-parent | while IFS='|' read merge_hash merge_subject; do
    # Extract PR number
    pr_num=$(echo "$merge_subject" | grep -oP '#\d+' | head -1)

    if [ -z "$pr_num" ]; then
        continue
    fi

    # Get PR title (everything before the PR number)
    pr_title=$(echo "$merge_subject" | sed -E 's/ \(#[0-9]+\)$//' | sed -E 's/ #[0-9]+$//')

    # Get the parent commits of the merge
    parents=$(git log --pretty=%P -n 1 $merge_hash)
    parent1=$(echo $parents | cut -d' ' -f1)
    parent2=$(echo $parents | cut -d' ' -f2)

    if [ -z "$parent2" ]; then
        # Not a merge commit, skip
        continue
    fi

    # Count commits in the PR (from merge base to parent2)
    merge_base=$(git merge-base $parent1 $parent2)
    commit_count=$(git rev-list --count ${merge_base}..${parent2})

    # Get files changed and line stats
    files_changed=$(git diff --name-only ${merge_base}..${parent2} | wc -l)

    # Get line additions and deletions
    stats=$(git diff --shortstat ${merge_base}..${parent2})
    lines_added=$(echo "$stats" | grep -oP '\d+(?= insertion)' || echo "0")
    lines_deleted=$(echo "$stats" | grep -oP '\d+(?= deletion)' || echo "0")

    echo "$pr_num|$pr_title|$commit_count|$files_changed|$lines_added|$lines_deleted"
done

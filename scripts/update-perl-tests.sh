#!/bin/bash
# ABOUTME: Updates perl-tests/ directory with latest tests from perl5.git
# ABOUTME: Uses git read-tree to import perl5 t/ directory as subtree

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "Updating perl-tests from perl5.git..."

# Check if perl5 remote exists
if ! git remote get-url perl5 >/dev/null 2>&1; then
    echo "Adding perl5 remote..."
    git remote add perl5 https://github.com/Perl/perl5.git
fi

# Fetch latest from perl5
echo "Fetching latest perl5 blead branch..."
git fetch perl5 blead

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
    echo "Error: You have uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Remove existing perl-tests directory
if [[ -d perl-tests ]]; then
    echo "Removing existing perl-tests directory..."
    git rm -rf perl-tests/
fi

# Import latest t/ directory from perl5
echo "Importing latest t/ directory from perl5 blead..."
git read-tree --prefix=perl-tests/ -u perl5/blead:t

# Show statistics
echo ""
echo "Update complete! Statistics:"
echo "  Total files: $(find perl-tests -type f | wc -l | tr -d ' ')"
echo "  Test files:  $(find perl-tests -name "*.t" | wc -l | tr -d ' ')"
echo "  Base tests:  $(find perl-tests/base -name "*.t" | wc -l | tr -d ' ')"
echo ""
echo "Next steps:"
echo "  1. Review changes: git status"
echo "  2. Commit changes: git commit -m 'Update perl-tests to latest perl5 blead:t'"
echo "  3. Push changes: git push"

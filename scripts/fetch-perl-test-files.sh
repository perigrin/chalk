#!/bin/bash
# ABOUTME: Fetches Perl test files from the official Perl git repository
# ABOUTME: for use in validating Chalk's parser against real Perl code

set -e

PERL_REPO="https://github.com/Perl/perl5.git"
PERL_COMMIT="v5.42.0"  # Adjust as needed
TEST_DIR="perl-tests/t/base"

echo "Fetching Perl test files from $PERL_REPO ($PERL_COMMIT)..."

# Create directory if it doesn't exist
mkdir -p "$TEST_DIR"

# Clone with sparse checkout to get only the test files we need
if [ ! -d "perl-tests/.git" ]; then
    git clone --filter=blob:none --no-checkout --depth 1 --branch "$PERL_COMMIT" "$PERL_REPO" perl-tests
    cd perl-tests
    git sparse-checkout init --cone
    git sparse-checkout set t/base
    git checkout
    cd ..
else
    echo "perl-tests directory already exists, skipping clone"
fi

echo "Perl test files fetched to $TEST_DIR"

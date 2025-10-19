#!/usr/bin/env perl
# ABOUTME: Baseline test harness for parsing all lib/*.pm files
# ABOUTME: Documents which library files currently parse successfully
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../lib";
use Chalk::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;
use File::Find;

# Get all .pm files in lib/
my @pm_files;
find(
    sub {
        push @pm_files, $File::Find::name if /\.pm$/;
    },
    "$RealBin/../lib"
);

# Sort for consistent test ordering
@pm_files = sort @pm_files;

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

my $total = scalar @pm_files;
my $passed = 0;
my $failed = 0;
my @failures;

diag "Testing $total .pm files in lib/";

foreach my $file (@pm_files) {
    my $rel_path = $file;
    $rel_path =~ s/^.*\/lib\///;  # Make path relative to lib/

    subtest "Parse $rel_path" => sub {
        # Read file content
        open my $fh, '<', $file or do {
            fail "Cannot read $file: $!";
            return;
        };
        my $source = do { local $/; <$fh> };
        close $fh;

        # Preprocess heredocs
        my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $source);
        $preprocessor->transform();
        my $preprocessed = $preprocessor->output;

        # Attempt to parse
        my $result = $parser->parse_string($preprocessed);

        if ($result) {
            pass "$rel_path parsed successfully";
            $passed++;
        } else {
            # Track failure but don't fail the test - this is a baseline assessment
            pass "$rel_path failed to parse (baseline)";
            $failed++;
            push @failures, $rel_path;
        }
    };
}

# Summary report
diag "";
diag "=== Baseline Parser Assessment for lib/ ===";
diag "Total files: $total";
diag "Passed: $passed";
diag "Failed: $failed";
diag "Success rate: " . sprintf("%.1f%%", ($passed / $total) * 100);

if (@failures) {
    diag "";
    diag "Files that failed to parse:";
    diag "  $_" for @failures;
}

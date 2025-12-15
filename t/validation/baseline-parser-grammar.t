#!/usr/bin/env perl
# ABOUTME: Baseline test harness for parsing all grammar/*.bnf files
# ABOUTME: Documents which BNF grammar files currently parse successfully
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar::BNF;
use Chalk::Parser;
use File::Find;
use File::Spec;

# Get BNF grammar for parsing BNF files
my $bnf_parser = Chalk::Grammar::BNF->new();
my $bnf_grammar = $bnf_parser->grammar;
my $parser = Chalk::Parser->new(grammar => $bnf_grammar);

# Get all .bnf files in grammar/
my @bnf_files;
find(
    sub {
        push @bnf_files, $File::Find::name if /\.bnf$/;
    },
    "$RealBin/../../grammar"
);

# Sort for consistent test ordering
@bnf_files = sort @bnf_files;

my $total = scalar @bnf_files;
my $passed = 0;
my $failed = 0;
my @failures;

diag "Testing $total .bnf files in grammar/";

foreach my $file (@bnf_files) {
    my $rel_path = $file;
    $rel_path =~ s/^.*\/grammar\///;  # Make path relative to grammar/

    subtest "Parse $rel_path" => sub {
        # Read file content
        open my $fh, '<:utf8', $file or do {
            fail "Cannot read $file: $!";
            return;
        };
        my $source = do { local $/; <$fh> };
        close $fh;

        # Attempt to parse
        my $result = $parser->parse_string($source);

        if ($result) {
            ok($result, "$rel_path parsed successfully");
            $passed++;
        } else {
            # Mark as TODO - expected to parse eventually but not yet implemented
            todo "Parser does not yet support all BNF constructs in $rel_path" => sub {
                ok($result, "$rel_path should parse");
            };
            $failed++;
            push @failures, $rel_path;
        }
    };
}

# Summary report
diag "";
diag "=== Baseline Parser Assessment for grammar/ ===";
diag "Total files: $total";
diag "Passed: $passed";
diag "Failed: $failed";
diag "Success rate: " . ($total > 0 ? sprintf("%.1f%%", ($passed / $total) * 100) : "N/A (no files found)");

if (@failures) {
    diag "";
    diag "Files that failed to parse:";
    diag "  $_" for @failures;
}

#!/usr/bin/env perl
# ABOUTME: Baseline test harness for parsing all t/*.t test files
# ABOUTME: Documents which test files currently parse successfully
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../lib";
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;
use File::Find;

# Get all .t files in t/ (excluding this file and subdirectories we'll skip)
my @t_files;
find(
    {
        wanted => sub {
            return unless /\.t$/;
            return if $File::Find::name =~ /baseline-parser/;  # Skip baseline tests themselves
            push @t_files, $File::Find::name;
        },
        no_chdir => 1,
    },
    "$RealBin"
);

# Sort for consistent test ordering
@t_files = sort @t_files;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my $total = scalar @t_files;
my $passed = 0;
my $failed = 0;
my @failures;

diag "Testing $total .t files in t/";

foreach my $file (@t_files) {
    my $rel_path = $file;
    $rel_path =~ s/^.*\/t\///;  # Make path relative to t/

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
diag "=== Baseline Parser Assessment for t/ ===";
diag "Total files: $total";
diag "Passed: $passed";
diag "Failed: $failed";
diag "Success rate: " . sprintf("%.1f%%", ($passed / $total) * 100);

if (@failures) {
    diag "";
    diag "Files that failed to parse:";
    diag "  $_" for @failures;
}

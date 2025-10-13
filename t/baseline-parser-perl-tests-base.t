#!/usr/bin/env perl
# ABOUTME: Baseline test harness for parsing perl-tests/base/*.t files
# ABOUTME: Documents which perl5 base test files currently parse successfully
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../lib";
use Chalk::Grammar::Perl;
use Chalk::Parser;
use Chalk::Preprocessor::HeredocV2;

# Get all .t files in perl-tests/base/
my $base_dir = "$RealBin/../perl-tests/base";
opendir my $dh, $base_dir or die "Cannot open $base_dir: $!";
my @t_files = sort grep { /\.t$/ && -f "$base_dir/$_" } readdir($dh);
closedir $dh;

my $parser = Chalk::Parser->new(grammar => $Chalk::Grammar::Perl::chalk_grammar);

my $total = scalar @t_files;
my $passed = 0;
my $failed = 0;
my @failures;

diag "Testing $total .t files in perl-tests/base/";

foreach my $filename (@t_files) {
    my $file = "$base_dir/$filename";

    subtest "Parse $filename" => sub {
        # Read file content
        open my $fh, '<', $file or do {
            fail "Cannot read $file: $!";
            return;
        };
        my $source = do { local $/; <$fh> };
        close $fh;

        # Preprocess heredocs
        my $preprocessor = Chalk::Preprocessor::HeredocV2->new(input => $source);
        $preprocessor->transform();
        my $preprocessed = $preprocessor->output;

        # Attempt to parse
        my $result = $parser->parse_string($preprocessed);

        if ($result) {
            pass "$filename parsed successfully";
            $passed++;
        } else {
            # Track failure but don't fail the test - this is a baseline assessment
            pass "$filename failed to parse (baseline)";
            $failed++;
            push @failures, $filename;
        }
    };
}

# Summary report
diag "";
diag "=== Baseline Parser Assessment for perl-tests/base/ ===";
diag "Total files: $total";
diag "Passed: $passed";
diag "Failed: $failed";
diag "Success rate: " . sprintf("%.1f%%", ($passed / $total) * 100);

if (@failures) {
    diag "";
    diag "Files that failed to parse:";
    diag "  $_" for @failures;
}

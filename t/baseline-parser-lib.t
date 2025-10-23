#!/usr/bin/env perl
# ABOUTME: Baseline test harness for parsing all lib/*.pm files
# ABOUTME: Documents which library files currently parse successfully
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../lib";
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;
use Chalk::Preprocessor::Heredoc;
use File::Find;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "grammar", "chalk.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

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

# Skip Chalk/BNF.pm - it's a thin wrapper scheduled for removal (see issue #69)
@pm_files = grep { $_ !~ m{/Chalk/BNF\.pm$} } @pm_files;

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
            # Mark as TODO - we expect this to fail until grammar is complete
            my $todo = todo "$rel_path parsing not yet supported";
            ok 0, "$rel_path should parse";
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

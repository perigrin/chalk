#!/usr/bin/env perl
# ABOUTME: Baseline test harness for parsing perl-tests/base/*.t files
# ABOUTME: Documents which perl5 base test files currently parse successfully
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
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

# Get all .t files in perl-tests/base/
my $base_dir = "$RealBin/../perl-tests/base";
opendir my $dh, $base_dir or die "Cannot open $base_dir: $!";
my @t_files = sort grep { /\.t$/ && -f "$base_dir/$_" } readdir($dh);
closedir $dh;

my $parser = Chalk::Parser->new(grammar => $chalk_grammar);

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
        my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $source);
        $preprocessor->transform();
        my $preprocessed = $preprocessor->output;

        # Attempt to parse
        my $result = $parser->parse_string($preprocessed);

        if ($result) {
            ok($result, "$filename parsed successfully");
            $passed++;
        } else {
            # Mark as TODO - expected to parse eventually but not yet implemented
            todo "Parser does not yet support all Perl constructs in $filename" => sub {
                ok($result, "$filename should parse");
            };
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

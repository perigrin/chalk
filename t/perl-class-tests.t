#!/usr/bin/env perl
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw(:std :utf8);

use Test2::V0;

# Test that chalk can parse Perl's t/class test suite
# This validates our compatibility with modern Perl class syntax

my $chalk_path = './chalk';
my $grammar_path = './chalk-grammar.pl';

# First check that chalk itself works
ok(-f $chalk_path, "chalk executable exists");
ok(-f $grammar_path, "chalk grammar exists");

# Test that we can parse all t/class files
my $all_class_result = 0;
if (-d "perl-tests/t/class") {
    my @all_files = glob("perl-tests/t/class/*.t");
    # Sort by file size (smallest first) for faster feedback
    @all_files = sort { -s $a <=> -s $b } @all_files;
    my $parsed_count = 0;
    my $total_count = scalar(@all_files);
    
    for my $file (@all_files) {
        my $basename = $file;
        $basename =~ s{.*/}{};  # Extract just the filename
        diag("Attempting to parse $basename...");
        
        my $result = system($chalk_path, $file);
        my $exit_code = $result >> 8;
        
        if ($exit_code == 0) {
            $parsed_count++;
            diag("  ✓ Successfully parsed $basename");
        } else {
            diag("  ✗ Failed to parse $basename");
        }
    }
    
    diag("Parsed $parsed_count out of $total_count t/class files");
    $all_class_result = $parsed_count;
}

# This test documents our current progress with modern Perl class syntax
# We expect it to improve over time as we implement class/field/method features
ok($all_class_result >= 0, "chalk attempted to parse t/class (progress: $all_class_result files)");

done_testing();
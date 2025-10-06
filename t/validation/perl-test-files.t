#!/usr/bin/env perl
# ABOUTME: Validate Perl test files using Boolean semiring for fast syntax checking
# ABOUTME: Demonstrates Boolean semiring's practical utility similar to `perl -c`
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use File::Glob qw(bsd_glob);
use Time::HiRes qw(time);

local $| = 1;

# Directory containing Perl test files
my $test_dir = "$RealBin/../../perl-tests/t/base";

unless (-d $test_dir) {
    plan skip_all => "Perl test directory not found at $test_dir";
}

my @test_files = bsd_glob("$test_dir/*.t");

unless (@test_files) {
    plan skip_all => "No test files found in $test_dir";
}

diag "Validating " . scalar(@test_files) . " Perl test files using Boolean semiring";

my $start_time = time();
my $passed = 0;
my $total = 0;

for my $file (sort @test_files) {
    my $name = $file =~ s{^.*/}{}r;
    $total++;

    # Use Boolean semiring for fast validation with 30s timeout
    my $output;
    my $exit_code;
    my $timed_out = 0;

    try {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm 30;
        $output = `$RealBin/../../app.pl --semiring Boolean '$file' 2>&1`;
        $exit_code = $? >> 8;
        alarm 0;
    }
    catch ($e) {
        if ($e eq "timeout\n") {
            $timed_out = 1;
        }
    }

    # Check if validation was successful
    my $success = (!$timed_out && $exit_code == 0 && $output =~ /Parse successful: 1/);

    if ($success) {
        pass "$name validates successfully with Boolean semiring";
        $passed++;
    } else {
        fail "$name validates successfully with Boolean semiring";

        # Provide diagnostic information
        if ($timed_out) {
            diag("  Validation timed out after 30 seconds for $file");
        } elsif ($output =~ /PARSING STOPPED: Reached position (\d+) of (\d+)/) {
            diag("  Failed to validate $file");
            diag("  Stopped at position $1 of $2");
        } elsif ($output =~ /Parse failed/) {
            diag("  Parse failed for $file");
        } else {
            diag("  Unexpected output: $output");
        }
    }
}

my $elapsed = time() - $start_time;

# Summary
diag "";
diag "=== Validation Summary ===";
diag sprintf("Files validated: %d/%d (%.1f%%)", $passed, $total, 100 * $passed / $total);
diag sprintf("Total time: %.3f seconds", $elapsed);
diag sprintf("Average per file: %.3f seconds", $elapsed / $total) if $total > 0;

done_testing;

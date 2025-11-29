#!/usr/bin/env perl
# ABOUTME: Phase 1 Acceptance Test - ChalkSyntax validates all lib/ files
# ABOUTME: Tests Boolean+Precedence+TypeInference composite on Chalk source code

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use File::Find;
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkSyntax;

# Load Chalk grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Create ChalkSyntax semiring (Boolean + Precedence + TypeInference)
my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);
ok $semiring, 'ChalkSyntax semiring created';

# Find all .pm files in lib/
my @lib_files;
find(sub {
    return unless -f && /\.pm$/;
    push @lib_files, $File::Find::name;
}, "$RealBin/../../lib");

note("Found " . scalar(@lib_files) . " .pm files in lib/");

# Phase 1 Acceptance: All lib/ files must parse without error
my $passed = 0;
my $failed = 0;

for my $file (sort @lib_files) {
    my $relative = $file;
    $relative =~ s{^.*/lib/}{};

    # Output progress immediately
    note("Processing: $relative");
    STDOUT->flush();

    # Read file
    open my $fh, '<:utf8', $file or do {
        fail("Cannot read $relative: $!");
        $failed++;
        next;
    };
    my $code = do { local $/; <$fh> };
    close $fh;

    # Parse with ChalkSyntax
    my $parser = Chalk::Parser->new(
        grammar => $grammar,
        semiring => $semiring
    );

    my $result = eval { $parser->parse_string($code) };
    my $error = $@;

    if ($error) {
        fail("$relative: Parse died with error");
        diag("Error: $error");
        $failed++;
    } elsif (!$result) {
        fail("$relative: ChalkSyntax validation failed");
        $failed++;
    } else {
        pass("$relative: Validated successfully");
        $passed++;
    }
}

# Report summary
note("Validation Summary:");
note("  Passed: $passed");
note("  Failed: $failed");
note("  Success Rate: " . sprintf("%.1f%%", 100 * $passed / (@lib_files || 1)));

# Phase 1 acceptance criteria: 100% success
is($failed, 0, "Phase 1 Acceptance: All lib/ files validate with ChalkSyntax");

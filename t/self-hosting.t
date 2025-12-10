#!/usr/bin/env perl
# ABOUTME: Test chalk parsing its own source code (lib/) with full type inference
# ABOUTME: Uses ChalkSyntax semiring (Boolean + Precedence + TypeInference) for complete validation
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use File::Find;
use Chalk::Grammar::BNF;
use Chalk::Semiring::ChalkSyntax;

local $| = 1;

# Check if lib/* was modified in this branch/PR
# If not, skip the expensive self-hosting test (it takes ~18-20 minutes)
my $lib_changed = 0;

# If FORCE_SELF_HOSTING env var is set, always run
if ($ENV{FORCE_SELF_HOSTING}) {
    $lib_changed = 1;
    diag "FORCE_SELF_HOSTING set - running full self-hosting test";
} elsif (-d "$RealBin/../.git") {
    # Get the merge base with the target branch (pu)
    my $merge_base = `git -C "$RealBin/.." merge-base HEAD origin/pu 2>/dev/null`;
    chomp $merge_base;

    if ($merge_base) {
        # Check if any files in lib/ changed since the merge base
        my $changed_files = `git -C "$RealBin/.." diff --name-only $merge_base HEAD 2>/dev/null`;
        $lib_changed = 1 if $changed_files =~ m{^lib/}m;
    } else {
        # Fallback: If we can't determine merge base, assume lib changed
        $lib_changed = 1;
    }
} else {
    # Not in a git repo, run the tests
    $lib_changed = 1;
}

unless ($lib_changed) {
    plan tests => 1;
    pass "No changes to lib/* detected - skipping expensive self-hosting test";
    diag "Self-hosting test skipped: lib/ unchanged since merge-base with origin/pu";
    diag "To force running: FORCE_SELF_HOSTING=1 prove t/self-hosting.t";
    exit 0;
}

diag "lib/* changed detected - running full self-hosting test";

# Load the chalk.bnf grammar
open my $grammar_fh, "<:utf8", "$RealBin/../grammar/chalk.bnf" or die $!;
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;

my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program", "Chalk");

# Create ChalkSyntax semiring (Boolean + Precedence + TypeInference)
my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $chalk_grammar);

# Find all .pm files in lib/
my @pm_files;
find(
    sub {
        push @pm_files, $File::Find::name if /\.pm$/ && -f;
    },
    "$RealBin/../lib"
);

@pm_files = sort @pm_files;

diag "=== Self-Hosting Test: lib/ ===";
diag "Testing " . scalar(@pm_files) . " files";

my $passed = 0;
my $failed = 0;
my @failed_files;

for my $file (@pm_files) {
    my $relative = $file;
    $relative =~ s|^.*/lib/||;

    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    my $content = do { local $/; <$fh> };
    close $fh;

    my $parser = Chalk::Parser->new(grammar => $chalk_grammar, semiring => $semiring);
    my $result = $parser->parse_string($content);

    if ($result) {
        pass("$relative parses successfully");
        $passed++;
    } else {
        fail("$relative should parse");
        push @failed_files, $relative;
        $failed++;
    }
}

my $total = $passed + $failed;
my $pct = sprintf("%.1f", ($passed / $total) * 100);

diag "";
diag "=== Self-Hosting Results ===";
diag "Total files: $total";
diag "Passed: $passed";
diag "Failed: $failed";
diag "Success rate: $pct%";

if (@failed_files) {
    diag "";
    diag "Files that failed to parse:";
    for my $file (@failed_files) {
        diag "  $file";
    }
}

# The test passes if we're making progress, but we note the goal
ok $passed > 0, "At least some files parse (goal: 100%)";

diag "";
diag "Self-hosting goal: 100% of lib/ should parse";
diag "Current status: $pct%";

done_testing;

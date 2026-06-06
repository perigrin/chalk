# ABOUTME: Top-level CodeGen harness rig — runs one corpus entry end-to-end (S via oracle, P via driver).
# ABOUTME: run_entry($tag, $spec) -> { S, P, verdict } using RunUnderPerl, PerlDriver, and Comparator.
package Chalk::CodeGen::Harness;

use 5.42.0;
use utf8;

use Carp qw(croak);

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness::RunUnderPerl;
use Chalk::CodeGen::Harness::PerlDriver;
use Chalk::CodeGen::Harness::Comparator;

# Corpus of canonical snippets for each hand-graph tag.
# Each entry is the minimal Perl snippet that matches the hand graph.
# These are used as the oracle's source-of-truth (S side).
my %CORPUS = (
    A1 => 'class C { method m() { my $x = 1; return $x; } }',
    A4 => 'class C { method m() { my $x; $x = 1; return $x; } }',
    A5 => 'class C { field $x :param; method m() { return $x; } }',
    E1 => 'class C { method m() { my $x = 1; $x } }',
    F3 => 'class C { sub foo { return $_[0] + $_[1] } method m() { my $r = foo(1, 2); return $r; } }',
);

# run_entry($tag, $spec) -> { S => BehaviorRecord, P => BehaviorRecord, verdict => \%verdict }
#
# Runs one corpus entry end-to-end:
#   1. S = RunUnderPerl->capture(corpus snippet for $tag, $spec)  — oracle via real perl
#   2. P = PerlDriver->run(HandGraphs->graph_for($tag), $spec)    — generated via Chalk
#   3. verdict = Comparator->verdict($S, $P, $emission_meta)
#
# Returns a hashref with keys S, P, verdict.
# Dies if $tag is not a known corpus entry.
sub run_entry {
    my (undef, $tag, $spec) = @_;    # undef = class name
    croak "run_entry: tag must be a non-empty string"
        unless defined $tag && length $tag;
    croak "run_entry: spec must be a hashref"
        unless ref $spec eq 'HASH';
    croak "run_entry: unknown tag '$tag'"
        unless exists $CORPUS{$tag};

    my $snippet = $CORPUS{$tag};

    # ---- S side: oracle via real perl ----
    my $S = Chalk::CodeGen::Harness::RunUnderPerl->capture($snippet, $spec);

    # ---- P side: generated via Chalk Target::Perl ----
    my $graph = Chalk::CodeGen::Harness::HandGraphs->graph_for($tag);
    my ($P, $emission_meta) = Chalk::CodeGen::Harness::PerlDriver->run($graph, $spec);

    # ---- Verdict ----
    $emission_meta->{graph_source} //= "hand:$tag";
    my $verdict = Chalk::CodeGen::Harness::Comparator->verdict($S, $P, $emission_meta);

    return {
        S       => $S,
        P       => $P,
        verdict => $verdict,
    };
}

1;

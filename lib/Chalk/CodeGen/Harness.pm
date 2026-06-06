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
    A1  => 'class C { method m() { my $x = 1; return $x; } }',
    A2  => 'class C { method m() { my @list = (1, 2, 3); return scalar @list; } }',
    A3  => 'class C { method m() { my %h = (a => 1, b => 2); return $h{a}; } }',
    A4  => 'class C { method m() { my $x; $x = 1; return $x; } }',
    A5  => 'class C { field $x :param; method m() { return $x; } }',
    B1  => 'class C { method m() { my @list = (); push @list, 1; return scalar @list; } }',
    B2  => 'class C { method m() { print "hi"; return 1; } }',
    B3  => 'class C { method m() { say "hi"; return 1; } }',
    B4  => 'class C { method m() { die "boom"; } }',
    B5  => 'class C { method m() { foo(1, 2); return 1; } }',
    B6  => 'class C { method m() { $self->bar(); return 1; } }',
    B7  => 'class C { method m() { my @list = (); unshift @list, 1; return scalar @list; } }',
    B8  => 'class C { method m() { warn "hi"; return 1; } }',
    C1  => 'class C { method m() { my $x = 1; $x = 2; return $x; } }',
    C2  => 'class C { method m() { my $x = 1; $x += 2; return $x; } }',
    C3  => 'class C { method m() { my $s = "a"; $s .= "b"; return $s; } }',
    C4  => 'class C { method m() { my @a = (1); $a[0] = 2; return $a[0]; } }',
    C5  => 'class C { method m() { my %h = (); $h{k} = 1; return $h{k}; } }',
    D1  => 'class C { method m($n) { my $x = 0; if ($n > 0) { $x = 1; } else { $x = 2; } return $x; } }',
    D2  => 'class C { method m() { my $i = 0; while ($i < 3) { $i = $i + 1; } return $i; } }',
    D3  => 'class C { method m() { my $sum = 0; foreach my $n (1, 2, 3) { $sum = $sum + $n; } return $sum; } }',
    D4  => 'class C { method m($n) { my $x = 0; $x = 1 if $n > 0; return $x; } }',
    D5  => 'class C { method m() { my $i = 0; $i = $i + 1 while $i < 3; return $i; } }',
    D6  => 'class C { method m($n) { my $x = $n > 0 ? 1 : 2; return $x; } }',
    D7  => 'class C { method m($n) { my $x = 0; if ($n > 0) { if ($n > 5) { $x = 1; } else { $x = 2; } } else { $x = 3; } return $x; } }',
    D8  => 'class C { method m() { try { die "boom"; } catch ($e) { return 0; } return 1; } }',
    E1  => 'class C { method m() { my $x = 1; $x } }',
    E2  => 'class C { method m($n) { if ($n > 0) { return 1; } return 0; } }',
    E3  => 'class C { method m() { foreach my $n (1, 2, 3) { return $n if $n == 2; } return 0; } }',
    E4  => 'class C { method m() { die "no" if 1; return 1; } }',
    F1  => 'class C { method m() { return $self->foo->bar; } }',
    F2  => 'class C { method m() { return $self->foo(1, 2, 3); } }',
    F3  => 'class C { sub foo { return $_[0] + $_[1] } method m() { my $r = foo(1, 2); return $r; } }',
    G1  => 'class C { method m() { my $r = [1, 2]; return $r->@*; } }',
    G2  => 'class C { method m() { my $r = { a => 1 }; return $r->%*; } }',
    G3  => 'class C { method m() { my @a = (1, 2); return $a[0]; } }',
    G4  => 'class C { method m() { my %h = (k => 1); return $h{k}; } }',
    H1  => 'class C { method m() { my @r = map { $_ * 2 } (1, 2, 3); return scalar @r; } }',
    H2  => 'class C { method m() { my @r = grep { $_ > 1 } (1, 2, 3); return scalar @r; } }',
    H3  => 'class C { method m() { my @r = sort (3, 1, 2); return $r[0]; } }',
    H4  => 'class C { method m() { my $f = sub ($x) { return $x + 1; }; return $f->(1); } }',
    I1  => 'class C { field $x :param; ADJUST { $x = $x + 1; } method m() { return $x; } }',
    I2  => 'sub greet ($name) { return "hi $name"; }',
    I3  => 'class C { method m() { my sub helper ($n) { return $n * 2; } return helper(3); } }',
    J1  => 'class C { method m($s) { return $s =~ /foo/; } }',
    J2  => 'class C { method m($s) { $s =~ s/foo/bar/; return $s; } }',
    J3  => 'class C { method m() { my @keys = qw(a b c); return scalar @keys; } }',
    K1  => 'class C { method m() { my $i = 0; ++$i; return $i; } }',
    K2  => 'class C { method m() { my $i = 0; $i++; return $i; } }',
    L1  => 'class C { method m($a, $b) { return $a && $b; } }',
    L2  => 'class C { method m($a, $b) { return $a || $b; } }',
    L3  => 'class C { method m($a, $b) { return $a // $b; } }',
    L4  => 'class C { method m($a) { return !$a; } }',
    M1  => 'use strict; use warnings; sub greet { return "hi"; }',
    M5  => 'class C { method m($n) { my $x = 0; $x = 1 unless $n; return $x; } }',
    M6  => 'class C { method m() { my $sum = 0; $sum = $sum + $_ for (1, 2, 3); return $sum; } }',
    M7  => 'class C { method m() { my $sum = 0; foreach (1, 2, 3) { $sum = $sum + $_; } return $sum; } }',
    M2  => 'use List::Util qw(first sum); sub greet { return first { $_ > 1 } (0, 2, 3); }',
    M3  => 'class C { method m($name) { return "hello $name"; } }',
    M4  => 'class C { method m() { my @list = (1, 2); return "got @list"; } }',
    M8  => 'class C { method m($r) { return $r->[0]; } }',
    M9  => 'class C { method m($r) { return $r->{key}; } }',
    M10 => 'class C { method m() { my @list = (1, 2); my $r = \@list; return $r->[0]; } }',
    M11 => 'class C { method m() { my %h = (k => 1); my $r = \%h; return $r->{k}; } }',
    M12 => 'class C { method m() { return Foo::Bar->new(); } }',
    M13 => 'class C { method m() { return Foo::Bar::baz(1); } }',
    M14 => 'class C { method m($a) { return "got " . $a; } }',
    M15 => 'class C { method m($x) { my $y; $y //= $x; return $y; } }',
    M16 => 'class C { method m($n) { unless ($n) { return 0; } return 1; } }',
    M17 => 'class C { method m() { foreach my $n (1, 2, 3) { next if $n == 2; } return 1; } }',
    M18 => 'class C { method m() { foreach my $n (1, 2, 3) { last if $n > 1; } return 1; } }',
    M19 => 'class C { method m() { my ($a, $b) = (1, 2); return $a + $b; } }',
    M22 => 'class C { method m() { my @r = sort { $a <=> $b } (3, 1, 2); return $r[0]; } }',
    M25 => 'class C { method m() { my $sum = 0; for (my $i = 0; $i < 3; $i++) { $sum = $sum + $i; } return $sum; } }',
    M23 => 'class C { method m() { my %h = (a => 1); delete $h{a}; return scalar keys %h; } }',
    M24 => 'class C { method m($r) { return $r->{a}->[0]; } }',
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
    my $is_sub_spec = exists $spec->{sub_name};
    my $S = $is_sub_spec
        ? Chalk::CodeGen::Harness::RunUnderPerl->capture_sub($snippet, $spec)
        : Chalk::CodeGen::Harness::RunUnderPerl->capture($snippet, $spec);

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

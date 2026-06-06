# ABOUTME: Gap-map generator for the CodeGen harness — iterates all 78 tier-1 corpus idioms (A-M).
# ABOUTME: Produces per-idiom PASS/GAP/MISCOMPILE/NOT-YET-COVERED verdicts and a structured artifact.
package Chalk::CodeGen::Harness::GapMap;

use 5.42.0;
use utf8;

use Carp      qw(croak);
use JSON::PP;

use Chalk::CodeGen::Harness::HandGraphs;
use Chalk::CodeGen::Harness::PerlDriver;
use Chalk::CodeGen::Harness::RunUnderPerl;
use Chalk::CodeGen::Harness::Comparator;

# Path to the tier-1 corpus file (=== TAG-delimited).
my $CORPUS_FILE = 't/fixtures/ir-audit-corpus.pl';

# Path for the generated gap-map artifact.
my $ARTIFACT_FILE = 't/fixtures/codegen-harness/gap-map.json';

# ---------------------------------------------------------------------------
# Out-of-subset idiom registry.
#
# Idioms listed here are classified REJECT: they are excluded from the Chalk
# subset by explicit policy decision, are NOT codegen targets, and must NOT
# count as codegen failures.  They still appear in the 78-entry denominator
# (classified, not dropped) and carry a documented reason.
#
# Key   = tier-1 corpus tag (e.g. 'M21').
# Value = human-readable reason string explaining the policy decision.
# ---------------------------------------------------------------------------
my %REJECT_IDIOMS = (
    # eval { } is excluded by the try/catch policy: Chalk's exception-handling
    # mechanism is try/catch; eval is excluded in all forms (see CLAUDE.md and
    # the memory note feedback_try_catch_not_eval).  The grammar (chalk-bootstrap.bnf)
    # has no eval rule and no eval keyword anywhere in its 336 lines.
    M21 => 'out-of-subset by policy: eval is excluded in all forms; '
         . 'Chalk uses try/catch for exception handling (see CLAUDE.md)',
);

# Idioms that are IN-SUBSET but deliberately deferred past Phase 1, with a
# specific reason recorded so the gap map does not flatten them into a generic
# "no hand graph defined".  Key = tag, value = reason string.  These remain
# NOT-YET-COVERED (in the denominator, blocking tier-1-green until addressed),
# but the reason documents the known follow-up work.
my %DEFERRED_REASONS = (
    # do { } as an expression is valid Perl, NOT policy-excluded, and is used
    # in Chalk's own source (SemanticAction.pm, FilterComposite.pm use //= do {})
    # so it is needed for the self-host capstone.  Classified IN-SUBSET-DEFERRED
    # per the M20/M21 scope decision (docs/plans/2026-06-06-phase1-m20-m21-scope-decision.md):
    # it needs a Chalk::IR::Node::Do + a DoBlock grammar rule + emitter; tracked
    # as a follow-up codegen issue, not Phase-1 work.
    M20 => 'IN-SUBSET-DEFERRED: needs Chalk::IR::Node::Do + DoBlock grammar rule '
         . '+ emitter; tracked as a follow-up codegen issue (see the M20/M21 '
         . 'scope-decision doc)',
);

# ---------------------------------------------------------------------------
# generate() -> \%gap_map
#
# Iterates every tier-1 corpus entry (A1 .. M25, 78 idioms total), runs each
# through the rig (oracle S + driver P + comparator verdict) when a hand graph
# is available, and records per-idiom:
#   { tag, group, verdict: PASS|GAP|MISCOMPILE|NOT-YET-COVERED, extra => {...} }
#
# Idioms with no hand graph are recorded as NOT-YET-COVERED (still in the
# denominator — never silently omitted).
#
# Returns a hashref:
#   {
#     entries => [ { tag, group, verdict, extra }, ... ],   # 78 entries, one per idiom
#     summary => {
#         denominator   => 78,
#         by_verdict    => { PASS => N, GAP => N, MISCOMPILE => N, 'NOT-YET-COVERED' => N },
#         by_group      => { A => { count => 5, verdicts => {...} }, ... },
#     },
#   }
#
# Also writes the artifact file t/fixtures/codegen-harness/gap-map.json.
# ---------------------------------------------------------------------------
sub generate {
    my (undef) = @_;    # class method

    my $corpus_text = _load_corpus();
    my @ordered_tags = _enumerate_tags($corpus_text);

    my @entries;
    for my $tag (@ordered_tags) {
        my $group = _group_of($tag);
        my $entry = _run_one($tag, $group, $corpus_text);
        push @entries, $entry;
    }

    my $summary = _build_summary(\@entries);

    my $gap_map = {
        entries => \@entries,
        summary => $summary,
    };

    _write_artifact($gap_map);

    return $gap_map;
}

# ---------------------------------------------------------------------------
# validate_coverage(\%gap_map, \%expected_group_counts) -> bool
#
# Returns true iff:
#   1. denominator == sum(expected_group_counts)
#   2. every group in expected_group_counts is present with the correct count
#
# Returns false (or dies with a descriptive message) when either condition fails.
# Used by gap-map-neg.t to detect shrunk denominators and dropped groups.
# ---------------------------------------------------------------------------
sub validate_coverage {
    my (undef, $gap_map, $expected_groups) = @_;    # class method

    croak "validate_coverage: gap_map must be a hashref"
        unless ref $gap_map eq 'HASH';
    croak "validate_coverage: expected_groups must be a hashref"
        unless ref $expected_groups eq 'HASH';

    my $entries = $gap_map->{entries} // [];

    # Compute expected total
    my $expected_total = 0;
    $expected_total += $_ for values %$expected_groups;

    my $actual_total = scalar @$entries;
    unless ($actual_total == $expected_total) {
        return false;
    }

    # Count per-group
    my %actual_group_counts;
    for my $entry (@$entries) {
        $actual_group_counts{ $entry->{group} }++ if defined $entry->{group};
    }

    for my $group (sort keys %$expected_groups) {
        my $expected = $expected_groups->{$group};
        my $actual   = $actual_group_counts{$group} // 0;
        unless ($actual == $expected) {
            return false;
        }
    }

    return true;
}

# ---------------------------------------------------------------------------
# valid_verdicts() -> @list
#
# Returns the complete list of valid verdict strings.  Tests use this to
# assert that new verdicts are documented rather than appearing silently.
# ---------------------------------------------------------------------------
sub valid_verdicts {
    return qw(PASS GAP MISCOMPILE NOT-YET-COVERED UNDER_SPECIFIED REJECT);
}

# ---------------------------------------------------------------------------
# tier1_green(\%gap_map) -> bool
#
# Returns true iff the gap map satisfies the tier-1 green requirement:
#   - Every IN-SUBSET idiom has verdict PASS.
#   - REJECT idioms are excluded from the requirement.
#   - Any non-PASS, non-REJECT verdict (GAP, MISCOMPILE, NOT-YET-COVERED,
#     UNDER_SPECIFIED) on an in-subset idiom counts as NOT green.
#
# "In-subset" means: any entry whose verdict is not REJECT.
# ---------------------------------------------------------------------------
sub tier1_green {
    my (undef, $gap_map) = @_;    # class method

    croak "tier1_green: gap_map must be a hashref"
        unless ref $gap_map eq 'HASH';

    my $entries = $gap_map->{entries} // [];

    for my $entry (@$entries) {
        my $v = $entry->{verdict} // 'UNKNOWN';
        next if $v eq 'REJECT';    # out-of-subset, excluded from green requirement
        return false unless $v eq 'PASS';
    }

    return true;
}

# ---------------------------------------------------------------------------
# classify_verdict_from_meta(\%emission_meta, $divergence_signal) -> verdict_string
#
# Maps emission_meta + divergence signal to a verdict string.
# Used by gap-map-neg.t to test the MISCOMPILE-vs-GAP discrimination.
#
# $divergence_signal: 'diverged' | 'match'
# ---------------------------------------------------------------------------
sub classify_verdict_from_meta {
    my (undef, $emission_meta, $divergence_signal) = @_;    # class method

    croak "classify_verdict_from_meta: emission_meta must be a hashref"
        unless ref $emission_meta eq 'HASH';

    # GAP/NOT-YET-COVERED: emission was incomplete or unsupported
    if ($emission_meta->{marked_unsupported} || !$emission_meta->{emitted_for_every_construct}) {
        return 'NOT-YET-COVERED';
    }

    # MISCOMPILE: complete emission but behavior diverged
    if (($divergence_signal // '') eq 'diverged') {
        return 'MISCOMPILE';
    }

    # PASS: complete emission and behavior matched
    return 'PASS';
}

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

# Load the corpus text from disk.
sub _load_corpus {
    open my $fh, '<', $CORPUS_FILE
        or croak "GapMap: cannot open corpus '$CORPUS_FILE': $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    croak "GapMap: corpus file is empty" unless defined $text && length $text;
    return $text;
}

# Enumerate all tags in corpus order from the === TAG-delimited corpus text.
# Returns an ordered list of tag strings like ('A1','A2',...,'M25').
sub _enumerate_tags {
    my ($corpus_text) = @_;
    my @tags;
    for my $line (split /\n/, $corpus_text) {
        if ($line =~ /^===\s+([A-Z]\d+)(?:\s|:)/) {
            push @tags, $1;
        }
    }
    croak "GapMap: no tags found in corpus" unless @tags;
    return @tags;
}

# Extract the single letter group from a tag like 'A1' -> 'A', 'M25' -> 'M'.
sub _group_of {
    my ($tag) = @_;
    $tag =~ /^([A-Z])/;
    return $1 // croak "GapMap: cannot extract group from tag '$tag'";
}

# ---------------------------------------------------------------------------
# check_spec_completeness($tag, $snippet, $spec) -> bool/undef
#
# Structural guard against vacuous passes from under-specified exercise specs.
# Returns a true value (the reason string) when the spec is under-specified:
# the snippet declares method/sub parameters but the spec supplies no args.
# Returns false/undef when the spec is adequate.
#
# A parameterized method or sub run with no args exercises only the undef-arg
# path. Both oracle and generated code produce the same degenerate result,
# so the verdict is meaninglessly PASS. This guard catches that before the
# rig runs.
# ---------------------------------------------------------------------------
sub check_spec_completeness {
    my (undef, $tag, $snippet, $spec) = @_;    # class method

    croak "check_spec_completeness: tag must be a non-empty string"
        unless defined $tag && length $tag;
    croak "check_spec_completeness: snippet must be a non-empty string"
        unless defined $snippet && length $snippet;
    croak "check_spec_completeness: spec must be a hashref"
        unless ref $spec eq 'HASH';

    # For sub-based specs, check sub_args vs the sub's parameter list.
    if (exists $spec->{sub_name}) {
        my $param_count = _extract_sub_param_count($snippet, $spec->{sub_name});
        if ($param_count > 0) {
            my $args = $spec->{sub_args} // [];
            if (scalar(@$args) == 0) {
                return "sub '$spec->{sub_name}' has $param_count parameter(s) but spec supplies no sub_args";
            }
        }
        return undef;    # adequately specified
    }

    # For class-based specs, check method_args vs the method's parameter list.
    return undef unless exists $spec->{method};

    my $method = $spec->{method};
    my $param_count = _extract_method_param_count($snippet, $method);
    if ($param_count > 0) {
        my $args = $spec->{method_args} // [];
        if (scalar(@$args) == 0) {
            return "method '$method' has $param_count parameter(s) but spec supplies no method_args";
        }
    }
    return undef;    # adequately specified
}

# Build a spec for running a corpus entry through RunUnderPerl.
# Most corpus entries are class C { method m() { ... } }; a few are not.
# For non-class entries (I2, M1, M2) we return a 'sub_name' spec for capture_sub.
#
# Parameterized idioms have representative method_args that exercise the
# interesting behavior (not just the degenerate undef-arg path).
# Multi-outcome idioms (logical ops, ternary, regex match) use the first
# representative arg here; bilateral coverage is provided by the batch tests.
sub _spec_for {
    my ($tag, $snippet) = @_;

    # Non-class top-level-sub entries: I2, M1, M2.
    # These define a top-level sub named 'greet' which is called directly.
    # Args per idiom: I2 passes 'world', M1 and M2 pass no args.
    my %SUB_SPECS = (
        I2 => { sub_name => 'greet', sub_args => ['world'], context => 'scalar' },
        M1 => { sub_name => 'greet', sub_args => [],        context => 'scalar' },
        M2 => { sub_name => 'greet', sub_args => [],        context => 'scalar' },
    );
    if (exists $SUB_SPECS{$tag}) {
        return $SUB_SPECS{$tag};
    }

    return undef unless $snippet =~ /class\s+C\s*\{/;

    # Per-tag representative args for parameterized idioms.
    # Chosen so the interesting behavior is exercised (not just the undef path).
    # Bilateral cases (both true/false outcome branches) are covered by batch tests.
    my %PARAM_ARGS = (
        # D6: ternary $n > 0 ? 1 : 2 — pass n=1 so the true branch (1) is taken.
        D6  => [1],
        # J1: regex match $s =~ /foo/ — pass 'foobar' so the match succeeds.
        J1  => ['foobar'],
        # J2: s/foo/bar/ — pass 'foobar' so the substitution actually fires.
        J2  => ['foobar'],
        # L1: $a && $b — pass (1, 2): both truthy, returns 2 (last truthy value).
        L1  => [1, 2],
        # L2: $a || $b — pass (0, 3): left false so right (3) is returned.
        L2  => [0, 3],
        # L3: $a // $b — pass (undef, 4): left undefined so right (4) is returned.
        L3  => [undef, 4],
        # L4: !$a — pass (0): false input, so !0 = true (1).
        L4  => [0],
        # M3: "hello $name" — pass 'world' so interpolation produces "hello world".
        M3  => ['world'],
        # M8: $r->[0] — pass a real arrayref [42] so the deref executes and returns 42.
        M8  => [[42]],
        # M9: $r->{key} — pass a real hashref {key=>7} so the deref executes and returns 7.
        M9  => [{ key => 7 }],
        # M14: "got " . $a — pass 'it' so concatenation yields "got it".
        M14 => ['it'],
        # M15: $y //= $x — pass 5 so defined-or assign gives $y = 5.
        M15 => [5],
        # M24: $r->{a}->[0] — pass a real nested ref {a=>[9]} so the chained deref returns 9.
        M24 => [{ a => [9] }],
    );

    my $method_args = $PARAM_ARGS{$tag} // [];

    # Class-based entries: instantiate C and call method m().
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => $method_args,
        context     => 'scalar',
    };
    return $spec;
}

# Run one corpus entry through the rig and return an entry hashref.
# The entry always carries: { tag, group, verdict, extra }.
sub _run_one {
    my ($tag, $group, $corpus_text) = @_;

    # Check the out-of-subset registry first.  REJECT idioms are classified
    # immediately: they stay in the denominator but never reach the codegen rig.
    if (exists $REJECT_IDIOMS{$tag}) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'REJECT',
            extra   => {
                reason           => $REJECT_IDIOMS{$tag},
                classification   => 'out-of-subset',
            },
        };
    }

    # Extract the snippet from the corpus.
    my $snippet = eval {
        Chalk::CodeGen::Harness::RunUnderPerl->extract_snippet($corpus_text, $tag);
    };
    if ($@) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'NOT-YET-COVERED',
            extra   => { reason => "corpus extract failed: $@" },
        };
    }

    # Try to get a hand graph for this tag.
    my $mop = eval {
        Chalk::CodeGen::Harness::HandGraphs->graph_for($tag);
    };
    if ($@) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'NOT-YET-COVERED',
            extra   => { reason => "graph_for died: $@" },
        };
    }

    # No hand graph yet — record NOT-YET-COVERED (still in denominator).
    # If the tag has a recorded deferral reason, surface it instead of the
    # generic "no hand graph defined" so the artifact documents the decision.
    unless (defined $mop) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'NOT-YET-COVERED',
            extra   => {
                reason => $DEFERRED_REASONS{$tag} // 'no hand graph defined',
            },
        };
    }

    # We have a hand graph. Build a spec for exercising the snippet.
    my $spec = _spec_for($tag, $snippet);
    unless (defined $spec) {
        # Graph exists but snippet cannot be exercised via class rig.
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'NOT-YET-COVERED',
            extra   => { reason => 'non-class snippet; cannot exercise via class rig' },
        };
    }

    # Structural guard: a spec that supplies no args for a parameterized method
    # would produce a vacuous PASS via the degenerate undef-arg path.
    # UNDER_SPECIFIED is a correctness alarm, not backlog.
    my $under_spec_reason = eval {
        Chalk::CodeGen::Harness::GapMap->check_spec_completeness($tag, $snippet, $spec)
    };
    if ($under_spec_reason) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'UNDER_SPECIFIED',
            extra   => {
                reason           => "spec is under-specified: $under_spec_reason",
                implicated_layer => 'spec',
            },
        };
    }

    # Determine exercise mode: sub-name spec uses capture_sub; class spec uses capture.
    my $is_sub_spec = exists $spec->{sub_name};

    # Run the S side (oracle via RunUnderPerl).
    my $S = eval {
        $is_sub_spec
            ? Chalk::CodeGen::Harness::RunUnderPerl->capture_sub($snippet, $spec)
            : Chalk::CodeGen::Harness::RunUnderPerl->capture($snippet, $spec);
    };
    if ($@) {
        my $err = $@;
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                reason => "oracle capture failed: $err",
                implicated_layer => 'oracle',
            },
        };
    }

    # Run the P side (generated via PerlDriver).
    my ($P, $emission_meta) = eval {
        Chalk::CodeGen::Harness::PerlDriver->run($mop, $spec);
    };
    if ($@) {
        my $err = $@;
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                reason => "driver run failed: $err",
                implicated_layer => 'codegen',
            },
        };
    }

    # Classify via Comparator.
    $emission_meta->{graph_source} //= "hand:$tag";
    my $verdict_rec = eval {
        Chalk::CodeGen::Harness::Comparator->verdict($S, $P, $emission_meta);
    };
    if ($@) {
        my $err = $@;
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'GAP',
            extra   => {
                reason => "comparator died: $err",
                implicated_layer => 'harness',
            },
        };
    }

    my $verdict_str = $verdict_rec->{verdict} // 'GAP';

    # If Comparator returned GAP (incomplete emission), report as NOT-YET-COVERED
    # when the reason is "no graph" — but here we have a graph, so GAP means
    # "graph exists but emission was incomplete", which is still a real GAP.
    return {
        tag     => $tag,
        group   => $group,
        verdict => $verdict_str,
        extra   => $verdict_rec,
    };
}

# Build the summary section from the entries list.
sub _build_summary {
    my ($entries) = @_;

    my %by_verdict;
    my %by_group;

    for my $entry (@$entries) {
        my $v = $entry->{verdict} // 'UNKNOWN';
        my $g = $entry->{group}   // 'UNKNOWN';
        $by_verdict{$v}++;
        $by_group{$g}{count}++;
        $by_group{$g}{verdicts}{$v}++;
    }

    return {
        denominator => scalar(@$entries),
        by_verdict  => \%by_verdict,
        by_group    => \%by_group,
    };
}

# Write the gap-map artifact as JSON.
sub _write_artifact {
    my ($gap_map) = @_;

    # Ensure the directory exists.
    my $dir = $ARTIFACT_FILE;
    $dir =~ s|/[^/]+$||;
    unless (-d $dir) {
        mkdir $dir or croak "GapMap: cannot create artifact dir '$dir': $!";
    }

    open my $fh, '>', $ARTIFACT_FILE
        or croak "GapMap: cannot write artifact '$ARTIFACT_FILE': $!";

    my $json = JSON::PP->new->utf8->canonical->encode($gap_map);
    print $fh $json;
    close $fh;
}

# ---------------------------------------------------------------------------
# _extract_method_param_count($snippet, $method_name) -> $count
#
# Parses the Perl snippet for a method declaration matching:
#   method $method_name($param, ...) { ... }
# Returns the number of declared parameters (excluding $self, which is
# implicit in Perl 5.42 class methods and not listed in the signature).
# Returns 0 if the method has no parameters or is not found.
# ---------------------------------------------------------------------------
sub _extract_method_param_count {
    my ($snippet, $method) = @_;
    return 0 unless defined $snippet && defined $method && length $method;

    # Match:  method m($a, $b) { ... }  or  method m() { ... }
    # The signature is the content between the outer parentheses after the method name.
    if ($snippet =~ /\bmethod\s+\Q$method\E\s*\(([^)]*)\)/) {
        my $sig = $1 // '';
        $sig =~ s/^\s+|\s+$//g;
        return 0 unless length $sig;

        # Count comma-separated parameters (each starts with $, @, or %).
        my @params = split /\s*,\s*/, $sig;
        my $count  = scalar grep { /^\s*[\$\@\%]/ } @params;
        return $count;
    }
    return 0;
}

# ---------------------------------------------------------------------------
# _extract_sub_param_count($snippet, $sub_name) -> $count
#
# Same as _extract_method_param_count but for top-level subs:
#   sub $sub_name($param, ...) { ... }
# ---------------------------------------------------------------------------
sub _extract_sub_param_count {
    my ($snippet, $sub_name) = @_;
    return 0 unless defined $snippet && defined $sub_name && length $sub_name;

    if ($snippet =~ /\bsub\s+\Q$sub_name\E\s*\(([^)]*)\)/) {
        my $sig = $1 // '';
        $sig =~ s/^\s+|\s+$//g;
        return 0 unless length $sig;

        my @params = split /\s*,\s*/, $sig;
        my $count  = scalar grep { /^\s*[\$\@\%]/ } @params;
        return $count;
    }
    return 0;
}

1;

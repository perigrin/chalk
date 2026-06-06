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

# Build a default spec for running a corpus entry through RunUnderPerl.
# Most corpus entries are class C { method m() { ... } }; a few are not.
# For non-class entries (I2, M1, M2) we return a 'sub_name' spec for capture_sub.
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

    # Class-based entries: instantiate C and call method m().
    my $spec = {
        class       => 'C',
        constructor => { params => {} },
        method      => 'm',
        method_args => [],
        context     => 'scalar',
    };
    return $spec;
}

# Run one corpus entry through the rig and return an entry hashref.
# The entry always carries: { tag, group, verdict, extra }.
sub _run_one {
    my ($tag, $group, $corpus_text) = @_;

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
    unless (defined $mop) {
        return {
            tag     => $tag,
            group   => $group,
            verdict => 'NOT-YET-COVERED',
            extra   => { reason => 'no hand graph defined' },
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

1;

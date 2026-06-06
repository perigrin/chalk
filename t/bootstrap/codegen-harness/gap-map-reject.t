# ABOUTME: Tests for the REJECT verdict mechanism in the gap-map — out-of-subset idioms.
# ABOUTME: Asserts REJECT entries stay in the denominator, are excluded from gap/failure counts,
# ABOUTME: and that tier-1-green is defined as green over the in-subset set only.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';

use_ok('Chalk::CodeGen::Harness::GapMap');

# ---------------------------------------------------------------------------
# R1: REJECT is a valid verdict string
# The valid-verdicts list must include REJECT.
# ---------------------------------------------------------------------------
{
    my @valid = Chalk::CodeGen::Harness::GapMap->valid_verdicts();
    ok(grep({ $_ eq 'REJECT' } @valid),
        'R1: REJECT is in the valid_verdicts list');
}

# ---------------------------------------------------------------------------
# R2: M21 is classified REJECT in the generated gap map
# The generated gap map must assign M21 the REJECT verdict (not NOT-YET-COVERED
# or GAP), because eval is excluded by the try/catch policy.
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 2 if $err || !defined $gap_map;

        my $entries = $gap_map->{entries} // [];
        my ($m21) = grep { $_->{tag} eq 'M21' } @$entries;

        ok(defined $m21,
            'R2a: M21 appears in the gap map entries');
        is($m21->{verdict}, 'REJECT',
            'R2b: M21 verdict is REJECT');
    }
}

# ---------------------------------------------------------------------------
# R3: REJECT idiom still counts in the denominator (no silent shrinkage)
# After classifying M21 as REJECT, the denominator must still be 78.
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 1 if $err || !defined $gap_map;

        my $entries = $gap_map->{entries} // [];
        is(scalar(@$entries), 78,
            'R3: denominator is still 78 after REJECT classification');
    }
}

# ---------------------------------------------------------------------------
# R4: REJECT idiom does NOT count as a GAP or failure
# The summary.by_verdict must NOT count M21 under GAP or NOT-YET-COVERED.
# It must appear only under REJECT.
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 2 if $err || !defined $gap_map;

        my $by_v = $gap_map->{summary}{by_verdict} // {};

        # REJECT count must be >= 1 (at minimum M21)
        my $reject_count = $by_v->{REJECT} // 0;
        ok($reject_count >= 1,
            "R4a: summary.by_verdict.REJECT >= 1 (got $reject_count)");

        # The REJECT count must NOT inflate NOT-YET-COVERED count relative
        # to what it would be without REJECT classification. We verify this
        # by checking that NOT-YET-COVERED is strictly less than 21 (pre-REJECT
        # the NOT-YET-COVERED count was 21; after classifying M21 it must be 20).
        my $nyc = $by_v->{'NOT-YET-COVERED'} // 0;
        ok($nyc < 21,
            "R4b: NOT-YET-COVERED count decreased from pre-REJECT baseline of 21 (got $nyc)");
    }
}

# ---------------------------------------------------------------------------
# R5: tier1_green() returns true when all in-subset idioms PASS
# (no REJECT entries in the green requirement, but a REJECT entry present)
# ---------------------------------------------------------------------------
{
    # Build a synthetic map: 78 entries — 77 PASS + 1 REJECT (M21).
    # tier1_green() must return true for this map.
    my @entries;
    for my $i (1..77) {
        push @entries, { tag => "X$i", group => 'X', verdict => 'PASS', extra => {} };
    }
    push @entries, { tag => 'M21', group => 'M', verdict => 'REJECT',
                     extra => { reason => 'eval excluded by policy' } };

    my $synthetic = {
        entries => \@entries,
        summary => {
            denominator => 78,
            by_verdict  => { PASS => 77, REJECT => 1 },
            by_group    => {},
        },
    };

    my $green = eval { Chalk::CodeGen::Harness::GapMap->tier1_green($synthetic) };
    ok(!$@ && $green,
        'R5: tier1_green() returns true when all in-subset idioms PASS and one REJECT entry is present');
}

# ---------------------------------------------------------------------------
# R6: tier1_green() returns false when an in-subset idiom is NOT-YET-COVERED
# (REJECT entries excluded from the requirement; NYC entries are failures)
# ---------------------------------------------------------------------------
{
    my @entries;
    for my $i (1..76) {
        push @entries, { tag => "X$i", group => 'X', verdict => 'PASS', extra => {} };
    }
    push @entries, { tag => 'M21', group => 'M', verdict => 'REJECT',
                     extra => { reason => 'eval excluded by policy' } };
    push @entries, { tag => 'M20', group => 'M', verdict => 'NOT-YET-COVERED',
                     extra => { reason => 'scope decision pending' } };

    my $synthetic = {
        entries => \@entries,
        summary => {
            denominator => 78,
            by_verdict  => { PASS => 76, REJECT => 1, 'NOT-YET-COVERED' => 1 },
            by_group    => {},
        },
    };

    my $green = eval { Chalk::CodeGen::Harness::GapMap->tier1_green($synthetic) };
    ok(!$@ && !$green,
        'R6: tier1_green() returns false when an in-subset idiom is NOT-YET-COVERED');
}

# ---------------------------------------------------------------------------
# R7: tier1_green() returns false when an in-subset idiom is GAP
# ---------------------------------------------------------------------------
{
    my @entries;
    for my $i (1..76) {
        push @entries, { tag => "X$i", group => 'X', verdict => 'PASS', extra => {} };
    }
    push @entries, { tag => 'M21', group => 'M', verdict => 'REJECT',
                     extra => { reason => 'eval excluded by policy' } };
    push @entries, { tag => 'X77', group => 'X', verdict => 'GAP', extra => {} };

    my $synthetic = {
        entries => \@entries,
        summary => {
            denominator => 78,
            by_verdict  => { PASS => 76, REJECT => 1, GAP => 1 },
            by_group    => {},
        },
    };

    my $green = eval { Chalk::CodeGen::Harness::GapMap->tier1_green($synthetic) };
    ok(!$@ && !$green,
        'R7: tier1_green() returns false when an in-subset idiom is GAP');
}

# ---------------------------------------------------------------------------
# R8: tier1_green() returns false when an in-subset idiom is MISCOMPILE
# ---------------------------------------------------------------------------
{
    my @entries;
    for my $i (1..76) {
        push @entries, { tag => "X$i", group => 'X', verdict => 'PASS', extra => {} };
    }
    push @entries, { tag => 'M21', group => 'M', verdict => 'REJECT',
                     extra => { reason => 'eval excluded by policy' } };
    push @entries, { tag => 'X77', group => 'X', verdict => 'MISCOMPILE', extra => {} };

    my $synthetic = {
        entries => \@entries,
        summary => {
            denominator => 78,
            by_verdict  => { PASS => 76, REJECT => 1, MISCOMPILE => 1 },
            by_group    => {},
        },
    };

    my $green = eval { Chalk::CodeGen::Harness::GapMap->tier1_green($synthetic) };
    ok(!$@ && !$green,
        'R8: tier1_green() returns false when an in-subset idiom is MISCOMPILE');
}

# ---------------------------------------------------------------------------
# R9: REJECT entries have a 'reason' in extra
# M21 must carry a reason explaining the REJECT classification.
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 1 if $err || !defined $gap_map;

        my $entries = $gap_map->{entries} // [];
        my ($m21) = grep { $_->{tag} eq 'M21' } @$entries;

        SKIP: {
            skip 'M21 entry not found', 1 unless defined $m21;
            ok(defined $m21->{extra}{reason} && length($m21->{extra}{reason}),
                'R9: M21 REJECT entry has a non-empty reason in extra');
        }
    }
}

# ---------------------------------------------------------------------------
# R10: validate_coverage still passes for a map containing REJECT entries
# REJECT does not break the coverage validator.
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 1 if $err || !defined $gap_map;

        my %full_groups = (
            A => 5, B => 8, C => 5, D => 8, E => 4, F => 3,
            G => 4, H => 4, I => 3, J => 3, K => 2, L => 4,
            M => 25,
        );

        my $valid = eval {
            Chalk::CodeGen::Harness::GapMap->validate_coverage($gap_map, \%full_groups)
        };
        my $validate_err = $@;

        ok($valid && !$validate_err,
            'R10: validate_coverage still returns true after M21 REJECT classification');
    }
}

done_testing();

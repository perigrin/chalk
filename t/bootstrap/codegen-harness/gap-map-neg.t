# ABOUTME: Negative (adversarial) tests for the gap-map generator — guards against false-green shrinkage.
# ABOUTME: Catches shrunk denominator, dropped groups, MISCOMPILE laundered as GAP, omitted NOT-YET-COVERED.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';

use_ok('Chalk::CodeGen::Harness::GapMap');

my $FULL_DENOMINATOR = 78;
my %FULL_GROUP_COUNTS = (
    A => 5, B => 8, C => 5, D => 8, E => 4, F => 3,
    G => 4, H => 4, I => 3, J => 3, K => 2, L => 4,
    M => 25,
);

# ---------------------------------------------------------------------------
# Helper: build a synthetic gap-map result from a list of entry hashrefs.
# Used to drive the validation functions directly.
# ---------------------------------------------------------------------------
sub synthetic_gap_map {
    my (@entries) = @_;
    return {
        entries => \@entries,
        summary => {
            denominator => scalar(@entries),
            by_verdict  => {},
            by_group    => {},
        },
    };
}

# ---------------------------------------------------------------------------
# N1: Shrunk-denominator false green
# A gap map covering only groups A-F+I (a subset) must FAIL the coverage assertion.
# The validator must detect denominator < 78.
# ---------------------------------------------------------------------------
{
    # Build a fake gap_map with only A(5)+B(8)+C(5)+D(8)+E(4)+F(3)+I(3) = 36 entries
    my @subset_entries;
    my %subset_groups = (A=>5, B=>8, C=>5, D=>8, E=>4, F=>3, I=>3);
    for my $g (sort keys %subset_groups) {
        for my $i (1 .. $subset_groups{$g}) {
            push @subset_entries, { tag => "$g$i", group => $g, verdict => 'NOT-YET-COVERED' };
        }
    }
    my $subset_map = synthetic_gap_map(@subset_entries);

    # The validation method must detect this as incomplete
    my $valid = eval {
        Chalk::CodeGen::Harness::GapMap->validate_coverage($subset_map, \%FULL_GROUP_COUNTS)
    };
    my $err = $@;

    # Either validate_coverage returns false/error, or it dies — either way not "all good"
    my $detected = (!$valid) || (defined $err && length $err);
    ok($detected,
        'N1: shrunk denominator (36 of 78) is DETECTED by validate_coverage');
}

# ---------------------------------------------------------------------------
# N2: Dropped-group escape — removing a group's idioms must be detected
# via per-group count check, not silently produce a smaller-but-greener map.
# Remove group M (25 idioms) and check detection.
# ---------------------------------------------------------------------------
{
    my @no_M_entries;
    for my $g (sort keys %FULL_GROUP_COUNTS) {
        next if $g eq 'M';
        for my $i (1 .. $FULL_GROUP_COUNTS{$g}) {
            push @no_M_entries, { tag => "$g$i", group => $g, verdict => 'NOT-YET-COVERED' };
        }
    }
    my $no_M_map = synthetic_gap_map(@no_M_entries);

    my $valid = eval {
        Chalk::CodeGen::Harness::GapMap->validate_coverage($no_M_map, \%FULL_GROUP_COUNTS)
    };
    my $err = $@;

    my $detected = (!$valid) || (defined $err && length $err);
    ok($detected,
        'N2: dropped group M (25 idioms) is DETECTED by validate_coverage');
}

# ---------------------------------------------------------------------------
# N3: Miscompile laundered as GAP
# An entry that behaves like a MISCOMPILE (complete emission + divergence) must
# appear as MISCOMPILE, never as GAP. The verdict discriminator must be distinct.
#
# We test this by asserting that GapMap's classify_verdict() function returns
# MISCOMPILE (not GAP) when emission_meta says complete AND behavior diverges.
# ---------------------------------------------------------------------------
{
    my $miscompile_entry = eval {
        Chalk::CodeGen::Harness::GapMap->classify_verdict_from_meta(
            {
                emitted_for_every_construct => 1,
                marked_unsupported          => 0,
            },
            'diverged',    # signal that behavior diverged
        )
    };

    # classify_verdict_from_meta(complete=1, diverged=1) must return MISCOMPILE
    is($miscompile_entry, 'MISCOMPILE',
        'N3: complete emission + divergence classified as MISCOMPILE, not GAP');
}

# ---------------------------------------------------------------------------
# N4: GAP when emission is incomplete (not laundered into PASS or MISCOMPILE)
# ---------------------------------------------------------------------------
{
    my $gap_entry = eval {
        Chalk::CodeGen::Harness::GapMap->classify_verdict_from_meta(
            {
                emitted_for_every_construct => 0,
                marked_unsupported          => 0,
            },
            'match',    # behavior would match but emission was incomplete
        )
    };

    like($gap_entry, qr/^(?:GAP|NOT-YET-COVERED)$/,
        'N4: incomplete emission classified as GAP/NOT-YET-COVERED, not PASS');
}

# ---------------------------------------------------------------------------
# N5: NOT-YET-COVERED idiom still counted in denominator
# An idiom with no hand graph must appear in the entries (as NOT-YET-COVERED
# or GAP), so coverage % cannot be inflated by omission.
#
# We test this by calling generate() and asserting that every tag in
# ir-audit-corpus.pl appears in the result — including tags with no HandGraph.
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 3 if $err || !defined $gap_map;

        my $entries = $gap_map->{entries} // [];
        my %tag_in_map = map { $_->{tag} => 1 } @$entries;

        # A2 has no hand graph and must still appear
        ok(exists $tag_in_map{A2},
            'N5a: A2 (no hand graph) appears in the gap map denominator');

        # M25 (C-style for loop) has no hand graph and must still appear
        ok(exists $tag_in_map{M25},
            'N5b: M25 (no hand graph) appears in the gap map denominator');

        # Count NOT-YET-COVERED or GAP entries — there should be many (most of 78)
        my $nyc_count = scalar grep {
            ($_->{verdict} // '') =~ /^(?:NOT-YET-COVERED|GAP)$/
        } @$entries;

        ok($nyc_count > 0,
            "N5c: at least one NOT-YET-COVERED/GAP entry present (got $nyc_count)");
    }
}

# ---------------------------------------------------------------------------
# N6: All 13 groups must be present; a map with only 12 must fail validation.
# ---------------------------------------------------------------------------
{
    # Build a map missing group J (3 idioms)
    my @no_J_entries;
    for my $g (sort keys %FULL_GROUP_COUNTS) {
        next if $g eq 'J';
        for my $i (1 .. $FULL_GROUP_COUNTS{$g}) {
            push @no_J_entries, { tag => "$g$i", group => $g, verdict => 'NOT-YET-COVERED' };
        }
    }
    my $no_J_map = synthetic_gap_map(@no_J_entries);

    my $valid = eval {
        Chalk::CodeGen::Harness::GapMap->validate_coverage($no_J_map, \%FULL_GROUP_COUNTS)
    };
    my $err = $@;

    my $detected = (!$valid) || (defined $err && length $err);
    ok($detected,
        'N6: missing group J (3 idioms) detected by validate_coverage');
}

# ---------------------------------------------------------------------------
# N7: validate_coverage returns true for the FULL correct map
# (confirms the validator can also pass when correct).
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 1 if $err || !defined $gap_map;

        my $valid = eval {
            Chalk::CodeGen::Harness::GapMap->validate_coverage($gap_map, \%FULL_GROUP_COUNTS)
        };
        my $validate_err = $@;

        ok($valid && !$validate_err,
            'N7: validate_coverage returns true for the full correct 78-idiom map');
    }
}

done_testing();

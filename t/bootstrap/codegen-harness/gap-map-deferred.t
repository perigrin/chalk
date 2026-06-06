# ABOUTME: Tests for the IN-SUBSET-DEFERRED verdict in the gap-map — deferred-debt idioms.
# ABOUTME: Asserts DEFERRED entries stay in the denominator, are excluded from tier-1-green
# ABOUTME: (like REJECT but in-subset), and carry a reason documenting the deferral.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib';

use_ok('Chalk::CodeGen::Harness::GapMap');

# ---------------------------------------------------------------------------
# D1: DEFERRED is a valid verdict string.
# ---------------------------------------------------------------------------
{
    my @valid = Chalk::CodeGen::Harness::GapMap->valid_verdicts();
    ok(grep({ $_ eq 'DEFERRED' } @valid),
        'D1: DEFERRED is in the valid_verdicts list');
}

# ---------------------------------------------------------------------------
# D2: M20 (do-block) is classified DEFERRED in the generated gap map.
# M20 was decided IN-SUBSET-DEFERRED (do-block is valid Perl, used in lib/,
# needed for the self-host capstone, but needs a Do IR node + grammar rule).
# It must carry verdict DEFERRED, not NOT-YET-COVERED.
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    my $err = $@;

    SKIP: {
        skip "generate() failed: $err", 3 if $err || !defined $gap_map;

        my $entries = $gap_map->{entries} // [];
        my ($m20) = grep { $_->{tag} eq 'M20' } @$entries;

        ok(defined $m20,
            'D2a: M20 appears in the gap map entries');
        is($m20->{verdict}, 'DEFERRED',
            'D2b: M20 verdict is DEFERRED');
        like($m20->{extra}{reason} // '', qr/Do\b.*grammar|IN-SUBSET-DEFERRED/i,
            'D2c: M20 carries the deferral reason');
    }
}

# ---------------------------------------------------------------------------
# D3: DEFERRED idiom still counts in the denominator (no silent shrinkage).
# ---------------------------------------------------------------------------
{
    my $gap_map = eval { Chalk::CodeGen::Harness::GapMap->generate() };
    SKIP: {
        skip "generate() failed", 1 unless defined $gap_map;
        my $entries = $gap_map->{entries} // [];
        is(scalar(@$entries), 78,
            'D3: denominator is still 78 (DEFERRED entries not dropped)');
    }
}

# ---------------------------------------------------------------------------
# D4: tier1_green excludes DEFERRED from the green requirement.
# A gap map where every entry is PASS except one DEFERRED must be GREEN
# (deferred-debt does not block green), mirroring the REJECT exclusion.
# ---------------------------------------------------------------------------
{
    my $gm = {
        entries => [
            { tag => 'A1', verdict => 'PASS' },
            { tag => 'M20', verdict => 'DEFERRED' },
            { tag => 'M21', verdict => 'REJECT' },
        ],
    };
    ok(Chalk::CodeGen::Harness::GapMap->tier1_green($gm),
        'D4: tier1_green is true when only DEFERRED/REJECT remain alongside PASS');
}

# ---------------------------------------------------------------------------
# D5: a genuine NOT-YET-COVERED still blocks green (DEFERRED is not a loophole).
# DEFERRED must not be a way to launder real undone work — only the explicitly
# registered deferred idioms get DEFERRED; an ordinary NOT-YET-COVERED still
# blocks green.
# ---------------------------------------------------------------------------
{
    my $gm = {
        entries => [
            { tag => 'A1', verdict => 'PASS' },
            { tag => 'I1', verdict => 'NOT-YET-COVERED' },
        ],
    };
    ok(!Chalk::CodeGen::Harness::GapMap->tier1_green($gm),
        'D5: tier1_green is false when an in-subset NOT-YET-COVERED remains');
}

done_testing();

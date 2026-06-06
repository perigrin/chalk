# ABOUTME: Tests for the LLVM IR-completeness gap-map over the computation slice (Phase 3b).
# ABOUTME: Asserts the artifact is produced, well-formed, and enforces the false-green guard.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

my $LLI = '/usr/lib/llvm-15/bin/lli';

unless (-x $LLI) {
    plan skip_all => "lli not found at $LLI — LLVM gap-map requires lli";
}

# ---------------------------------------------------------------------------
# T1: LLVMGapMap module loads.
# ---------------------------------------------------------------------------
use_ok('Chalk::CodeGen::Harness::LLVMGapMap');

# ---------------------------------------------------------------------------
# T2: generate() class method exists.
# ---------------------------------------------------------------------------
ok(Chalk::CodeGen::Harness::LLVMGapMap->can('generate'),
    'LLVMGapMap has a generate() class method');

# ---------------------------------------------------------------------------
# T3: generate() returns a well-formed hashref without dying.
# ---------------------------------------------------------------------------
my $gap_map;
{
    $gap_map = eval { Chalk::CodeGen::Harness::LLVMGapMap->generate() };
    is($@, '', 'LLVMGapMap->generate() does not die')
        or diag("generate() died: $@");
}

SKIP: {
    skip 'generate() failed', 25 unless defined $gap_map;

    # T4: artifact has 'entries' key.
    ok(exists $gap_map->{entries}, 'llvm_gap_map has entries key');

    my $entries = $gap_map->{entries} // [];

    # T5: every entry has the required fields.
    my $all_have_fields = 1;
    for my $e (@$entries) {
        unless (defined $e->{tag} && defined $e->{group} && defined $e->{verdict}) {
            $all_have_fields = 0;
            last;
        }
    }
    ok($all_have_fields, 'every entry has tag, group, and verdict fields');

    # T6: all verdicts are from the valid set.
    my %VALID_VERDICTS = map { $_ => 1 } qw(L-GREEN GAP MISCOMPILE);
    my $all_valid = 1;
    my @bad;
    for my $e (@$entries) {
        unless ($VALID_VERDICTS{ $e->{verdict} // '' }) {
            $all_valid = 0;
            push @bad, "$e->{tag}: " . ($e->{verdict} // 'undef');
        }
    }
    ok($all_valid, 'every verdict is L-GREEN | GAP | MISCOMPILE')
        or diag("invalid verdicts: @bad");

    # T7: MISCOMPILE and GAP are distinct — a MISCOMPILE must have lowered
    # (no Scalar, no libperl), while GAP must have failed to lower runtime-free.
    # Verify that no entry simultaneously signals both.
    my $no_overlap = 1;
    for my $e (@$entries) {
        if (($e->{verdict} // '') eq 'MISCOMPILE') {
            # A MISCOMPILE must NOT have a gap_reason — it lowered successfully.
            if (defined $e->{extra}{gap_reason}) {
                $no_overlap = 0;
                last;
            }
        }
    }
    ok($no_overlap, 'MISCOMPILE entries have no gap_reason (distinct from GAP)');

    # T8: at least one L-GREEN entry exists (the literal-arithmetic slice is L-GREEN).
    my @greens = grep { ($_->{verdict} // '') eq 'L-GREEN' } @$entries;
    ok(@greens >= 1, 'at least one L-GREEN entry exists (literal arithmetic slice)');

    # T9: every L-GREEN entry has libperl_free = 1.
    my $greens_libperl_free = 1;
    for my $e (@greens) {
        unless ($e->{extra}{libperl_free}) {
            $greens_libperl_free = 0;
            last;
        }
    }
    ok($greens_libperl_free, 'every L-GREEN entry is libperl-free (false-green guard)');

    # T10: every L-GREEN entry has runtime_free_coverage = 1.0 (100%).
    my $greens_full_coverage = 1;
    for my $e (@greens) {
        my $cov = $e->{extra}{runtime_free_coverage} // 0;
        unless ($cov == 1.0) {
            $greens_full_coverage = 0;
            last;
        }
    }
    ok($greens_full_coverage,
        'every L-GREEN entry has runtime_free_coverage == 1.0 (100% runtime-free)');

    # T11: every L-GREEN entry has lli_output matching perl_oracle.
    my $greens_match_oracle = 1;
    for my $e (@greens) {
        my $lli    = $e->{extra}{lli_output} // '';
        my $oracle = $e->{extra}{perl_oracle} // '';
        unless ($lli eq $oracle) {
            $greens_match_oracle = 0;
            last;
        }
    }
    ok($greens_match_oracle,
        'every L-GREEN entry: lli_output == perl_oracle');

    # T12: every GAP entry has a gap_reason (representation-missing / coercion-missing /
    # guard-missing / no-graph-for-idiom).
    my @gaps = grep { ($_->{verdict} // '') eq 'GAP' } @$entries;
    my $gaps_have_reason = 1;
    for my $e (@gaps) {
        unless (defined $e->{extra}{gap_reason} && length $e->{extra}{gap_reason}) {
            $gaps_have_reason = 0;
            last;
        }
    }
    ok($gaps_have_reason, 'every GAP entry has a gap_reason');

    # T13: GAP entries have a gap_category (representation-missing | coercion-missing |
    # guard-missing | not-in-computation-slice).
    my @valid_gap_cats = qw(
        representation-missing
        coercion-missing
        guard-missing
        not-in-computation-slice
        lowering-not-implemented
    );
    my %valid_gap_cat = map { $_ => 1 } @valid_gap_cats;
    my $gaps_have_category = 1;
    for my $e (@gaps) {
        my $cat = $e->{extra}{gap_category} // '';
        unless ($valid_gap_cat{$cat}) {
            $gaps_have_category = 0;
            last;
        }
    }
    ok($gaps_have_category, 'every GAP entry has a valid gap_category')
        or do {
            for my $gap_e (grep { !$valid_gap_cat{$_->{extra}{gap_category}//'unknown'} } @gaps) {
                diag("  $gap_e->{tag}: gap_category=" . ($gap_e->{extra}{gap_category}//'undef'));
            }
        };

    # T14: FALSE-GREEN GUARD — a deliberately Scalar-heavy idiom must NOT get L-GREEN.
    # LLVMGapMap provides a method to run a synthetic Scalar-repr graph and verify
    # the verdict is GAP, never L-GREEN.
    ok(Chalk::CodeGen::Harness::LLVMGapMap->can('verdict_for_scalar_graph'),
        'LLVMGapMap has verdict_for_scalar_graph() for the false-green guard test');

    my $scalar_verdict = eval {
        Chalk::CodeGen::Harness::LLVMGapMap->verdict_for_scalar_graph()
    };
    is($@, '', 'verdict_for_scalar_graph() does not die');
    is($scalar_verdict, 'GAP',
        'a Scalar-representation graph verdicts GAP, never L-GREEN (false-green guard)');

    # T15: artifact file exists at the expected path.
    my $ARTIFACT = 't/fixtures/codegen-harness/llvm-gap-map.json';
    ok(-f $ARTIFACT, "artifact exists at $ARTIFACT");

    # T16: artifact is valid JSON with entries and summary.
    if (-f $ARTIFACT) {
        require JSON::PP;
        my $json_text = do {
            open my $fh, '<', $ARTIFACT or die "cannot open $ARTIFACT: $!";
            local $/;
            <$fh>;
        };
        my $from_disk = eval { JSON::PP->new->decode($json_text) };
        is($@, '', 'artifact is valid JSON');
        ok(exists $from_disk->{entries}, 'artifact has entries key');
        ok(exists $from_disk->{summary}, 'artifact has summary key');
    }
    else {
        fail('artifact JSON load skipped (file missing)');
        fail('artifact entries key');
        fail('artifact summary key');
    }

    # T17: summary has denominator, by_verdict, by_group.
    my $summary = $gap_map->{summary} // {};
    ok(exists $summary->{denominator}, 'summary has denominator');
    ok(exists $summary->{by_verdict},  'summary has by_verdict');
    ok(exists $summary->{by_group},    'summary has by_group');

    # T18: denominator equals the number of entries.
    is($summary->{denominator}, scalar(@$entries),
        'summary.denominator == count of entries');

    # T19: computation-slice groups all present.
    my %by_group = %{$summary->{by_group} // {}};
    for my $g (qw(A C D K L)) {
        ok(exists $by_group{$g}, "computation-slice group $g is present in gap-map");
    }
}

done_testing;

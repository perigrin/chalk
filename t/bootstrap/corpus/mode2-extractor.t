# ABOUTME: Tests the Mode-2 assertion extractor that harvests Test::More
# ABOUTME: is/cmp_ok/ok assertions from real perl5 t/opbasic files into corpus cases.
use 5.42.0;
use utf8;
use Test::More;

use lib 't/lib';
use Chalk::CodeGen::Harness::Mode2Extractor;

binmode Test::More->builder->output,         ':encoding(UTF-8)';
binmode Test::More->builder->failure_output, ':encoding(UTF-8)';
binmode Test::More->builder->todo_output,    ':encoding(UTF-8)';

my $E = 'Chalk::CodeGen::Harness::Mode2Extractor';

# The 5 real Test::More-shaped proving-ground files (perl5 blead t/opbasic).
my $OPBASIC = "$ENV{HOME}/dev/perl5/t/opbasic";
my @FILES = map { "$OPBASIC/$_" } qw(arith.t cmp.t concat.t magic_phase.t qq.t);

# ---------------------------------------------------------------------------
# Guard: the corpus files must exist. Without them there is nothing to prove.
# ---------------------------------------------------------------------------
for my $f (@FILES) {
    BAIL_OUT("corpus file missing: $f") unless -f $f;
}

# ---------------------------------------------------------------------------
# 1. An in-subset is(EXPR, literal) yields a valid harvested case record.
#    concat.t has `is("-", '-', '"-"')` — subject "-" , string-literal expected.
# ---------------------------------------------------------------------------
subtest 'in-subset is(EXPR, literal) yields a valid case record' => sub {
    my $res = $E->extract_file("$OPBASIC/concat.t");

    ok scalar($res->{cases}->@*), 'concat.t produced harvested cases';

    my ($case) = grep { $_->{subject} eq q{"-"} && $_->{expected} eq q{-} }
        $res->{cases}->@*;
    ok $case, 'found the is("-", \'-\') case';
    is $case->{cmp},  'eq',      'string-literal expected -> eq comparator';
    like $case->{file}, qr/concat\.t$/, 'case carries its source file';
    ok $case->{line} > 0, 'case carries a 1-based source line';
    ok !exists $case->{skip_reason}, 'a harvested case has no skip_reason';
};

# ---------------------------------------------------------------------------
# 2. R5.1: a non-literal EXPECTED -> counted skip 'non-literal-expected'.
#    qq.t has `is("\x53", chr 83)` — expected is a chr() call, not a literal.
# ---------------------------------------------------------------------------
subtest 'R5.1: non-literal expected -> counted skip' => sub {
    my $res = $E->extract_file("$OPBASIC/qq.t");

    my ($skip) = grep { $_->{reason} eq 'non-literal-expected' }
        $res->{skips}->@*;
    ok $skip, 'qq.t non-literal expected (chr 83) is a counted skip';
    is $res->{histogram}{'non-literal-expected'},
        scalar(grep { $_->{reason} eq 'non-literal-expected' } $res->{skips}->@*),
        'histogram count matches the skip list for non-literal-expected';
};

# ---------------------------------------------------------------------------
# 3. R5.3: an out-of-subset SUBJECT token -> LOUD counted skip in histogram.
#    magic_phase.t has `ok ${^GLOBAL_PHASE} eq 'START'` — a typeglob-ish
#    special var. The skip reason must NAME the offending token.
# ---------------------------------------------------------------------------
subtest 'R5.3: out-of-subset subject -> counted skip naming the token' => sub {
    my $res = $E->extract_file("$OPBASIC/magic_phase.t");

    ok scalar(keys $res->{histogram}->%*),
        'magic_phase.t published a non-empty skip histogram';

    my @named = grep { $_->{reason} =~ /^out-of-subset:/ } $res->{skips}->@*;
    ok scalar(@named), 'at least one out-of-subset skip names its token';
};

# ---------------------------------------------------------------------------
# 3b. Preamble soundness (the false-harvest trap): a subject lexical that is
#     MUTATED between its `my` binding and the assertion, or bound in a DIFFERENT
#     block, is NOT self-contained. Harvesting it with a stale `my $x = literal`
#     preamble would emit a WRONG oracle. Such subjects MUST be counted skips,
#     never harvested cases.  concat.t exercises all three:
#       L222  my $a="abc"; $a .= $a; ok($a eq 'abcabc')   -- mutated after bind
#       L785  is($a, '')   where the nearest my $a is a DIFFERENT block
#       L862  my ($a,$b)=qw(a b); ($a='A'.$b).='c'; is($a,"Abc") -- list-assign+mut
# ---------------------------------------------------------------------------
subtest 'preamble soundness: mutated/out-of-scope lexicals are not harvested' => sub {
    my $res = $E->extract_file("$OPBASIC/concat.t");
    my %case_line = map { $_->{line} => 1 } $res->{cases}->@*;

    ok !$case_line{222},
        'L222 (my $a="abc"; $a.=$a) is NOT harvested with a stale preamble';
    ok !$case_line{785},
        'L785 (nearest my $a is another block) is NOT harvested';
    ok !$case_line{862},
        'L862 (list-assign + mutation) is NOT harvested';

    # Sanity: a genuinely self-contained case IS still harvested.
    ok $case_line{264}, 'L264 is("-", \'-\') — literal both sides — still harvested';

    # ok(!$@, ...) depends on a preceding eval that set $@; without it the
    # subject is not self-contained. $@ must be treated as out-of-subset, so
    # these are counted skips, not harvested cases.
    ok !$case_line{94},  'L94 ok(!$@) is NOT harvested ($@ implies a prior eval)';
    ok !$case_line{105}, 'L105 ok(!$@) after *pi typeglob is NOT harvested';
};

# ---------------------------------------------------------------------------
# 4. GAP-not-silent-skip invariant: harvested + skipped == total seen.
#    This must hold for EVERY file — nothing is silently dropped.
# ---------------------------------------------------------------------------
subtest 'no silent drops: harvested + skipped == total assertions seen' => sub {
    for my $f (@FILES) {
        my $res = $E->extract_file($f);
        my $harvested = scalar $res->{cases}->@*;
        my $skipped   = scalar $res->{skips}->@*;
        is $harvested + $skipped, $res->{total},
            "$f: harvested($harvested) + skipped($skipped) == total($res->{total})";
    }
};

# ---------------------------------------------------------------------------
# 4b. cmp_ok(SUBJECT, OP, EXPECTED) — the corpus never uses this form, but the
#     extractor must parse it. Drive it with a synthetic temp file so the
#     comparator-carrying path is exercised (op literal -> case cmp).
# ---------------------------------------------------------------------------
subtest 'cmp_ok(SUBJECT, OP, literal) carries the operator as the comparator' => sub {
    use File::Temp qw(tempfile);
    my ($fh, $tmp) = tempfile(SUFFIX => '.t', UNLINK => 1);
    print {$fh} "use Test::More;\n";
    print {$fh} "cmp_ok(2 + 3, '==', 5, 'addition');\n";
    print {$fh} "cmp_ok(\$x, '==', 5, 'non-literal subject var');\n";
    close $fh;

    my $res = $E->extract_file($tmp);
    my ($case) = grep { $_->{cmp} eq '==' } $res->{cases}->@*;
    ok $case, 'cmp_ok literal case harvested';
    is $case->{subject},  '2 + 3', 'subject is arg0';
    is $case->{expected}, '5',     'expected is the arg2 literal';
    is $case->{cmp},      '==',    'comparator is the arg1 op literal';

    # $x has no in-scope my binding -> counted skip, not a wrong harvest.
    ok scalar($res->{skips}->@*), 'the unbound-var cmp_ok is a counted skip';
    is scalar($res->{cases}->@*) + scalar($res->{skips}->@*), $res->{total},
        'no silent drop in the synthetic cmp_ok file';
};

# ---------------------------------------------------------------------------
# 5. Aggregate over all 5 files: publish the histogram (the worklist signal)
#    and prove the global no-silent-drop invariant.
# ---------------------------------------------------------------------------
subtest 'aggregate histogram is published with no silent drops' => sub {
    my ($total, $harvested, $skipped) = (0, 0, 0);
    my %hist;

    for my $f (@FILES) {
        my $res = $E->extract_file($f);
        $total     += $res->{total};
        $harvested += scalar $res->{cases}->@*;
        $skipped   += scalar $res->{skips}->@*;
        $hist{$_} += $res->{histogram}{$_} for keys $res->{histogram}->%*;
    }

    diag "=== Mode-2 harvest over 5 t/opbasic files ===";
    diag "total assertions seen: $total";
    diag "harvested:             $harvested";
    diag "skipped:               $skipped";
    diag "--- skip histogram (reason -> count) [worklist signal] ---";
    diag sprintf("  %-28s %d", $_, $hist{$_}) for sort keys %hist;

    is $harvested + $skipped, $total,
        "GLOBAL no-silent-drop: harvested($harvested) + skipped($skipped) == total($total)";
    ok $harvested > 0, 'at least some assertions were harvestable';
    ok scalar(keys %hist), 'the skip histogram is non-empty (there is a worklist)';
};

done_testing;

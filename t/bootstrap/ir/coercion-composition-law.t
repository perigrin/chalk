# ABOUTME: Characterization of the T2 functor's composition law: for A->B->C,
# ABOUTME: does the composed emission agree with the direct A->C? Records reality.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

# ---------------------------------------------------------------------------
# WHAT THIS TEST IS
#
# T2 is a functor from Chalk types to LLVM types: it maps objects (Int, Num,
# Str... |-> i64, double, %Str...) AND arrows (the coercions between them).
# A functor must respect composition: the arrow A->C and the composite
# A->B->C must agree.
#
# They do NOT always agree today. This test is a CHARACTERIZATION, not an
# assertion that they should: it enumerates every triple, emits both routes,
# runs both under lli, and asserts the RECORDED verdict. A pair that newly
# breaks fails. A pair that is newly FIXED also fails -- deliberately -- and
# the fixer must come here and change AGREE/DIFFER, which is the point: the
# table is the record of what we know, and moving it is an acknowledgement.
#
# A test asserting "all pairs compose" would be red on 38 rows from birth and
# would be disabled within a week. This one is green on the truth.
#
# THREE KINDS OF DIFFER live in the table below, and they are NOT the same:
#
#   (1) LOSSY-BY-DESIGN. Routing through Boolean throws away everything but
#       truthiness, so Int(42)->Boolean->Str is "1" and not "42". Perl agrees
#       (`!!42 . ""` is "1"). Composition genuinely fails here and SHOULD:
#       the intermediate object is smaller than the source. Not a bug.
#       Same for Num->Int->Str (int(1.5) is 1) and Str->Int->Num ("3.9x").
#
#   (2) THE PRECISION MISCOMPILE. Int->Num->Str disagrees above 2^53 because
#       Num |-> double forces a sitofp and the mantissa cannot hold the value.
#       This one IS a bug in the representation choice -- nothing about the
#       TYPE Num requires a float REPRESENTATION -- and it is reachable in
#       real code because Add uses a repr JOIN, so an Int operand can yield a
#       Num result. See the 2^53 / 2^53+1 rows.
#
#   (3) AN OUTRIGHT INVERSION. Every Undef->Boolean row differs, and here the
#       COMPOSED route is right and the DIRECT arm is wrong. See the block
#       comment on those rows.
#
# ---------------------------------------------------------------------------
# ON %g VERSUS %.15g (the question the brief asked to check separately)
#
# CHECKED, and there is NO bug here: the Num->Str arm uses %.15g
# (Context.pm:596 defines @fmt_num_g as c"%.15g\00"; Context.pm:2118 uses it),
# which is exactly what perl uses to stringify an NV. Verified on perl 5.42:
#     perl:  print 9007199254740993.0   -> 9.00719925474099e+15
#     chalk: Int(2^53+1) -> Num -> Str  -> 9.00719925474099e+15
# They MATCH. The Int->Num->Str disagreement is therefore NOT a format-string
# defect; it is entirely the sitofp precision loss of kind (2) above. The
# brief's "%g carries 6 significant digits" hypothesis does not hold -- the
# lossy 6-digit renderings visible in this file (e.g. Num:1.23457e+14) come
# from the RETURN-tag printer in the test epilogue, not from the coercion arm.
# ---------------------------------------------------------------------------

my $LLI = '/usr/lib/llvm-15/bin/lli';
plan skip_all => "lli not found at $LLI" unless -x $LLI;

sub run_lli {
    my ($ll_text) = @_;
    my ($fh, $tmp) = tempfile(SUFFIX => '.ll', UNLINK => 1);
    binmode $fh, ':utf8';
    print $fh $ll_text;
    close $fh;
    my $out = qx($LLI $tmp 2>&1);
    chomp $out;
    return $out;
}

# Build Constant(repr=$path[0]) -> Coerce -> ... -> Coerce -> print -> Return.
# A one-hop path is the DIRECT arrow; a two-hop path is the COMPOSITE.
#
# The endpoint is OBSERVED by printing it, the way a program observes a value,
# rather than by reading a type-tagged return epilogue. Both routes end at the
# same representation C and are post-composed with the SAME arrow C->Str, so
# the observation is applied identically to both arms and cannot manufacture or
# hide a disagreement between them: if direct and composed differ at C, they
# differ after C->Str unless C->Str itself collapses them, and the verdict table
# below was re-measured against the previous epilogue-based readings to confirm
# no verdict moved. Bracketed so a correctly-printed empty string ("" from
# Undef->Str) is distinguishable from nothing printed. Three Prints rather than
# a Concat: a Coerce'd Int has no tracked length.
sub chain_graph {
    my ($val, $const_type, @path) = @_;
    my $f = Chalk::IR::NodeFactory->new;
    my $n = $f->make('Constant', value => $val, const_type => $const_type);
    $n->set_stamp($path[0]);
    for my $i (1 .. $#path) {
        $n = $f->make('Coerce', inputs => [$n],
                      from_repr => $path[$i - 1], to_repr => $path[$i]);
        $n->set_stamp($path[$i]);
    }

    my $str = $n;
    if ($path[-1] ne 'Str') {
        $str = $f->make('Coerce', inputs => [$n],
                        from_repr => $path[-1], to_repr => 'Str');
        $str->set_stamp('Str');
    }

    my $ctrl = $f->make_cfg('Start');
    for my $part ('[', $str, "]\n") {
        my $val_node = ref $part ? $part : do {
            my $k = $f->make('Constant', value => $part, const_type => 'string');
            $k->set_stamp('Str');
            $k;
        };
        my $pr = $f->make('Print', inputs => [$val_node]);
        $pr->set_control_in($ctrl);
        $ctrl = $pr;
    }

    my $u = $f->make('Constant', value => undef, const_type => 'undef');
    $u->set_stamp('Undef');
    my $ret = $f->make_cfg('Return', inputs => [$u]);
    $ret->set_control_in($ctrl);
    return $ret;
}

# Emit and run one route. Returns the lli output, or a marker string.
sub emit_route {
    my ($val, $const_type, @path) = @_;
    my $ll = eval { Chalk::Target::LLVM->lower(chain_graph($val, $const_type, @path),
                                               program_mode => 1) };
    return 'LOWER-FAIL' if $@;
    my $out = run_lli($ll);
    return 'LLI-FAIL' if $out =~ /error:/;
    return $out;
}

# The probe values, per SOURCE representation. Boundary values matter most:
# 2^53 is where a double stops being able to name every integer, and 2^53+1 is
# the first integer it cannot.
#
# NOTE on 2**53 as a Perl literal: `2**53` is an NV in Perl and reaches the
# backend as "9.00719925474099e+15", which is not a valid i64 literal and dies
# in lli. The integer literals below avoid that -- it is a probe artifact, not
# a backend finding.
my %PROBE_VALUES = (
    Int     => [ ['0',      0,                'number'],
                 ['1',      1,                'number'],
                 ['-1',     -1,               'number'],
                 ['2^31',   2147483648,       'number'],
                 ['2^53',   9007199254740992, 'number'],
                 ['2^53+1', 9007199254740993, 'number'],
                 ['big15',  123456789012345,  'number'] ],
    Num     => [ ['0.0',    0,    'number'],
                 ['1.5',    1.5,  'number'],
                 ['-1.5',   -1.5, 'number'] ],
    Str     => [ ['"0"',    '0',    'string'],
                 ['"42"',   '42',   'string'],
                 ['"abc"',  'abc',  'string'],   # non-numeric, per the brief
                 ['"3.9x"', '3.9x', 'string'],
                 ['""',     '',     'string'] ],
    Boolean => [ ['1', 1, 'number'], ['0', 0, 'number'] ],
    Undef   => [ ['undef', 0, 'number'] ],
);

# The source category. Scalar and Slot are NOT here: no Constant can be built
# at those reprs (Context.pm:1675/1801 refuse), and the return epilogue cannot
# print one (LLVM.pm:1259). Both are limits of THIS HARNESS, not missing
# arrows -- _emit_coercion has live Scalar/Slot arms reached from field and
# element access. Composition through Slot needs a different probe shape.
my @REPRS = qw(Int Num Str Boolean Undef);

# ---------------------------------------------------------------------------
# THE RECORDED TABLE. Key: "A->B->C|value" => verdict.
# Measured under lli 15 on 2026-08-31. Rows absent from this table are triples
# where a route did not lower or lli rejected it; they are skipped, not passed.
# ---------------------------------------------------------------------------
my %RECORDED = (
    # ---- Int source ----------------------------------------------------
    # Int->Num->Str: THE MISCOMPILE (kind 2). Num |-> double forces a sitofp;
    # a double's 53-bit mantissa cannot name 2^53+1, so it rounds to 2^53 and
    # %.15g then renders it in exponent form. 2^53 itself IS representable but
    # still differs, because at that magnitude %.15g needs 16 digits to print
    # it positionally and falls back to exponent form -- so the two arms
    # disagree in FORMAT there, and in VALUE at 2^53+1.
    'Int->Num->Str|0'      => 'AGREE',
    'Int->Num->Str|1'      => 'AGREE',
    'Int->Num->Str|-1'     => 'AGREE',
    'Int->Num->Str|2^31'   => 'AGREE',
    'Int->Num->Str|2^53'   => 'DIFFER',
    'Int->Num->Str|2^53+1' => 'DIFFER',
    'Int->Num->Str|big15'  => 'AGREE',   # 15 digits: exactly what %.15g holds

    'Int->Num->Boolean|0'      => 'AGREE',
    'Int->Num->Boolean|1'      => 'AGREE',
    'Int->Num->Boolean|-1'     => 'AGREE',
    'Int->Num->Boolean|2^31'   => 'AGREE',
    'Int->Num->Boolean|2^53'   => 'AGREE',
    'Int->Num->Boolean|2^53+1' => 'AGREE',
    'Int->Num->Boolean|big15'  => 'AGREE',

    # Int->Str->* round-trips cleanly: the decimal face is exact for an i64,
    # so nothing is lost on the way through. This is the CONTROL for the
    # Int->Num->Str rows above -- same source, same target, lossless
    # intermediate, and it agrees at every probe value including 2^53+1.
    'Int->Str->Num|0'      => 'AGREE',
    'Int->Str->Num|1'      => 'AGREE',
    'Int->Str->Num|-1'     => 'AGREE',
    'Int->Str->Num|2^31'   => 'AGREE',
    'Int->Str->Num|2^53'   => 'AGREE',
    'Int->Str->Num|2^53+1' => 'AGREE',
    'Int->Str->Num|big15'  => 'AGREE',

    'Int->Str->Boolean|0'      => 'AGREE',
    'Int->Str->Boolean|1'      => 'AGREE',
    'Int->Str->Boolean|-1'     => 'AGREE',
    'Int->Str->Boolean|2^31'   => 'AGREE',
    'Int->Str->Boolean|2^53'   => 'AGREE',
    'Int->Str->Boolean|2^53+1' => 'AGREE',
    'Int->Str->Boolean|big15'  => 'AGREE',

    # Int->Boolean->*: LOSSY BY DESIGN (kind 1). Boolean keeps one bit, so
    # every nonzero collapses to 1. Perl agrees: `!!42 + 0` is 1, not 42.
    # AGREE at 0 and 1 only because those values ARE their own truthiness.
    'Int->Boolean->Num|0'      => 'AGREE',
    'Int->Boolean->Num|1'      => 'AGREE',
    'Int->Boolean->Num|-1'     => 'DIFFER',
    'Int->Boolean->Num|2^31'   => 'DIFFER',
    'Int->Boolean->Num|2^53'   => 'DIFFER',
    'Int->Boolean->Num|2^53+1' => 'DIFFER',
    'Int->Boolean->Num|big15'  => 'DIFFER',

    # The 0 row differs for a second reason on top of the collapse: Boolean's
    # string face is "" for false, while Int's is "0". Both match perl
    # (`!!0 . ""` is "", `0 . ""` is "0").
    'Int->Boolean->Str|0'      => 'DIFFER',
    'Int->Boolean->Str|1'      => 'AGREE',
    'Int->Boolean->Str|-1'     => 'DIFFER',
    'Int->Boolean->Str|2^31'   => 'DIFFER',
    'Int->Boolean->Str|2^53'   => 'DIFFER',
    'Int->Boolean->Str|2^53+1' => 'DIFFER',
    'Int->Boolean->Str|big15'  => 'DIFFER',

    # ---- Num source ----------------------------------------------------
    # Num->Int->Str: LOSSY BY DESIGN. Int truncates toward zero, so 1.5 -> 1.
    # Perl agrees (`int(1.5)` is 1).
    'Num->Int->Str|0.0'  => 'AGREE',
    'Num->Int->Str|1.5'  => 'DIFFER',
    'Num->Int->Str|-1.5' => 'DIFFER',

    # Truthiness survives truncation for these probes -- but NOT in general:
    # 0.5 would truncate to 0 and flip true to false. Not a recorded probe
    # value; noted so the AGREE here is not read as a guarantee.
    'Num->Int->Boolean|0.0'  => 'AGREE',
    'Num->Int->Boolean|1.5'  => 'AGREE',
    'Num->Int->Boolean|-1.5' => 'AGREE',

    'Num->Str->Int|0.0'      => 'AGREE',
    'Num->Str->Int|1.5'      => 'AGREE',
    'Num->Str->Int|-1.5'     => 'AGREE',
    'Num->Str->Boolean|0.0'  => 'AGREE',
    'Num->Str->Boolean|1.5'  => 'AGREE',
    'Num->Str->Boolean|-1.5' => 'AGREE',

    # Num->Boolean->*: LOSSY BY DESIGN, same as Int->Boolean->*.
    'Num->Boolean->Int|0.0'  => 'AGREE',
    'Num->Boolean->Int|1.5'  => 'AGREE',   # int(1.5)==1 == !!1.5
    'Num->Boolean->Int|-1.5' => 'DIFFER',
    'Num->Boolean->Str|0.0'  => 'DIFFER',  # "" vs "0"
    'Num->Boolean->Str|1.5'  => 'DIFFER',
    'Num->Boolean->Str|-1.5' => 'DIFFER',

    # ---- Str source ----------------------------------------------------
    # Str->Int->Num on "3.9x": LOSSY BY DESIGN. The direct Str->Num keeps the
    # leading-numeric 3.9; routing through Int truncates it to 3 first.
    'Str->Int->Num|"0"'    => 'AGREE',
    'Str->Int->Num|"42"'   => 'AGREE',
    'Str->Int->Num|"abc"'  => 'AGREE',   # both routes yield 0
    'Str->Int->Num|"3.9x"' => 'DIFFER',
    'Str->Int->Num|""'     => 'AGREE',

    # "abc": the direct Str->Boolean is TRUE (perl: a non-empty, non-"0"
    # string is true), but routing through a numeric intermediate parses it as
    # 0 and yields FALSE. Perl agrees with BOTH -- `!!"abc"` is 1 while
    # `!!("abc"+0)` is "" -- so this is a real semantic fork, not a defect.
    'Str->Int->Boolean|"0"'    => 'AGREE',
    'Str->Int->Boolean|"42"'   => 'AGREE',
    'Str->Int->Boolean|"abc"'  => 'DIFFER',
    'Str->Int->Boolean|"3.9x"' => 'AGREE',
    'Str->Int->Boolean|""'     => 'AGREE',

    'Str->Num->Int|"0"'    => 'AGREE',
    'Str->Num->Int|"42"'   => 'AGREE',
    'Str->Num->Int|"abc"'  => 'AGREE',
    'Str->Num->Int|"3.9x"' => 'AGREE',
    'Str->Num->Int|""'     => 'AGREE',

    'Str->Num->Boolean|"0"'    => 'AGREE',
    'Str->Num->Boolean|"42"'   => 'AGREE',
    'Str->Num->Boolean|"abc"'  => 'DIFFER',   # same fork as Str->Int->Boolean
    'Str->Num->Boolean|"3.9x"' => 'AGREE',
    'Str->Num->Boolean|""'     => 'AGREE',

    # Str->Boolean->*: LOSSY BY DESIGN. "42" collapses to 1.
    'Str->Boolean->Int|"0"'    => 'AGREE',
    'Str->Boolean->Int|"42"'   => 'DIFFER',
    'Str->Boolean->Int|"abc"'  => 'DIFFER',   # direct 0, via-Boolean 1
    'Str->Boolean->Int|"3.9x"' => 'DIFFER',
    'Str->Boolean->Int|""'     => 'AGREE',

    'Str->Boolean->Num|"0"'    => 'AGREE',
    'Str->Boolean->Num|"42"'   => 'DIFFER',
    'Str->Boolean->Num|"abc"'  => 'DIFFER',
    'Str->Boolean->Num|"3.9x"' => 'DIFFER',
    'Str->Boolean->Num|""'     => 'AGREE',

    # ---- Boolean source ------------------------------------------------
    # Boolean's own string face is ""/"1", but routing through a numeric
    # intermediate gives "0"/"1". Perl agrees with both faces in their own
    # context; the false row is where they part.
    'Boolean->Int->Num|1' => 'AGREE',
    'Boolean->Int->Num|0' => 'AGREE',
    'Boolean->Int->Str|1' => 'AGREE',
    'Boolean->Int->Str|0' => 'DIFFER',   # "" (direct) vs "0" (via Int)
    'Boolean->Num->Int|1' => 'AGREE',
    'Boolean->Num->Int|0' => 'AGREE',
    'Boolean->Num->Str|1' => 'AGREE',
    'Boolean->Num->Str|0' => 'DIFFER',   # same ""/"0" split
    'Boolean->Str->Int|1' => 'AGREE',
    'Boolean->Str->Int|0' => 'AGREE',
    'Boolean->Str->Num|1' => 'AGREE',
    'Boolean->Str->Num|0' => 'AGREE',

    # ---- Undef source --------------------------------------------------
    # Undef->*->Str: the ""/"0" split again. Direct Undef->Str is "" (perl:
    # `undef . ""` is ""); via a numeric intermediate undef becomes 0 first
    # and stringifies as "0". Both halves match perl for their own route.
    'Undef->Int->Num|undef'  => 'AGREE',
    'Undef->Int->Str|undef'  => 'DIFFER',
    'Undef->Num->Int|undef'  => 'AGREE',
    'Undef->Num->Str|undef'  => 'DIFFER',
    'Undef->Str->Int|undef'  => 'AGREE',
    'Undef->Str->Num|undef'  => 'AGREE',

    # !!!! KIND (3): AN OUTRIGHT INVERSION -- FOUND HERE, NOW FIXED !!!!
    #
    # Every one of the five rows below differs, and unlike every other DIFFER
    # in this table the COMPOSED route is the CORRECT one. The direct
    # Undef->Boolean arm emits:
    #
    #     %r = icmp ne i1 false, true      ; Coerce[Undef->Boolean] = false
    #
    # which computes (false != true) = TRUE. Its own trailing comment says the
    # answer must be `false`, and perl is unambiguous that undef is false.
    # The instruction contradicts the comment beside it.
    #
    # Confirmed three ways: Undef->Int->Boolean, Undef->Num->Boolean and
    # Undef->Str->Boolean ALL independently produce false (correct), while the
    # direct arm alone produces 1. Three agreeing witnesses against one
    # outlier. Perl oracle on 5.42:
    #     my $u; print(($u ? 1 : 0));            -> 0
    #     my $u; print((($u . "") ? 1 : 0));     -> 0
    #
    # FIXED 2026-08-31 at Context.pm:2579: the arm now emits `add i1 0, 0`,
    # the constant false, matching how Constant(Boolean) is emitted elsewhere.
    # All six rows flipped DIFFER -> AGREE and this test went RED until this
    # table was updated -- which is exactly the acknowledgement the design
    # intends, and the reason it records reality rather than asserting an
    # ideal. The characterization caught its own fix.
    'Undef->Int->Boolean|undef'  => 'AGREE' ,
    'Undef->Num->Boolean|undef'  => 'AGREE' ,
    'Undef->Str->Boolean|undef'  => 'AGREE' ,
    'Undef->Boolean->Int|undef'  => 'AGREE' ,
    'Undef->Boolean->Num|undef'  => 'AGREE' ,
    'Undef->Boolean->Str|undef'  => 'AGREE' ,
);

# ---------------------------------------------------------------------------

my @measured;   # [$key, $verdict, $direct, $composed]

for my $a (@REPRS) {
    for my $b (@REPRS) {
        next if $b eq $a;
        for my $c (@REPRS) {
            next if $c eq $b || $c eq $a;
            for my $probe ($PROBE_VALUES{$a}->@*) {
                my ($label, $val, $const_type) = $probe->@*;

                my $direct = emit_route($val, $const_type, $a, $c);
                next if $direct eq 'LOWER-FAIL' || $direct eq 'LLI-FAIL';
                my $composed = emit_route($val, $const_type, $a, $b, $c);
                next if $composed eq 'LOWER-FAIL' || $composed eq 'LLI-FAIL';

                push @measured, [
                    "$a->$b->$c|$label",
                    ($direct eq $composed ? 'AGREE' : 'DIFFER'),
                    $direct, $composed,
                ];
            }
        }
    }
}

subtest 'every measured triple matches its recorded verdict' => sub {
    plan tests => scalar @measured;
    for my $m (@measured) {
        my ($key, $verdict, $direct, $composed) = $m->@*;
        my $expected = $RECORDED{$key};
        if (!defined $expected) {
            fail("$key: NOT IN THE RECORDED TABLE (measured $verdict) — "
               . "a new route now lowers; add it with its verdict");
            next;
        }
        is($verdict, $expected,
           "$key: $verdict (direct='$direct' composed='$composed')");
    }
};

# The table must not rot: an entry naming a triple that no longer lowers is a
# stale exemption, and a stale exemption hides the finding it drifts onto.
subtest 'the recorded table has no stale rows' => sub {
    my %seen = map { $_->[0] => 1 } @measured;
    my @stale = sort grep { !$seen{$_} } keys %RECORDED;
    plan tests => 1;
    is_deeply(\@stale, [],
        'every recorded row corresponds to a route that still lowers')
        or diag("stale rows: @stale");
};

# The law is not vacuous: if NOTHING differed, this file would be asserting an
# ideal rather than recording reality, and the miscompile it exists to pin
# would have gone silent. Guard both directions.
subtest 'the characterization is non-vacuous' => sub {
    plan tests => 3;
    my $differ = grep { $_->[1] eq 'DIFFER' } @measured;
    my $agree  = grep { $_->[1] eq 'AGREE'  } @measured;
    ok($differ > 0, "at least one triple DIFFERs (measured $differ)");
    ok($agree  > 0, "at least one triple AGREEs (measured $agree)");

    # The specific miscompile this file was written for. If this ever starts
    # agreeing, Num stopped forcing a double and that is worth a red test.
    my ($row) = grep { $_->[0] eq 'Int->Num->Str|2^53+1' } @measured;
    is(($row ? $row->[1] : 'MISSING'), 'DIFFER',
       'Int->Num->Str at 2^53+1 still differs (sitofp precision loss)');
};

done_testing;

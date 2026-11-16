# ABOUTME: Pins the canonical type-tag contract in Chalk::CodeGen::Harness::TypeTag.
# ABOUTME: infer_tag (declared values) and tag_live_value (live values) rules, one site each.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';
use Scalar::Util qw(looks_like_number);
use builtin      qw(is_bool);
no warnings 'experimental::builtin';

binmode STDOUT, ':utf8';
binmode STDERR, ':utf8';

use Chalk::CodeGen::Harness::TypeTag;


# ---------------------------------------------------------------------------
# SECTION 1 -- infer_tag canonical rules (declared-string tagging)
# ---------------------------------------------------------------------------
#
# infer_tag() is for DECLARED values in behavior blocks (is_bool not available).
# The rules: already-tagged pass through; undef -> Undef:; "" -> Str: (not Bool:);
# numeric-with-dot -> Num:%g; numeric -> Int:; else -> Str:.
# ---------------------------------------------------------------------------

subtest 'infer_tag: undef -> Undef:' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag(undef), 'Undef:', 'undef tags as Undef:' );
};

subtest 'infer_tag: empty string -> Str: (not Bool:false)' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag(''), 'Str:', 'empty string tags as Str:' );
};

subtest 'infer_tag: Bool:1 (already tagged) -> passthrough' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('Bool:1'), 'Bool:1', 'Bool:1 passes through' );
};

subtest 'infer_tag: Bool: (already tagged) -> passthrough' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('Bool:'), 'Bool:', 'Bool: passes through' );
};

subtest 'infer_tag: Int:5 (already tagged) -> passthrough' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('Int:5'), 'Int:5', 'Int:5 passes through' );
};

subtest 'infer_tag: Num:3.14 (already tagged) -> passthrough' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('Num:3.14'), 'Num:3.14', 'Num:3.14 passes through' );
};

subtest 'infer_tag: Str:hello (already tagged) -> passthrough' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('Str:hello'), 'Str:hello', 'Str:hello passes through' );
};

subtest 'infer_tag: Undef: (already tagged) -> passthrough' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('Undef:'), 'Undef:', 'Undef: passes through' );
};

subtest 'infer_tag: plain integer -> Int:' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('0'),   'Int:0',  'plain 0 gives Int:0' );
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('5'),   'Int:5',  'plain 5 gives Int:5' );
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('-3'),  'Int:-3', 'negative integer gives Int:-3' );
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('42'),  'Int:42', '42 gives Int:42' );
};

subtest 'infer_tag: float with decimal -> Num:%g' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('3.14'), 'Num:3.14', '3.14 gives Num:3.14' );
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('0.5'),  'Num:0.5',  '0.5 gives Num:0.5' );
    # %g formatting: integer-valued float like "1.0" -- trailing zero stripped by %g
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('1.0'),
        sprintf('Num:%g', '1.0'), 'integer-valued float 1.0 gives Num:%g (trailing zero stripped)' );
};

subtest 'infer_tag: plain string -> Str:' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('hello'),  'Str:hello',  'plain word gives Str:hello' );
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('3abc'),   'Str:3abc',   'digit-prefix string gives Str:3abc' );
    # A string that happens to contain a colon -- not already-tagged form
    is( Chalk::CodeGen::Harness::TypeTag::infer_tag('a:b'),    'Str:a:b',    'string with colon gives Str:a:b' );
};

# ---------------------------------------------------------------------------
# SECTION 2 -- tag_live_value canonical rules (live Perl value tagging)
# ---------------------------------------------------------------------------
#
# tag_live_value() is for LIVE Perl values (is_bool available). Uses is_bool,
# then defined, then looks_like_number with decimal, then looks_like_number,
# then Str fallback.
# ---------------------------------------------------------------------------

subtest 'tag_live_value: Boolean true -> Bool:1' => sub {
    my $true_val = 1 == 1;    # bool-typed true
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value($true_val), 'Bool:1', 'bool-true gives Bool:1' );
};

subtest 'tag_live_value: Boolean false -> Bool:' => sub {
    my $false_val = 1 == 2;    # bool-typed false
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value($false_val), 'Bool:', 'bool-false gives Bool:' );
};

subtest 'tag_live_value: undef -> Undef:' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(undef), 'Undef:', 'undef gives Undef:' );
};

subtest 'tag_live_value: float -> Num:' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(3.14), 'Num:3.14', '3.14 gives Num:3.14' );
};

subtest 'tag_live_value: integer -> Int:' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(5),  'Int:5',  '5 gives Int:5' );
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(0),  'Int:0',  '0 gives Int:0' );
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(-3), 'Int:-3', '-3 gives Int:-3' );
};

subtest 'tag_live_value: string -> Str:' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value('hello'), 'Str:hello', '"hello" gives Str:hello' );
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(''),      'Str:',      '"" gives Str:' );
};

# ---------------------------------------------------------------------------
# Non-finite numerics: Inf/-Inf/NaN must tag as Num: with perl-style face
#
# perl prints Inf/NaN/-Inf (capitalized), not C's inf/nan. A non-finite
# numeric is NOT Int: (no decimal point but looks_like_number is true) and
# NOT Num:inf (wrong case). The canonical tag is Num:Inf / Num:-Inf / Num:NaN.
# ---------------------------------------------------------------------------

subtest 'tag_live_value: +Inf -> Num:Inf' => sub {
    my $inf = 0 + 'inf';
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value($inf), 'Num:Inf', '+Inf tags as Num:Inf' );
};

subtest 'tag_live_value: -Inf -> Num:-Inf' => sub {
    my $ninf = 0 + '-inf';
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value($ninf), 'Num:-Inf', '-Inf tags as Num:-Inf' );
};

subtest 'tag_live_value: NaN -> Num:NaN' => sub {
    my $nan = 0 + 'nan';
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value($nan), 'Num:NaN', 'NaN tags as Num:NaN' );
};

subtest 'tag_live_value: finite values unchanged after non-finite fix' => sub {
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(3),    'Int:3',    'finite int 3 still Int:3' );
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(0),    'Int:0',    'finite int 0 still Int:0' );
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value(3.14), 'Num:3.14', 'finite float still Num:3.14' );
};

# ---------------------------------------------------------------------------
# SECTIONS 3 AND 4: REMOVED -- they pinned the return-value type-tag epilogue,
# which a9adbfe7 deleted on purpose.
#
# Section 3 pinned TypeTag::llvm_prefixes against "the LLVM.pm hard-coded
# strings" -- the epilogue's printf formats (`Int:%lld\n`, `Bool:1\n`, ...).
# Those constants no longer exist in the backend, so the table pinned nothing
# but itself, and it is gone with them.
#
# Section 4 lowered a bare `return 1 + 2` (and Num/Boolean siblings), ran it
# under lli, and read the tagged value back off stdout. That IS the epilogue:
# a program has no channel that hands its return value to a harness, and since
# a9adbfe7 such a graph correctly prints nothing. A program's value is observed
# by printing it, which the llvm-* tests do (Print(Coerce(value -> Str))), the
# same conversion llvm-undef-defined-or.t made for its U4/U5.
#
# ---------------------------------------------------------------------------
# SECTION 5 -- infer_tag has one site
# ---------------------------------------------------------------------------
#
# This section used to compare MdtestCorpus::_infer_tag against
# TypeTag::infer_tag. cdefd9f8 deleted _infer_tag on purpose (the corpus runs
# cases as programs and asserts stdout, so it no longer tags a declared
# return value), leaving TypeTag::infer_tag the only site. The representative
# inputs stay pinned against it.
# ---------------------------------------------------------------------------

subtest 'infer_tag: representative inputs' => sub {
    my @cases = (
        [ undef,    'Undef:',   'undef'             ],
        [ '',       'Str:',     'empty string'      ],
        [ '0',      'Int:0',    'zero'              ],
        [ '5',      'Int:5',    'integer 5'         ],
        [ '-3',     'Int:-3',   'negative integer'  ],
        [ '3.14',   'Num:3.14', 'float 3.14'        ],
        [ 'Bool:1', 'Bool:1',   'pre-tagged Bool:1' ],
        [ 'Bool:',  'Bool:',    'pre-tagged Bool:'  ],
        [ 'hello',  'Str:hello','plain string'      ],
        [ '3abc',   'Str:3abc', 'digit-prefix str'  ],
        [ 'Int:5',  'Int:5',    'pre-tagged Int:5'  ],
        [ 'Num:3',  'Num:3',    'pre-tagged Num:3'  ],
        [ 'Undef:', 'Undef:',   'pre-tagged Undef:' ],
    );

    for my $case (@cases) {
        my ($input, $expected, $label) = $case->@*;
        my $display = defined $input ? "'$input'" : 'undef';
        is( Chalk::CodeGen::Harness::TypeTag::infer_tag($input), $expected,
            "TypeTag::infer_tag($display) == '$expected' ($label)" );
    }
};

done_testing;

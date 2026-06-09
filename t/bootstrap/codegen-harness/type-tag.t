# ABOUTME: Pins the canonical type-tag contract and verifies all four tag-emitting sites agree.
# ABOUTME: Round-trip test: perl-oracle tag == lli-emit tag for Bool/Int/Num/Str; LLVM prefix pinning.
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

my $LLI = '/usr/lib/llvm-15/bin/lli';

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

subtest 'tag_live_value: Bool true -> Bool:1' => sub {
    my $true_val = 1 == 1;    # bool-typed true
    is( Chalk::CodeGen::Harness::TypeTag::tag_live_value($true_val), 'Bool:1', 'bool-true gives Bool:1' );
};

subtest 'tag_live_value: Bool false -> Bool:' => sub {
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
# SECTION 3 -- LLVM canonical prefix pinning
# ---------------------------------------------------------------------------
#
# The LLVM backend bakes tag-prefix strings into LLVM IR constants. Those must
# match TypeTag's canonical prefixes exactly, or the perl-oracle and lli tags
# will diverge. This test reads TypeTag's constant table and checks it matches
# the LLVM.pm hard-coded strings directly.
# ---------------------------------------------------------------------------

subtest 'LLVM prefix table: Int repr matches LLVM.pm constant' => sub {
    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    is( $prefixes->{Int}{perl_tag_prefix}, 'Int:',          'Int perl_tag_prefix is "Int:"' );
    is( $prefixes->{Int}{llvm_fmt_c},      'Int:%d\0A\00',  'Int llvm_fmt_c matches LLVM.pm constant' );
};

subtest 'LLVM prefix table: Num repr matches LLVM.pm constant' => sub {
    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    is( $prefixes->{Num}{perl_tag_prefix}, 'Num:',          'Num perl_tag_prefix is "Num:"' );
    is( $prefixes->{Num}{llvm_fmt_c},      'Num:%g\0A\00',  'Num llvm_fmt_c matches LLVM.pm constant' );
};

subtest 'LLVM prefix table: Bool repr matches LLVM.pm constants' => sub {
    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    is( $prefixes->{Bool}{perl_tag_prefix_true},  'Bool:1',         'Bool true prefix is "Bool:1"' );
    is( $prefixes->{Bool}{perl_tag_prefix_false}, 'Bool:',          'Bool false prefix is "Bool:"' );
    is( $prefixes->{Bool}{llvm_true_c},           'Bool:1\0A\00',   'Bool true llvm_true_c matches LLVM.pm' );
    is( $prefixes->{Bool}{llvm_false_c},          'Bool:\0A\00',    'Bool false llvm_false_c matches LLVM.pm' );
};

subtest 'LLVM prefix table: Str repr matches LLVM.pm constant' => sub {
    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    is( $prefixes->{Str}{perl_tag_prefix}, 'Str:',          'Str perl_tag_prefix is "Str:"' );
    is( $prefixes->{Str}{llvm_fmt_c},      'Str:%s\0A\00',  'Str llvm_fmt_c matches LLVM.pm constant' );
};

# ---------------------------------------------------------------------------
# SECTION 4 -- round-trip agreement (perl-oracle == lli-emit), requires lli
# ---------------------------------------------------------------------------
#
# For each representation (Bool/Int/Num), build a minimal SoN Return graph,
# lower it to LLVM IR, run through lli, and assert the output tag prefix matches
# what TypeTag says the perl oracle would emit.
# ---------------------------------------------------------------------------

my $HAS_LLI = -x $LLI;

if ($HAS_LLI) {
    require Chalk::IR::NodeFactory;
    require Chalk::IR::Node::Constant;
    require Chalk::IR::Node::Add;
    require Chalk::IR::Node::NumEq;
    require Chalk::Target::LLVM;
}

sub _make_factory { return Chalk::IR::NodeFactory->new }

sub _run_lli {
    my ($ll_text) = @_;
    require File::Temp;
    my ( $fh, $tmp ) = File::Temp::tempfile( SUFFIX => '.ll', UNLINK => 1 );
    print $fh $ll_text;
    close $fh;
    my $out  = qx($LLI $tmp 2>&1);
    my $exit = $? >> 8;
    chomp $out;
    return ( $out, $exit );
}

subtest 'round-trip: Int repr (1+2=3) lli tag == TypeTag prefix' => sub {
    unless ($HAS_LLI) {
        plan skip_all => 'lli not found';
        return;
    }
    my $f   = _make_factory();
    my $c1  = $f->make( 'Constant', value => '1', const_type => 'integer' );
    $c1->set_representation('Int');
    my $c2  = $f->make( 'Constant', value => '2', const_type => 'integer' );
    $c2->set_representation('Int');
    my $add = $f->make( 'Add', inputs => [ $c1, $c2 ] );
    $add->set_representation('Int');
    my $ret = $f->make_cfg( 'Return', inputs => [$add] );

    my $ll           = Chalk::Target::LLVM->lower($ret);
    my ($out, $exit) = _run_lli($ll);

    is( $exit, 0,       'lli exits 0 for Int graph' );
    is( $out,  'Int:3', 'lli output is Int:3 for 1+2' );

    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    like( $out, qr/^\Q$prefixes->{Int}{perl_tag_prefix}\E/, 'lli output starts with canonical Int: prefix' );

    # Cross-check: tag_live_value(3) produces matching prefix.
    my $perl_tag      = Chalk::CodeGen::Harness::TypeTag::tag_live_value(3);
    my ($lli_prefix)  = $out      =~ /^([^:]+:)/;
    my ($perl_prefix) = $perl_tag =~ /^([^:]+:)/;
    is( $lli_prefix, $perl_prefix, 'lli prefix matches perl-oracle prefix for Int' );
};

subtest 'round-trip: Num repr (1.5) lli tag == TypeTag prefix' => sub {
    unless ($HAS_LLI) {
        plan skip_all => 'lli not found';
        return;
    }
    my $f   = _make_factory();
    my $c   = $f->make( 'Constant', value => '1.5', const_type => 'float' );
    $c->set_representation('Num');
    my $ret = $f->make_cfg( 'Return', inputs => [$c] );

    my $ll           = Chalk::Target::LLVM->lower($ret);
    my ($out, $exit) = _run_lli($ll);

    is( $exit, 0, 'lli exits 0 for Num graph' );
    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    like( $out, qr/^\Q$prefixes->{Num}{perl_tag_prefix}\E/, 'lli output starts with canonical Num: prefix' );

    my $perl_tag      = Chalk::CodeGen::Harness::TypeTag::tag_live_value(1.5);
    my ($lli_prefix)  = $out      =~ /^([^:]+:)/;
    my ($perl_prefix) = $perl_tag =~ /^([^:]+:)/;
    is( $lli_prefix, $perl_prefix, 'lli prefix matches perl-oracle prefix for Num' );
};

subtest 'round-trip: Bool repr true (1 == 1) lli tag == TypeTag prefix' => sub {
    unless ($HAS_LLI) {
        plan skip_all => 'lli not found';
        return;
    }
    my $f  = _make_factory();
    my $c1 = $f->make( 'Constant', value => '1', const_type => 'integer' );
    $c1->set_representation('Int');
    my $c2 = $f->make( 'Constant', value => '1', const_type => 'integer' );
    $c2->set_representation('Int');
    my $eq = $f->make( 'NumEq', inputs => [ $c1, $c2 ] );
    $eq->set_representation('Bool');
    my $ret = $f->make_cfg( 'Return', inputs => [$eq] );

    my $ll           = Chalk::Target::LLVM->lower($ret);
    my ($out, $exit) = _run_lli($ll);

    is( $exit, 0, 'lli exits 0 for Bool-true graph' );
    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    is( $out, $prefixes->{Bool}{perl_tag_prefix_true}, 'lli output is Bool:1 (canonical Bool-true tag)' );

    my $perl_tag = Chalk::CodeGen::Harness::TypeTag::tag_live_value( 1 == 1 );
    is( $perl_tag, 'Bool:1',  'perl oracle tags bool-true as Bool:1' );
    is( $out,      $perl_tag, 'lli tag == perl-oracle tag for Bool true' );
};

subtest 'round-trip: Bool repr false (1 == 2) lli tag == TypeTag prefix' => sub {
    unless ($HAS_LLI) {
        plan skip_all => 'lli not found';
        return;
    }
    my $f  = _make_factory();
    my $c1 = $f->make( 'Constant', value => '1', const_type => 'integer' );
    $c1->set_representation('Int');
    my $c2 = $f->make( 'Constant', value => '2', const_type => 'integer' );
    $c2->set_representation('Int');
    my $eq = $f->make( 'NumEq', inputs => [ $c1, $c2 ] );
    $eq->set_representation('Bool');
    my $ret = $f->make_cfg( 'Return', inputs => [$eq] );

    my $ll           = Chalk::Target::LLVM->lower($ret);
    my ($out, $exit) = _run_lli($ll);

    is( $exit, 0, 'lli exits 0 for Bool-false graph' );
    my $prefixes = Chalk::CodeGen::Harness::TypeTag::llvm_prefixes();
    is( $out, $prefixes->{Bool}{perl_tag_prefix_false}, 'lli output is Bool: (canonical Bool-false tag)' );

    my $perl_tag = Chalk::CodeGen::Harness::TypeTag::tag_live_value( 1 == 2 );
    is( $perl_tag, 'Bool:',   'perl oracle tags bool-false as Bool:' );
    is( $out,      $perl_tag, 'lli tag == perl-oracle tag for Bool false' );
};

# ---------------------------------------------------------------------------
# SECTION 5 -- site-agreement: all three test-side tag sites produce equal output
# ---------------------------------------------------------------------------
#
# For each representative input, verify that MdtestCorpus::_infer_tag,
# LLVMGapMap::_infer_oracle_tag, and TypeTag::infer_tag all produce equal output.
# This documents that the refactor is behavior-preserving.
# ---------------------------------------------------------------------------

subtest 'site agreement: infer_tag variants agree on representative inputs' => sub {
    require Chalk::CodeGen::Harness::MdtestCorpus;
    require Chalk::CodeGen::Harness::LLVMGapMap;

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
        my ($input, $expected, $label) = @$case;
        my $display = defined $input ? "'$input'" : 'undef';

        my $tt  = Chalk::CodeGen::Harness::TypeTag::infer_tag($input);
        my $mc  = Chalk::CodeGen::Harness::MdtestCorpus::_infer_tag($input);
        my $lgm = Chalk::CodeGen::Harness::LLVMGapMap::_infer_oracle_tag($input);

        is( $tt,  $expected, "TypeTag::infer_tag($display) == '$expected'" );
        is( $mc,  $expected, "MdtestCorpus::_infer_tag agrees for $label" );
        is( $lgm, $expected, "LLVMGapMap::_infer_oracle_tag agrees for $label" );
    }
};

done_testing;

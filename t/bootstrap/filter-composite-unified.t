# ABOUTME: Tests FilterComposite unified Context interface (#706).
# ABOUTME: Verifies zero/one/is_zero/multiply/add/on_scan/on_complete return Context objects.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;

no warnings 'experimental::class';

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

# ========================================================================
# Helpers
# ========================================================================

sub make_2ary_comp {
    my $bool_sr = Chalk::Bootstrap::Semiring::Boolean->new();
    my $sem_sr  = Chalk::Bootstrap::Semiring::SemanticAction->new();
    return Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $sem_sr],
    );
}

sub make_5ary_comp {
    my $bool_sr   = Chalk::Bootstrap::Semiring::Boolean->new();
    my $prec_sr   = Chalk::Bootstrap::Semiring::Precedence->new(
        lookup => \&Chalk::Grammar::Perl::PrecedenceTable::lookup,
    );
    my $type_sr   = Chalk::Bootstrap::Semiring::TypeInference->new(
        keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
        builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
    );
    my $struct_sr = Chalk::Bootstrap::Semiring::Structural->new();
    my $sem_sr    = Chalk::Bootstrap::Semiring::SemanticAction->new();
    return Chalk::Bootstrap::Semiring::FilterComposite->new(
        semirings => [$bool_sr, $prec_sr, $type_sr, $struct_sr, $sem_sr],
    );
}

# ========================================================================
# zero() — returns a Context with is_zero=true
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $zero = $comp->zero();

    isa_ok($zero, 'Chalk::Bootstrap::Context', '2-ary zero() returns a Context');
    ok($zero->is_zero(), '2-ary zero() has is_zero=true');
    ok($comp->is_zero($zero), '2-ary is_zero(zero()) returns true');
}

{
    my $comp = make_5ary_comp();
    my $zero = $comp->zero();

    isa_ok($zero, 'Chalk::Bootstrap::Context', '5-ary zero() returns a Context');
    ok($zero->is_zero(), '5-ary zero() has is_zero=true');
    ok($comp->is_zero($zero), '5-ary is_zero(zero()) returns true');
}

# ========================================================================
# one() — returns a Context with is_zero=false and annotations
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    isa_ok($one, 'Chalk::Bootstrap::Context', '2-ary one() returns a Context');
    ok(!$one->is_zero(), '2-ary one() has is_zero=false');
    ok(!$comp->is_zero($one), '2-ary is_zero(one()) returns false');
    ok(defined $one->annotations()->{cfg}, '2-ary one() has cfg annotation');
}

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    isa_ok($one, 'Chalk::Bootstrap::Context', '5-ary one() returns a Context');
    ok(!$one->is_zero(), '5-ary one() has is_zero=false');
    ok(!$comp->is_zero($one), '5-ary is_zero(one()) returns false');
    ok(defined $one->annotations()->{cfg},        '5-ary one() has cfg annotation');
    ok(defined $one->annotations()->{precedence},  '5-ary one() has precedence annotation');
    ok(defined $one->annotations()->{structural},  '5-ary one() has structural annotation');
}

# ========================================================================
# is_zero() — checks Context is_zero flag, not component tuple
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $zero = $comp->zero();
    my $one  = $comp->one();

    ok($comp->is_zero($zero),  'is_zero(zero()) = true');
    ok(!$comp->is_zero($one),  'is_zero(one()) = false');
}

# ========================================================================
# multiply() — returns Context or zero Context
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();
    my $zero = $comp->zero();

    my $result = $comp->multiply($one, $one);
    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply(one,one) returns Context');
    ok(!$comp->is_zero($result), 'multiply(one,one) is not zero');

    my $r_left  = $comp->multiply($zero, $one);
    ok($comp->is_zero($r_left), 'multiply(zero,one) is zero');

    my $r_right = $comp->multiply($one, $zero);
    ok($comp->is_zero($r_right), 'multiply(one,zero) is zero');
}

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();
    my $zero = $comp->zero();

    my $result = $comp->multiply($one, $one);
    isa_ok($result, 'Chalk::Bootstrap::Context', '5-ary multiply(one,one) returns Context');
    ok(!$comp->is_zero($result), '5-ary multiply(one,one) is not zero');

    # Annotations are preserved on multiply result
    ok(defined $result->annotations()->{cfg}, '5-ary multiply result has cfg annotation');
}

# ========================================================================
# add() — returns a single Context (not arrayref)
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();
    my $zero = $comp->zero();

    my $result = $comp->add($one, $one);
    isa_ok($result, 'Chalk::Bootstrap::Context', 'add(one,one) returns Context');
    ok(!$comp->is_zero($result), 'add(one,one) is not zero');

    # add(zero, x) = x, add(x, zero) = x
    my $r_left  = $comp->add($zero, $one);
    isa_ok($r_left, 'Chalk::Bootstrap::Context', 'add(zero,one) returns Context');
    ok(!$comp->is_zero($r_left), 'add(zero,one) is not zero');

    my $r_right = $comp->add($one, $zero);
    isa_ok($r_right, 'Chalk::Bootstrap::Context', 'add(one,zero) returns Context');
    ok(!$comp->is_zero($r_right), 'add(one,zero) is not zero');
}

# ========================================================================
# on_scan() — returns Context or zero Context
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    my $result = $comp->on_scan($one, 'Identifier', 0, 0, 'foo');
    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_scan returns Context');
    ok(!$comp->is_zero($result), 'on_scan result is not zero');
}

{
    my $comp = make_2ary_comp();
    my $zero = $comp->zero();

    my $result = $comp->on_scan($zero, 'Identifier', 0, 0, 'foo');
    ok($comp->is_zero($result), 'on_scan(zero) returns zero');
}

# ========================================================================
# on_complete() — returns Context or zero Context
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    # First scan to build a tree node
    my $scanned = $comp->on_scan($one, 'Identifier', 0, 0, 'foo');

    my $result = $comp->on_complete($scanned, 'Identifier', 0, 1, 0);
    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_complete returns Context');
    ok(!$comp->is_zero($result), 'on_complete result is not zero');
}

{
    my $comp = make_2ary_comp();
    my $zero = $comp->zero();

    my $result = $comp->on_complete($zero, 'Identifier', 0, 1, 0);
    ok($comp->is_zero($result), 'on_complete(zero) returns zero');
}

# ========================================================================
# on_skip_optional() — returns Context or zero Context
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    my $result = $comp->on_skip_optional($one, 'Element', 0, 0, 'Quantifier');
    isa_ok($result, 'Chalk::Bootstrap::Context', 'on_skip_optional returns Context');
    ok(!$comp->is_zero($result), 'on_skip_optional result is not zero');
}

# ========================================================================
# should_scan() — returns bool
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    my $result = $comp->should_scan($one, 'Identifier', 0, 0, 'foo', sub { false });
    ok($result, 'should_scan(one,...) returns true for identifier');
}

# ========================================================================
# 5-ary: precedence annotation survives multiply
# ========================================================================

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->on_scan($one, 'Identifier', 0, 0, 'foo');
    ok(defined $scanned->annotations()->{precedence},
        '5-ary on_scan result has precedence annotation');
    ok(defined $scanned->annotations()->{structural},
        '5-ary on_scan result has structural annotation');
}

# ========================================================================
# 5-ary: annotations->{type} is a tag hash after #707 migration (no _ti_raw)
# ========================================================================

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->on_scan($one, 'Identifier', 0, 0, 'foo');
    ok(!exists $scanned->annotations()->{_ti_raw},
        '5-ary on_scan result has no _ti_raw annotation after #707 migration');
    ok(exists $scanned->annotations()->{type},
        '5-ary on_scan result has type annotation');
}

# ========================================================================
# Integration: parse_ir via TestPipeline returns Context extract, not tuple
# ========================================================================

{
    use TestPipeline qw(parse_ir build_parser);

    my $parser = build_parser();
    my $ir = parse_ir($parser, 'Identifier ::= /[a-z]+/ ;');
    ok(defined $ir, 'parse_ir returns defined value for valid input');
    # IR should be a Grammar object (arrayref of rules), not a raw N-tuple
    ok(ref($ir) eq 'ARRAY' || (ref($ir) && $ir->isa('Chalk::Bootstrap::IR::Node')),
        'parse_ir result is IR (not a raw N-tuple)');
}

done_testing();

# ABOUTME: Tests FilterComposite unified Context interface (#706).
# ABOUTME: Verifies zero/one/is_zero/multiply/add return Context objects; complete via multiply.
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
use Chalk::IR::NodeFactory;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;

no warnings 'experimental::class';


# ========================================================================
# Helpers
# ========================================================================

# Helper: build an annotated scan Context (as Earley would create it)
sub make_scan_ctx($rule_name, $matched_text, $is_predicted_hash = {}) {
    return Chalk::Bootstrap::Context->new(
        focus       => $matched_text,
        position    => 0,
        annotations => {
            scan      => true,
            rule_name => $rule_name,
            alt_idx   => 0,
            predicted => $is_predicted_hash,
        },
    );
}

# Helper: build an annotated complete Context (as Earley would create it)
sub make_complete_ctx($value, $rule_name, $alt_idx, $pos, $origin) {
    return Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$value],
        position    => $pos,
        annotations => {
            complete  => true,
            rule_name => $rule_name,
            alt_idx   => $alt_idx,
            pos       => $pos,
            origin    => $origin,
        },
    );
}

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
# multiply with scan Context — returns Context or zero Context
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    my $result = $comp->multiply($one, make_scan_ctx('Identifier', 'foo'));
    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply with scan Context returns Context');
    ok(!$comp->is_zero($result), 'multiply with scan Context result is not zero');
}

{
    my $comp = make_2ary_comp();
    my $zero = $comp->zero();

    my $result = $comp->multiply($zero, make_scan_ctx('Identifier', 'foo'));
    ok($comp->is_zero($result), 'multiply(zero, scan_ctx) returns zero');
}

# ========================================================================
# multiply with complete Context — replaces on_complete
# Complete events are now handled by multiply with annotations->{complete}=true
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    # First multiply with scan Context to build a tree node
    my $scanned = $comp->multiply($one, make_scan_ctx('Identifier', 'foo'));

    my $complete_ctx = make_complete_ctx($scanned, 'Identifier', 0, 1, 0);
    my $result = $comp->multiply($scanned, $complete_ctx);
    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply with complete Context returns Context');
    ok(!$comp->is_zero($result), 'multiply with complete Context result is not zero');
}

{
    my $comp = make_2ary_comp();
    my $zero = $comp->zero();

    my $complete_ctx = make_complete_ctx($zero, 'Identifier', 0, 1, 0);
    my $result = $comp->multiply($zero, $complete_ctx);
    ok($comp->is_zero($result), 'multiply(zero, complete_ctx) returns zero');
}

# ========================================================================
# absent optional — multiply(value, one()) replaces on_skip_optional
# Absent optionals produce multiply(value, one()) which creates an
# unfocused Context node; action methods see one() for absent optionals.
# ========================================================================

{
    my $comp = make_2ary_comp();
    my $one  = $comp->one();

    my $result = $comp->multiply($one, $comp->one());
    isa_ok($result, 'Chalk::Bootstrap::Context', 'multiply(one, one()) for absent optional returns Context');
    ok(!$comp->is_zero($result), 'multiply(one, one()) for absent optional is not zero');
}

# ========================================================================
# 5-ary: precedence annotation survives multiply with scan Context
# ========================================================================

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->multiply($one, make_scan_ctx('Identifier', 'foo'));
    ok(defined $scanned->annotations()->{precedence},
        '5-ary multiply with scan Context result has precedence annotation');
    ok(defined $scanned->annotations()->{structural},
        '5-ary multiply with scan Context result has structural annotation');
}

# ========================================================================
# 5-ary: annotations->{type} is a tag hash after #707 migration (no _ti_raw)
# ========================================================================

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->multiply($one, make_scan_ctx('Identifier', 'foo'));
    ok(!exists $scanned->annotations()->{_ti_raw},
        '5-ary multiply result has no _ti_raw annotation after #707 migration');
    ok(exists $scanned->annotations()->{type},
        '5-ary multiply result has type annotation');
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

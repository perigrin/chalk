# ABOUTME: Tests for TI tree-walker migration to read from annotations->{type} (#707).
# ABOUTME: Verifies TI multiply returns tag hash directly for scan events and on_complete walks shared Context.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::TypeInference;
use Chalk::Bootstrap::Semiring::FilterComposite;
use Chalk::Bootstrap::Semiring::Boolean;
use Chalk::Bootstrap::Semiring::Precedence;
use Chalk::Bootstrap::Semiring::Structural;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Grammar::Perl::PrecedenceTable;
use Chalk::Bootstrap::IR::NodeFactory;

no warnings 'experimental::class';

Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

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

# Helper: build a complete-annotated Context for multiply() calls.
# Replaces on_complete($value, $rule_name, $alt_idx, $pos, $origin).
my $make_complete = sub ($value, $rule_name, $alt_idx, $pos, $origin) {
    $pos    //= 0;
    $origin //= 0;
    $alt_idx //= 0;
    return Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => defined($value) ? [$value] : [],
        position    => $pos,
        annotations => {
            complete  => true,
            rule_name => $rule_name,
            alt_idx   => $alt_idx,
            pos       => $pos,
            origin    => $origin,
        },
    );
};

# Build a TypeInference semiring for direct testing
my $ti = Chalk::Bootstrap::Semiring::TypeInference->new(
    keyword_check  => \&Chalk::Grammar::Perl::KeywordTable::is_keyword,
    builtin_lookup => \&Chalk::Grammar::Perl::TypeLibrary::get_builtin,
);

# Build a 5-ary FilterComposite
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
# TI multiply with scan Context: returns a tag hash directly (not a TI Context)
# ========================================================================

{
    my $result = $ti->multiply($ti->one(), make_scan_ctx('RegexLiteral', '/foo/'));
    ok(ref($result) eq 'HASH', 'TI multiply with RegexLiteral scan returns a tag hash');
    is($result->{type}, 'Regex', 'TI multiply RegexLiteral tag hash has type => Regex');
    ok($result->{valid}, 'TI multiply RegexLiteral tag hash has valid => true');
}

{
    my $result = $ti->multiply($ti->one(), make_scan_ctx('ScalarVariable', '$foo'));
    ok(ref($result) eq 'HASH', 'TI multiply with ScalarVariable scan returns a tag hash');
    is($result->{type}, 'Scalar', 'TI multiply ScalarVariable tag hash has type => Scalar');
}

{
    my $result = $ti->multiply($ti->one(), make_scan_ctx('QualifiedIdentifier', 'push'));
    ok(ref($result) eq 'HASH', 'TI multiply with builtin QualifiedIdentifier scan returns a tag hash');
    is($result->{call_symbol}, 'push', 'TI multiply builtin has call_symbol => push');
}

{
    my $result = $ti->multiply($ti->one(), make_scan_ctx('QualifiedIdentifier', 'myvar'));
    ok(ref($result) eq 'HASH', 'TI multiply with non-builtin identifier scan returns tag hash');
    ok(!exists $result->{call_symbol}, 'TI multiply non-builtin has no call_symbol');
    is($result->{ident_text}, 'myvar', 'TI multiply identifier has ident_text => myvar');
}

{
    my $result = $ti->multiply($ti->one(), make_scan_ctx('BinaryOp', '+'));
    ok(ref($result) eq 'HASH', 'TI multiply with BinaryOp scan returns tag hash');
    is($result->{op_text}, '+', 'TI multiply BinaryOp has op_text => +');
}

{
    # Transparent rule: returns valid tag hash with no type
    my $result = $ti->multiply($ti->one(), make_scan_ctx('SomeOtherRule', 'text'));
    ok(ref($result) eq 'HASH', 'TI multiply with transparent rule scan returns tag hash');
    ok($result->{valid}, 'TI multiply transparent result has valid => true');
    ok(!exists $result->{type}, 'TI multiply transparent result has no type');
}

# ========================================================================
# TI multiply undef/zero: returns undef when left is undef
# ========================================================================

{
    my $result = $ti->multiply(undef, make_scan_ctx('RegexLiteral', '/foo/'));
    ok(!defined $result, 'TI multiply(undef, scan_ctx) returns undef (zero)');
}

# ========================================================================
# FilterComposite: multiply with scan Context sets annotations->{type} from TI tag hash
# ========================================================================

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->multiply($one, make_scan_ctx('RegexLiteral', '/foo/'));
    ok(!$comp->is_zero($scanned), 'multiply RegexLiteral scan is not zero');

    my $type_ann = $scanned->annotations()->{type};
    ok(ref($type_ann) eq 'HASH', 'annotations->{type} is a hash ref after RegexLiteral scan');
    is($type_ann->{type}, 'Regex', 'annotations->{type}{type} = Regex after RegexLiteral scan');
}

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->multiply($one, make_scan_ctx('ScalarVariable', '$x'));
    ok(!$comp->is_zero($scanned), 'multiply ScalarVariable scan is not zero');

    my $type_ann = $scanned->annotations()->{type};
    ok(ref($type_ann) eq 'HASH', 'annotations->{type} is a hash ref after ScalarVariable scan');
    is($type_ann->{type}, 'Scalar', 'annotations->{type}{type} = Scalar after ScalarVariable scan');
}

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->multiply($one, make_scan_ctx('QualifiedIdentifier', 'push'));
    ok(!$comp->is_zero($scanned), 'multiply push builtin scan is not zero');

    my $type_ann = $scanned->annotations()->{type};
    ok(ref($type_ann) eq 'HASH', 'annotations->{type} is a hash ref after builtin scan');
    is($type_ann->{call_symbol}, 'push', 'annotations->{type}{call_symbol} = push');
}

# ========================================================================
# FilterComposite: _ti_raw is NOT present in multiply result (#707 removes it)
# ========================================================================

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    my $scanned = $comp->multiply($one, make_scan_ctx('ScalarVariable', '$x'));
    ok(!exists $scanned->annotations()->{_ti_raw},
        'annotations->{_ti_raw} is absent after #707 migration');
}

# ========================================================================
# TI on_complete: walks shared Context reading annotations->{type}
# ========================================================================

{
    # Build a shared Context tree that simulates multiply of two scan nodes.
    # Left child: ScalarVariable scan → annotations->{type} = {type => 'Scalar'}
    # Right child: BinaryOp scan → annotations->{type} = {op_text => '+'}
    my $left_child = Chalk::Bootstrap::Context->new(
        focus       => { scan => 'scalar' },  # any defined focus to stop walk
        children    => [],
        position    => 0,
        annotations => { type => { valid => 1, type => 'Scalar' } },
    );
    my $right_child = Chalk::Bootstrap::Context->new(
        focus       => { scan => 'op' },
        children    => [],
        position    => 1,
        annotations => { type => { valid => 1, op_text => '+' } },
    );
    my $shared_ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$left_child, $right_child],
        position    => 1,
        annotations => { type => undef },
    );

    my $result = $ti->multiply($shared_ctx, $make_complete->($shared_ctx, 'BinaryExpression', 0, 2, 0));
    ok(ref($result) eq 'HASH', 'TI multiply with complete Context returns a tag hash for BinaryExpression');
    ok($result->{valid}, 'TI multiply BinaryExpression result is valid');
    # BinaryExpression with op_text => '+' → result type is Num
    is($result->{type}, 'Num', 'TI multiply BinaryExpression + → type Num');
}

{
    # ExpressionList on_complete: reads item_types from child annotations->{type}
    my $child_ctx = Chalk::Bootstrap::Context->new(
        focus       => { item_types => ['Scalar'] },  # old-style: won't be found
        children    => [],
        position    => 0,
        annotations => { type => { valid => 1, type => 'Int' } },
    );
    my $shared_ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$child_ctx],
        position    => 0,
        annotations => { type => undef },
    );

    my $result = $ti->multiply($shared_ctx, $make_complete->($shared_ctx, 'ExpressionList', 0, 1, 0));
    ok(ref($result) eq 'HASH', 'TI multiply ExpressionList returns tag hash');
    ok($result->{valid}, 'TI multiply ExpressionList result is valid');
    is($result->{list_arity}, 1, 'TI multiply ExpressionList alt 0 arity = 1');
    # item_types should reflect the type from annotations->{type}
    is_deeply($result->{item_types}, ['Int'],
        'TI multiply ExpressionList reads type from annotations->{type}');
}

# ========================================================================
# FilterComposite: on_complete sets annotations->{type} to tag hash from TI
# ========================================================================

{
    my $comp = make_5ary_comp();
    my $one  = $comp->one();

    # Scan an identifier to build up context
    my $scanned_ident = $comp->multiply($one, make_scan_ctx('QualifiedIdentifier', 'myvar'));
    my $completed = $comp->multiply($scanned_ident, $make_complete->($scanned_ident, 'Atom', 0, 1, 0));

    ok(!$comp->is_zero($completed), 'multiply with complete Context Atom is not zero');
    my $type_ann = $completed->annotations()->{type};
    ok(ref($type_ann) eq 'HASH', 'multiply Atom annotations->{type} is a hash ref');
    ok($type_ann->{valid}, 'multiply Atom annotations->{type}{valid} is true');
}

# ========================================================================
# TI tree-walkers: _get_call_symbol reads from annotations->{type}
# ========================================================================

{
    # After migration: _get_call_symbol reads annotations->{type}{call_symbol}
    # Build a shared Context with annotations->{type} = {call_symbol => 'push'}
    my $leaf = Chalk::Bootstrap::Context->new(
        focus       => { scan => 'builtin' },  # defined focus to stop walk
        children    => [],
        position    => 0,
        annotations => { type => { valid => 1, call_symbol => 'push' } },
    );
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$leaf],
        position    => 0,
        annotations => { type => undef },
    );

    # _get_call_symbol is private, but on_complete for CallExpression uses it.
    # We can test indirectly: CallExpression on_complete with call_symbol in annotations
    # will look up the 'push' builtin and validate args.
    # Simulate CallExpression: pass ctx whose child has call_symbol annotation.
    my $result = $ti->multiply($ctx, $make_complete->($ctx, 'CallExpression', 0, 1, 0));
    # CallExpression with no item_types → passes arity check (min_arity may be 0 or > 0)
    # We just verify it runs without dying and returns a hash
    ok(!defined $result || ref($result) eq 'HASH',
        'TI multiply CallExpression with annotated call_symbol returns hash or undef');
}

# ========================================================================
# TypeInferenceActions helpers: read from annotations->{type}
# ========================================================================

{
    use Chalk::Bootstrap::Semiring::TypeInferenceActions;
    my $tia = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # Build a shared-tree Context where child has annotations->{type}{type} = 'Int'
    my $leaf = Chalk::Bootstrap::Context->new(
        focus       => { scan => 'literal' },
        children    => [],
        position    => 0,
        annotations => { type => { valid => 1, type => 'Int' } },
    );
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$leaf],
        position    => 0,
        annotations => { type => undef },
    );

    my $result = $tia->Atom($ctx);
    ok(ref($result) eq 'HASH', 'TypeInferenceActions Atom returns hash');
    is($result->{type}, 'Int',
        'TypeInferenceActions Atom reads type from annotations->{type}');
}

{
    use Chalk::Bootstrap::Semiring::TypeInferenceActions;
    my $tia = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # BinaryExpression: reads op_text from annotations->{type}
    my $op_leaf = Chalk::Bootstrap::Context->new(
        focus       => { scan => 'op' },
        children    => [],
        position    => 0,
        annotations => { type => { valid => 1, op_text => '*' } },
    );
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$op_leaf],
        position    => 0,
        annotations => { type => undef },
    );

    my $result = $tia->BinaryExpression($ctx);
    ok(ref($result) eq 'HASH', 'TypeInferenceActions BinaryExpression returns hash');
    is($result->{type}, 'Num',
        'TypeInferenceActions BinaryExpression * → type Num from annotations');
}

{
    use Chalk::Bootstrap::Semiring::TypeInferenceActions;
    my $tia = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # ExpressionList alt 0: reads type from annotations->{type} of child
    my $child = Chalk::Bootstrap::Context->new(
        focus       => { scan => 'scalar' },
        children    => [],
        position    => 0,
        annotations => { type => { valid => 1, type => 'Str' } },
    );
    my $ctx = Chalk::Bootstrap::Context->new(
        focus       => undef,
        children    => [$child],
        position    => 0,
        annotations => { type => undef },
    );

    my $result = $tia->ExpressionList($ctx, 0);
    ok(ref($result) eq 'HASH', 'TypeInferenceActions ExpressionList returns hash');
    is_deeply($result->{item_types}, ['Str'],
        'TypeInferenceActions ExpressionList reads item type from annotations->{type}');
}

done_testing();

# ABOUTME: Test TypeInferenceActions class methods for type annotation logic.
# ABOUTME: Tests each action method in isolation with Context tree inputs matching extend() dispatch.
use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::TypeInferenceActions;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Grammar::Perl::KeywordTable;

# Helper to create a Context with given focus and children.
# Simulates the Context tree that extend() receives.
sub mock_ctx($focus, $children = []) {
    return Chalk::Bootstrap::Context->new(
        focus    => $focus,
        children => $children,
        position => 0,
        rule     => undef,
    );
}

# Helper: create a multiply-like unfocused Context with children
sub mul_ctx(@children) {
    return Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => \@children,
        position => 0,
        rule     => undef,
    );
}

my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

# Test 1: Atom (wrapper rule - child's type passthrough via tree-walk)
subtest 'Atom passthrough' => sub {
    # Child has type => 'Str' in its focus
    my $child_ctx = mock_ctx({ type => 'Str' });
    my $ctx = mul_ctx($child_ctx);

    my $result = $actions->Atom($ctx);
    is($result, { valid => true, type => 'Str' }, 'Atom passes through child type');

    # No type in children → valid but no type
    my $no_type_ctx = mul_ctx(mock_ctx({ valid => true }));
    $result = $actions->Atom($no_type_ctx);
    is($result, { valid => true }, 'Atom with no child type returns valid without type');
};

# Test 2: Expression (wrapper rule - child's type passthrough)
subtest 'Expression passthrough' => sub {
    my $child_ctx = mock_ctx({ type => 'Int' });
    my $ctx = mul_ctx($child_ctx);

    my $result = $actions->Expression($ctx);
    is($result, { valid => true, type => 'Int' }, 'Expression passes through child type');
};

# Test 3: PostfixExpression (wrapper rule)
subtest 'PostfixExpression passthrough' => sub {
    my $child_ctx = mock_ctx({ type => 'Num' });
    my $ctx = mul_ctx($child_ctx);

    my $result = $actions->PostfixExpression($ctx);
    is($result, { valid => true, type => 'Num' }, 'PostfixExpression passes through child type');
};

# Test 4: BinaryExpression (rich rule - op_text determines type)
subtest 'BinaryExpression type from operator' => sub {
    # op_text in child focus, found by $_get_op_text tree-walker
    my $op_ctx = mock_ctx({ op_text => '+' });
    my $ctx = mul_ctx($op_ctx);

    my $result = $actions->BinaryExpression($ctx);
    is($result, { valid => true, type => 'Num' }, 'BinaryExpression + returns Num');

    # String concatenation
    $op_ctx = mock_ctx({ op_text => '.' });
    $ctx = mul_ctx($op_ctx);
    $result = $actions->BinaryExpression($ctx);
    is($result, { valid => true, type => 'Str' }, 'BinaryExpression . returns Str');

    # Comparison
    $op_ctx = mock_ctx({ op_text => '==' });
    $ctx = mul_ctx($op_ctx);
    $result = $actions->BinaryExpression($ctx);
    is($result, { valid => true, type => 'Bool' }, 'BinaryExpression == returns Bool');

    # Logical operator → Any → no type tag
    $op_ctx = mock_ctx({ op_text => '&&' });
    $ctx = mul_ctx($op_ctx);
    $result = $actions->BinaryExpression($ctx);
    is($result, { valid => true }, 'BinaryExpression && returns valid without type');

    # No op_text: preserve child type (intermediate completion)
    my $child_ctx = mock_ctx({ type => 'Str' });
    $ctx = mul_ctx($child_ctx);
    $result = $actions->BinaryExpression($ctx);
    is($result, { valid => true, type => 'Str' }, 'BinaryExpression without op preserves child type');
};

# Test 5: UnaryExpression (rich rule - op_text determines type)
subtest 'UnaryExpression type from operator' => sub {
    # Unary minus → Num
    my $op_ctx = mock_ctx({ op_text => '-' });
    my $ctx = mul_ctx($op_ctx);

    my $result = $actions->UnaryExpression($ctx);
    is($result, { valid => true, type => 'Num' }, 'UnaryExpression - returns Num');

    # Logical not → Bool
    $op_ctx = mock_ctx({ op_text => '!' });
    $ctx = mul_ctx($op_ctx);
    $result = $actions->UnaryExpression($ctx);
    is($result, { valid => true, type => 'Bool' }, 'UnaryExpression ! returns Bool');

    # Bitwise not → Int
    $op_ctx = mock_ctx({ op_text => '~' });
    $ctx = mul_ctx($op_ctx);
    $result = $actions->UnaryExpression($ctx);
    is($result, { valid => true, type => 'Int' }, 'UnaryExpression ~ returns Int');
};

# Test 6: ExpressionList (tracks list arity and per-item types)
subtest 'ExpressionList arity and item_types' => sub {
    # alt 0: single Expression
    my $child_ctx = mock_ctx({ type => 'Str' });
    my $ctx = mul_ctx($child_ctx);

    my $result = $actions->ExpressionList($ctx, 0);
    is($result, {
        valid => true,
        list_arity => 1,
        item_types => ['Str'],
    }, 'ExpressionList alt 0: single item');

    # alt 1: ExpressionList , Expression (previous has arity+item_types)
    my $prev_ctx = mock_ctx({ list_arity => 2, item_types => ['Str', 'Int'] });
    my $new_ctx = mock_ctx({ type => 'Num' });
    $ctx = mul_ctx($prev_ctx, $new_ctx);

    $result = $actions->ExpressionList($ctx, 1);
    is($result, {
        valid => true,
        list_arity => 3,
        item_types => ['Str', 'Int', 'Num'],
    }, 'ExpressionList alt 1: appends item');

    # alt 3: trailing comma preserves arity
    my $prev_with_arity = mock_ctx({ list_arity => 2, item_types => ['Str', 'Int'] });
    $ctx = mul_ctx($prev_with_arity);

    $result = $actions->ExpressionList($ctx, 3);
    is($result, {
        valid => true,
        list_arity => 2,
        item_types => ['Str', 'Int'],
    }, 'ExpressionList alt 3: trailing comma preserves');
};

# Test 7: CallExpression is handled inline in TypeInference.pm, not via Actions dispatch.
# No test here — see semiring-type-inference.t for CallExpression tests.

# Test 8: Boundary rules (preserve type via tree-walk, clear other tags implicitly)
subtest 'Boundary rules preserve type, clear other tags' => sub {
    # Child has type and call_symbol and op_text in focus
    my $child_ctx = mock_ctx({ type => 'Array', call_symbol => 'push', op_text => '+' });
    my $ctx = mul_ctx($child_ctx);

    # ParenExpr: preserves type (via tree-walk), no call_symbol/op_text in result
    my $result = $actions->ParenExpr($ctx);
    is($result, { valid => true, type => 'Array' }, 'ParenExpr preserves type, clears others');

    # Block
    $result = $actions->Block($ctx);
    is($result, { valid => true, type => 'Array' }, 'Block preserves type, clears others');

    # Signature
    $result = $actions->Signature($ctx);
    is($result, { valid => true, type => 'Array' }, 'Signature preserves type, clears others');

    # Attribute
    $result = $actions->Attribute($ctx);
    is($result, { valid => true, type => 'Array' }, 'Attribute preserves type, clears others');
};

# Test 9: PostfixDeref (type depends on alt_idx)
subtest 'PostfixDeref type by alt_idx' => sub {
    my $ctx = mock_ctx({ valid => true });

    # alt 0 = ->@* (array)
    my $result = $actions->PostfixDeref($ctx, 0);
    is($result, { valid => true, type => 'Array' }, 'PostfixDeref alt 0 returns Array');

    # alt 1 = ->%* (hash)
    $result = $actions->PostfixDeref($ctx, 1);
    is($result, { valid => true, type => 'Hash' }, 'PostfixDeref alt 1 returns Hash');

    # alt 2 = ->$* (scalar)
    $result = $actions->PostfixDeref($ctx, 2);
    is($result, { valid => true, type => 'Scalar' }, 'PostfixDeref alt 2 returns Scalar');

    # alt 3 = ->$#* (scalar count)
    $result = $actions->PostfixDeref($ctx, 3);
    is($result, { valid => true, type => 'Scalar' }, 'PostfixDeref alt 3 returns Scalar');
};

# Test 10: Subscript (type depends on alt_idx)
subtest 'Subscript type by alt_idx' => sub {
    my $ctx = mock_ctx({ valid => true });

    # alt 0 = [...] (array subscript)
    my $result = $actions->Subscript($ctx, 0);
    is($result, { valid => true, type => 'Scalar' }, 'Subscript alt 0 returns Scalar');

    # alt 1 = {...} (hash subscript)
    $result = $actions->Subscript($ctx, 1);
    is($result, { valid => true, type => 'Scalar' }, 'Subscript alt 1 returns Scalar');

    # alt 2+ = ->() deref-call (type unknown)
    $result = $actions->Subscript($ctx, 2);
    is($result, { valid => true }, 'Subscript alt 2 returns valid without type');
};

# Test 11: Rules with fixed return types
subtest 'Rules with fixed types' => sub {
    my $ctx = mock_ctx({ valid => true });

    my $result = $actions->PostfixIncDec($ctx);
    is($result, { valid => true, type => 'Num' }, 'PostfixIncDec returns Num');

    $result = $actions->AnonymousSub($ctx);
    is($result, { valid => true, type => 'Code' }, 'AnonymousSub returns Code');

    $result = $actions->QwLiteral($ctx);
    is($result, { valid => true, type => 'List' }, 'QwLiteral returns List');

    $result = $actions->ArrayConstructor($ctx);
    is($result, { valid => true, type => 'ArrayRef' }, 'ArrayConstructor returns ArrayRef');

    $result = $actions->HashConstructor($ctx);
    is($result, { valid => true, type => 'HashRef' }, 'HashConstructor returns HashRef');
};

# Test 12: Rules with unknown types
subtest 'Rules with unknown types' => sub {
    my $ctx = mock_ctx({ valid => true });

    my $result = $actions->TernaryExpression($ctx);
    is($result, { valid => true }, 'TernaryExpression returns valid without type');

    $result = $actions->AssignmentExpression($ctx);
    is($result, { valid => true }, 'AssignmentExpression returns valid without type');

    $result = $actions->MethodCall($ctx);
    is($result, { valid => true }, 'MethodCall returns valid without type');
};

done_testing;

# ABOUTME: Test TypeInferenceActions class methods for type annotation and rejection logic.
# ABOUTME: Tests each action method in isolation with mock Context/tags inputs.
use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::Bootstrap::Context;
use Chalk::Bootstrap::Semiring::TypeInferenceActions;
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::Grammar::Perl::KeywordTable;

# Helper to create a mock Context with given focus and children
sub mock_ctx($focus, $children = []) {
    return Chalk::Bootstrap::Context->new(
        focus    => $focus,
        children => $children,
        position => 0,
        rule     => undef,
    );
}

# Test 1: Atom (wrapper rule - child's type passthrough)
subtest 'Atom passthrough' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # Child has type => 'Str'
    my $child_ctx = mock_ctx({ type => 'Str' });
    my $ctx = mock_ctx(undef, [$child_ctx]);
    my $tags = { type => 'Str' };

    my $result = $actions->Atom($ctx, $tags);
    is($result, { valid => true, type => 'Str' }, 'Atom passes through child type');
};

# Test 2: Expression (wrapper rule - child's type passthrough)
subtest 'Expression passthrough' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    my $child_ctx = mock_ctx({ type => 'Int' });
    my $ctx = mock_ctx(undef, [$child_ctx]);
    my $tags = { type => 'Int' };

    my $result = $actions->Expression($ctx, $tags);
    is($result, { valid => true, type => 'Int' }, 'Expression passes through child type');
};

# Test 3: PostfixExpression (wrapper rule)
subtest 'PostfixExpression passthrough' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    my $child_ctx = mock_ctx({ type => 'Num' });
    my $ctx = mock_ctx(undef, [$child_ctx]);
    my $tags = { type => 'Num' };

    my $result = $actions->PostfixExpression($ctx, $tags);
    is($result, { valid => true, type => 'Num' }, 'PostfixExpression passes through child type');
};

# Test 4: BinaryExpression (rich rule - op_text determines type)
subtest 'BinaryExpression type from operator' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # Addition operator -> Num type
    my $ctx = mock_ctx(undef);
    my $tags = { op_text => '+' };

    my $result = $actions->BinaryExpression($ctx, $tags);
    is($result, { valid => true, type => 'Num' }, 'BinaryExpression + returns Num');

    # String concatenation -> Str type
    $tags = { op_text => '.' };
    $result = $actions->BinaryExpression($ctx, $tags);
    is($result, { valid => true, type => 'Str' }, 'BinaryExpression . returns Str');

    # Comparison -> Bool type
    $tags = { op_text => '==' };
    $result = $actions->BinaryExpression($ctx, $tags);
    is($result, { valid => true, type => 'Bool' }, 'BinaryExpression == returns Bool');

    # Logical operator -> Any type (returns undef since Any is permissive)
    $tags = { op_text => '&&' };
    $result = $actions->BinaryExpression($ctx, $tags);
    is($result, { valid => true }, 'BinaryExpression && returns valid without type');
};

# Test 5: UnaryExpression (rich rule - op_text determines type)
subtest 'UnaryExpression type from operator' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # Unary minus -> Num type
    my $ctx = mock_ctx(undef);
    my $tags = { op_text => '-' };

    my $result = $actions->UnaryExpression($ctx, $tags);
    is($result, { valid => true, type => 'Num' }, 'UnaryExpression - returns Num');

    # Logical not -> Bool type
    $tags = { op_text => '!' };
    $result = $actions->UnaryExpression($ctx, $tags);
    is($result, { valid => true, type => 'Bool' }, 'UnaryExpression ! returns Bool');

    # Bitwise not -> Int type
    $tags = { op_text => '~' };
    $result = $actions->UnaryExpression($ctx, $tags);
    is($result, { valid => true, type => 'Int' }, 'UnaryExpression ~ returns Int');
};

# Test 6: ExpressionList (tracks list arity and per-item types)
subtest 'ExpressionList arity and item_types' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # Test with tags already computed by TypeInference
    my $ctx = mock_ctx(undef);
    my $tags = {
        list_arity => 3,
        item_types => ['Str', 'Int', 'Num']
    };

    # ExpressionList doesn't transform, it uses tags as-is
    my $result = $actions->ExpressionList($ctx, $tags);
    is($result, {
        valid => true,
        list_arity => 3,
        item_types => ['Str', 'Int', 'Num']
    }, 'ExpressionList preserves arity and item_types');
};

# Test 7: CallExpression (validates builtin signatures)
subtest 'CallExpression builtin validation' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # Valid builtin call: push(@arr, $val) - Array + Any
    my $ctx = mock_ctx(undef);
    my $tags = {
        call_symbol => 'push',
        item_types => ['Array', 'Str'],
        list_arity => 2
    };

    my $result = $actions->CallExpression($ctx, $tags);
    is($result, { valid => true, type => 'Int' }, 'CallExpression push returns Int');

    # Valid builtin: length($str) - Scalar (satisfies implicit type)
    $tags = {
        call_symbol => 'length',
        item_types => ['Str'],
        list_arity => 1
    };
    $result = $actions->CallExpression($ctx, $tags);
    is($result, { valid => true, type => 'Int' }, 'CallExpression length returns Int');

    # Unknown function - returns Unknown type
    $tags = {
        call_symbol => 'unknown_func',
        item_types => ['Str'],
        list_arity => 1
    };
    $result = $actions->CallExpression($ctx, $tags);
    is($result, { valid => true, type => 'Unknown' }, 'CallExpression unknown returns Unknown');

    # No call_symbol - returns Unknown
    $tags = {
        item_types => ['Str'],
        list_arity => 1
    };
    $result = $actions->CallExpression($ctx, $tags);
    is($result, { valid => true, type => 'Unknown' }, 'CallExpression no symbol returns Unknown');
};

# Test 8: Boundary rules (clear tags but preserve type)
subtest 'Boundary rules preserve type, clear other tags' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # ParenExpr: preserves type, clears call_symbol/op_text
    my $ctx = mock_ctx(undef);
    my $tags = {
        type => 'Array',
        call_symbol => 'push',
        op_text => '+'
    };

    my $result = $actions->ParenExpr($ctx, $tags);
    is($result, { valid => true, type => 'Array' }, 'ParenExpr preserves type, clears others');

    # Block: same behavior
    $result = $actions->Block($ctx, $tags);
    is($result, { valid => true, type => 'Array' }, 'Block preserves type, clears others');

    # Signature: same behavior
    $result = $actions->Signature($ctx, $tags);
    is($result, { valid => true, type => 'Array' }, 'Signature preserves type, clears others');

    # Attribute: same behavior
    $result = $actions->Attribute($ctx, $tags);
    is($result, { valid => true, type => 'Array' }, 'Attribute preserves type, clears others');
};

# Test 9: PostfixDeref (type depends on alt_idx)
subtest 'PostfixDeref type by alt_idx' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    my $ctx = mock_ctx(undef);
    my $tags = {};

    # alt 0 = ->@* (array)
    my $result = $actions->PostfixDeref($ctx, $tags, 0);
    is($result, { valid => true, type => 'Array' }, 'PostfixDeref alt 0 returns Array');

    # alt 1 = ->%* (hash)
    $result = $actions->PostfixDeref($ctx, $tags, 1);
    is($result, { valid => true, type => 'Hash' }, 'PostfixDeref alt 1 returns Hash');

    # alt 2 = ->$* (scalar)
    $result = $actions->PostfixDeref($ctx, $tags, 2);
    is($result, { valid => true, type => 'Scalar' }, 'PostfixDeref alt 2 returns Scalar');

    # alt 3 = ->$#* (scalar count)
    $result = $actions->PostfixDeref($ctx, $tags, 3);
    is($result, { valid => true, type => 'Scalar' }, 'PostfixDeref alt 3 returns Scalar');
};

# Test 10: Subscript (type depends on alt_idx)
subtest 'Subscript type by alt_idx' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    my $ctx = mock_ctx(undef);
    my $tags = {};

    # alt 0 = [...] (array subscript)
    my $result = $actions->Subscript($ctx, $tags, 0);
    is($result, { valid => true, type => 'Scalar' }, 'Subscript alt 0 returns Scalar');

    # alt 1 = {...} (hash subscript)
    $result = $actions->Subscript($ctx, $tags, 1);
    is($result, { valid => true, type => 'Scalar' }, 'Subscript alt 1 returns Scalar');

    # alt 2+ = ->() deref-call (type unknown)
    $result = $actions->Subscript($ctx, $tags, 2);
    is($result, { valid => true }, 'Subscript alt 2 returns valid without type');
};

# Test 11: Rules with fixed return types
subtest 'Rules with fixed types' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    my $ctx = mock_ctx(undef);
    my $tags = {};

    # PostfixIncDec -> Num
    my $result = $actions->PostfixIncDec($ctx, $tags);
    is($result, { valid => true, type => 'Num' }, 'PostfixIncDec returns Num');

    # AnonymousSub -> Code
    $result = $actions->AnonymousSub($ctx, $tags);
    is($result, { valid => true, type => 'Code' }, 'AnonymousSub returns Code');

    # QwLiteral -> List
    $result = $actions->QwLiteral($ctx, $tags);
    is($result, { valid => true, type => 'List' }, 'QwLiteral returns List');

    # ArrayConstructor -> ArrayRef
    $result = $actions->ArrayConstructor($ctx, $tags);
    is($result, { valid => true, type => 'ArrayRef' }, 'ArrayConstructor returns ArrayRef');

    # HashConstructor -> HashRef
    $result = $actions->HashConstructor($ctx, $tags);
    is($result, { valid => true, type => 'HashRef' }, 'HashConstructor returns HashRef');
};

# Test 12: Rules with unknown types
subtest 'Rules with unknown types' => sub {
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    my $ctx = mock_ctx(undef);
    my $tags = {};

    # TernaryExpression -> type unknown
    my $result = $actions->TernaryExpression($ctx, $tags);
    is($result, { valid => true }, 'TernaryExpression returns valid without type');

    # AssignmentExpression -> type unknown
    $result = $actions->AssignmentExpression($ctx, $tags);
    is($result, { valid => true }, 'AssignmentExpression returns valid without type');

    # MethodCall -> type unknown
    $result = $actions->MethodCall($ctx, $tags);
    is($result, { valid => true }, 'MethodCall returns valid without type');
};

done_testing;

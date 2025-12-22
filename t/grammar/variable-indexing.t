# ABOUTME: Tests for Variable semantic action with array/hash indexing
# ABOUTME: Verifies Variable generates ArrayGet/HashGet nodes for $arr[0], $hash{key}

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::Variable;
use Chalk::IR::Node::ArrayGet;
use Chalk::IR::Node::HashGet;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::NewHash;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::Scope;
use Chalk::IR::Node::Start;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Helper to create a scope with an array variable
sub make_scope_with_array {
    my ($var_name, $array_node) = @_;
    my $start = Chalk::IR::Node::Start->new();
    my $scope = Chalk::IR::Node::Scope->new();
    $scope = $scope->with_control($start);
    $scope = $scope->with_binding('@' . $var_name, $array_node);
    return $scope;
}

# Helper to create a scope with a hash variable
sub make_scope_with_hash {
    my ($var_name, $hash_node) = @_;
    my $start = Chalk::IR::Node::Start->new();
    my $scope = Chalk::IR::Node::Scope->new();
    $scope = $scope->with_control($start);
    $scope = $scope->with_binding('%' . $var_name, $hash_node);
    return $scope;
}

# Helper to create a context for Variable -> ScalarVar '[' Expression ']'
# This represents $arr[0] where the scalar access uses the array sigil lookup
sub make_array_subscript_context {
    my ($var_name, $index_node, $scope) = @_;

    # For $arr[0], the ScalarVar metadata points to scalar sigil
    # but we need to look up the array @arr
    my $scalar_var_metadata = {
        type => 'scalar_var',
        name => $var_name,
        sigil => '$'
    };

    # Children: ScalarVar, '[', Expression, ']'
    my @child_contexts = (
        # Child 0: ScalarVar (returns metadata)
        Chalk::EvalContext->new(
            focus => $scalar_var_metadata,
            children => [],
            start_pos => 0,
            end_pos => 4,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
        # Child 1: '['
        Chalk::EvalContext->new(
            focus => '[',
            children => [],
            start_pos => 4,
            end_pos => 5,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
        # Child 2: Expression (index node)
        Chalk::EvalContext->new(
            focus => $index_node,
            children => [],
            start_pos => 5,
            end_pos => 6,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
        # Child 3: ']'
        Chalk::EvalContext->new(
            focus => ']',
            children => [],
            start_pos => 6,
            end_pos => 7,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
    );

    return Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => 7,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );
}

# Helper to create a context for Variable -> ScalarVar '{' Expression '}'
# This represents $hash{key}
sub make_hash_subscript_context {
    my ($var_name, $key_node, $scope) = @_;

    my $scalar_var_metadata = {
        type => 'scalar_var',
        name => $var_name,
        sigil => '$'
    };

    # Children: ScalarVar, '{', Expression, '}'
    my @child_contexts = (
        # Child 0: ScalarVar (returns metadata)
        Chalk::EvalContext->new(
            focus => $scalar_var_metadata,
            children => [],
            start_pos => 0,
            end_pos => 5,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
        # Child 1: '{'
        Chalk::EvalContext->new(
            focus => '{',
            children => [],
            start_pos => 5,
            end_pos => 6,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
        # Child 2: Expression (key node)
        Chalk::EvalContext->new(
            focus => $key_node,
            children => [],
            start_pos => 6,
            end_pos => 9,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
        # Child 3: '}'
        Chalk::EvalContext->new(
            focus => '}',
            children => [],
            start_pos => 9,
            end_pos => 10,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
    );

    return Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => 10,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );
}

subtest 'Variable array subscript generates ArrayGet' => sub {
    my $array_node = Chalk::IR::Node::NewArray->new(inputs => []);
    my $scope = make_scope_with_array('arr', $array_node);

    my $index_node = Chalk::IR::Node::Constant->new(
        value => 0,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $context = make_array_subscript_context('arr', $index_node, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::Variable->new(
        lhs => 'Variable',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Result is blessed');
    is($result->op, 'ArrayGet', 'Returns an ArrayGet node');
    is($result->array_id, $array_node->id, 'Array ID is correct');
    is($result->index_id, $index_node->id, 'Index ID is correct');
};

subtest 'Variable hash subscript generates HashGet' => sub {
    my $hash_node = Chalk::IR::Node::NewHash->new(inputs => []);
    my $scope = make_scope_with_hash('config', $hash_node);

    my $key_node = Chalk::IR::Node::Constant->new(
        value => 'name',
        type => Chalk::Grammar::Chalk::Type::Str->new()
    );

    my $context = make_hash_subscript_context('config', $key_node, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::Variable->new(
        lhs => 'Variable',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Result is blessed');
    is($result->op, 'HashGet', 'Returns a HashGet node');
    is($result->hash_id, $hash_node->id, 'Hash ID is correct');
    is($result->key_id, $key_node->id, 'Key ID is correct');
};

subtest 'Variable still works for simple variable lookup' => sub {
    my $array_node = Chalk::IR::Node::NewArray->new(inputs => []);
    my $scope = make_scope_with_array('data', $array_node);

    # Simple ArrayVar context (just @data, no subscript)
    my $var_metadata = {
        type => 'array_var',
        name => 'data',
        sigil => '@'
    };

    my @child_contexts = (
        Chalk::EvalContext->new(
            focus => $var_metadata,
            children => [],
            start_pos => 0,
            end_pos => 5,
            env => { scope => $scope },
            grammar => undef,
            rule => undef
        ),
    );

    my $context = Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => 5,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::Variable->new(
        lhs => 'Variable',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Result is blessed');
    is($result->id, $array_node->id, 'Returns the array node from scope');
};

done_testing();

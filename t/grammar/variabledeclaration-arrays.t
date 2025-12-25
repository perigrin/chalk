# ABOUTME: Tests for VariableDeclaration semantic action with arrays and hashes
# ABOUTME: Verifies VariableDeclaration generates proper IR nodes for @arr and %hash

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::VariableDeclaration;
use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::NewHash;
use Chalk::IR::Node::Store;
use Chalk::IR::Node::Scope;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::List;
use Chalk::IR::Node::Constant;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::EvalContext;
use Scalar::Util 'blessed';

# Helper to create a Start node for control flow
sub make_start {
    return Chalk::IR::Node::Start->new();
}

# Helper to create a scope with control flow
sub make_scope {
    my $start = make_start();
    my $scope = Chalk::IR::Node::Scope->new();
    return $scope->with_control($start);
}

# Helper to create a context for VariableDeclaration
# VariableDeclaration -> LexicalDeclarator WS_OPT Variable WS_OPT '=' WS_OPT Expression
sub make_decl_context {
    my ($var_metadata, $value_node, $scope) = @_;

    # Children: 'my', WS, Variable, WS, '=', WS, Expression
    my @child_contexts = (
        # Child 0: 'my' (LexicalDeclarator)
        Chalk::EvalContext->new(
            focus => 'my',
            children => [],
            start_pos => 0,
            end_pos => 2,
            env => {},
            grammar => undef,
            rule => undef
        ),
        # Child 1: WS_OPT (whitespace)
        Chalk::EvalContext->new(
            focus => ' ',
            children => [],
            start_pos => 2,
            end_pos => 3,
            env => {},
            grammar => undef,
            rule => undef
        ),
        # Child 2: Variable (returns metadata hash)
        Chalk::EvalContext->new(
            focus => $var_metadata,
            children => [],
            start_pos => 3,
            end_pos => 7,
            env => {},
            grammar => undef,
            rule => undef
        ),
        # Child 3: WS_OPT
        Chalk::EvalContext->new(
            focus => ' ',
            children => [],
            start_pos => 7,
            end_pos => 8,
            env => {},
            grammar => undef,
            rule => undef
        ),
        # Child 4: '='
        Chalk::EvalContext->new(
            focus => '=',
            children => [],
            start_pos => 8,
            end_pos => 9,
            env => {},
            grammar => undef,
            rule => undef
        ),
        # Child 5: WS_OPT
        Chalk::EvalContext->new(
            focus => ' ',
            children => [],
            start_pos => 9,
            end_pos => 10,
            env => {},
            grammar => undef,
            rule => undef
        ),
        # Child 6: Expression (the value IR node)
        Chalk::EvalContext->new(
            focus => $value_node,
            children => [],
            start_pos => 10,
            end_pos => 15,
            env => {},
            grammar => undef,
            rule => undef
        ),
    );

    my $env = { scope => $scope };

    return Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => 15,
        env => $env,
        grammar => undef,
        rule => undef
    );
}

subtest 'VariableDeclaration handles scalar_var' => sub {
    my $scope = make_scope();

    my $var_metadata = {
        type => 'scalar_var',
        name => 'x',
        sigil => '$'
    };

    my $value = Chalk::IR::Node::Constant->new(
        value => 42,
        type => Chalk::Grammar::Chalk::Type::Int->new()
    );

    my $context = make_decl_context($var_metadata, $value, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Result is blessed');
    is($result->op, 'Store', 'Returns a Store node');
    is($result->var, '$x', 'Variable name includes sigil for scalars');
};

subtest 'VariableDeclaration handles array_var' => sub {
    my $scope = make_scope();

    my $var_metadata = {
        type => 'array_var',
        name => 'arr',
        sigil => '@'
    };

    # For array declaration, the value is a NewArray node
    my $value = Chalk::IR::Node::NewArray->new(
        inputs => []
    );

    my $context = make_decl_context($var_metadata, $value, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Result is blessed');
    is($result->op, 'Store', 'Returns a Store node');
    is($result->var, '@arr', 'Variable name includes sigil for arrays');
};

subtest 'VariableDeclaration handles hash_var' => sub {
    my $scope = make_scope();

    my $var_metadata = {
        type => 'hash_var',
        name => 'hash',
        sigil => '%'
    };

    # For hash declaration, the value is a NewHash node
    my $value = Chalk::IR::Node::NewHash->new(
        inputs => []
    );

    my $context = make_decl_context($var_metadata, $value, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    ok(blessed($result), 'Result is blessed');
    is($result->op, 'Store', 'Returns a Store node');
    is($result->var, '%hash', 'Variable name includes sigil for hashes');
};

subtest 'VariableDeclaration updates scope with array binding' => sub {
    my $scope = make_scope();

    my $var_metadata = {
        type => 'array_var',
        name => 'data',
        sigil => '@'
    };

    my $value = Chalk::IR::Node::NewArray->new(
        inputs => []
    );

    my $context = make_decl_context($var_metadata, $value, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    $rule->evaluate($context);

    # Check that scope was updated
    my $new_scope = $context->env->{scope};
    my $bound_value = $new_scope->lookup('@data');
    ok(defined($bound_value), 'Array variable is bound in scope');
    is($bound_value->id, $value->id, 'Bound value matches the NewArray node');
};

subtest 'VariableDeclaration updates scope with hash binding' => sub {
    my $scope = make_scope();

    my $var_metadata = {
        type => 'hash_var',
        name => 'config',
        sigil => '%'
    };

    my $value = Chalk::IR::Node::NewHash->new(
        inputs => []
    );

    my $context = make_decl_context($var_metadata, $value, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    $rule->evaluate($context);

    # Check that scope was updated
    my $new_scope = $context->env->{scope};
    my $bound_value = $new_scope->lookup('%config');
    ok(defined($bound_value), 'Hash variable is bound in scope');
    is($bound_value->id, $value->id, 'Bound value matches the NewHash node');
};

done_testing();

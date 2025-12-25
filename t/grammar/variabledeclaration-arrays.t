# ABOUTME: Tests for VariableDeclaration semantic action with arrays and hashes
# ABOUTME: Verifies VariableDeclaration creates bindings in scope for @arr and %hash

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Chalk::Grammar;  # Must be loaded first to define Chalk::GrammarRule
use Chalk::Grammar::Chalk::Rule::VariableDeclaration;
use Chalk::IR::Node::UnboundVariable;
use Chalk::IR::Node::Scope;
use Chalk::IR::Node::Start;
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
# VariableDeclaration -> LexicalDeclarator WS_OPT Variable
# (No '=' - that's handled by Assignment)
sub make_decl_context {
    my ($unbound_var, $scope) = @_;

    # Children: 'my', WS, Variable (which evaluates to UnboundVariable)
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
        # Child 2: Variable (evaluates to UnboundVariable)
        Chalk::EvalContext->new(
            focus => $unbound_var,
            children => [],
            start_pos => 3,
            end_pos => 7,
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
        end_pos => 7,
        env => $env,
        grammar => undef,
        rule => undef
    );
}

subtest 'VariableDeclaration handles scalar_var' => sub {
    my $scope = make_scope();

    # Variable evaluates to UnboundVariable when not in scope
    my $unbound_var = Chalk::IR::Node::UnboundVariable->new(name => '$x');

    my $context = make_decl_context($unbound_var, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    # VariableDeclaration returns the UnboundVariable for Assignment to use
    isa_ok($result, 'Chalk::IR::Node::UnboundVariable', 'Returns UnboundVariable');
    is($result->name, '$x', 'Variable name is preserved');

    # Binding was created in scope
    my $new_scope = $context->env->{scope};
    my $bound_value = $new_scope->lookup('$x');
    ok(defined($bound_value), 'Scalar variable is bound in scope');
    is($bound_value->name, '$x', 'Bound value is the UnboundVariable');
};

subtest 'VariableDeclaration handles array_var' => sub {
    my $scope = make_scope();

    # Variable evaluates to UnboundVariable for arrays
    my $unbound_var = Chalk::IR::Node::UnboundVariable->new(name => '@arr');

    my $context = make_decl_context($unbound_var, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    # VariableDeclaration returns the UnboundVariable
    isa_ok($result, 'Chalk::IR::Node::UnboundVariable', 'Returns UnboundVariable');
    is($result->name, '@arr', 'Array name includes sigil');

    # Binding was created in scope
    my $new_scope = $context->env->{scope};
    my $bound_value = $new_scope->lookup('@arr');
    ok(defined($bound_value), 'Array variable is bound in scope');
    is($bound_value->name, '@arr', 'Bound value is the UnboundVariable');
};

subtest 'VariableDeclaration handles hash_var' => sub {
    my $scope = make_scope();

    # Variable evaluates to UnboundVariable for hashes
    my $unbound_var = Chalk::IR::Node::UnboundVariable->new(name => '%hash');

    my $context = make_decl_context($unbound_var, $scope);

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    # VariableDeclaration returns the UnboundVariable
    isa_ok($result, 'Chalk::IR::Node::UnboundVariable', 'Returns UnboundVariable');
    is($result->name, '%hash', 'Hash name includes sigil');

    # Binding was created in scope
    my $new_scope = $context->env->{scope};
    my $bound_value = $new_scope->lookup('%hash');
    ok(defined($bound_value), 'Hash variable is bound in scope');
    is($bound_value->name, '%hash', 'Bound value is the UnboundVariable');
};

subtest 'VariableDeclaration returns undef without scope' => sub {
    # Variable evaluates to UnboundVariable
    my $unbound_var = Chalk::IR::Node::UnboundVariable->new(name => '$x');

    # Create context without scope
    my @child_contexts = (
        Chalk::EvalContext->new(
            focus => 'my',
            children => [],
            start_pos => 0,
            end_pos => 2,
            env => {},
            grammar => undef,
            rule => undef
        ),
        Chalk::EvalContext->new(
            focus => ' ',
            children => [],
            start_pos => 2,
            end_pos => 3,
            env => {},
            grammar => undef,
            rule => undef
        ),
        Chalk::EvalContext->new(
            focus => $unbound_var,
            children => [],
            start_pos => 3,
            end_pos => 7,
            env => {},
            grammar => undef,
            rule => undef
        ),
    );

    my $context = Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => 7,
        env => {},  # No scope
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    is($result, undef, 'Returns undef when no scope available');
};

subtest 'VariableDeclaration returns undef for non-name node' => sub {
    my $scope = make_scope();

    # Pass a string instead of an object with name()
    my @child_contexts = (
        Chalk::EvalContext->new(
            focus => 'my',
            children => [],
            start_pos => 0,
            end_pos => 2,
            env => {},
            grammar => undef,
            rule => undef
        ),
        Chalk::EvalContext->new(
            focus => ' ',
            children => [],
            start_pos => 2,
            end_pos => 3,
            env => {},
            grammar => undef,
            rule => undef
        ),
        Chalk::EvalContext->new(
            focus => 'not_an_object',  # String, not object with name()
            children => [],
            start_pos => 3,
            end_pos => 7,
            env => {},
            grammar => undef,
            rule => undef
        ),
    );

    my $context = Chalk::EvalContext->new(
        children => \@child_contexts,
        focus => undef,
        start_pos => 0,
        end_pos => 7,
        env => { scope => $scope },
        grammar => undef,
        rule => undef
    );

    my $rule = Chalk::Grammar::Chalk::Rule::VariableDeclaration->new(
        lhs => 'VariableDeclaration',
        rhs => []
    );
    my $result = $rule->evaluate($context);

    is($result, undef, 'Returns undef when child lacks name() method');
};

done_testing();

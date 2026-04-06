# ABOUTME: Tests that AssignmentExpression updates cfg_state scope on variable assignment
# ABOUTME: Covers VarDecl target, plain variable assignment, and compound assignment
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::IR::Node::Constant;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Actions;
use Chalk::Bootstrap::Context;
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# Helper: build a leaf Context wrapping an IR node (simulates a completed sub-rule)
my sub make_leaf_ctx($node) {
    return Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => undef,
    );
}

# Helper: build a parent Context with specified leaf children (focus=undef)
my sub make_parent_ctx(@children) {
    return Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => \@children,
        position => 0,
        rule     => undef,
    );
}

# --- Case 1: VarDecl target assignment updates scope ---
# AssignmentExpression(VarDecl_with_no_init, '=', Constant(42))
# Should create a new VarDecl with initializer and bind '$x' in scope
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    # Simulate a VarDecl node with no initializer yet (from 'my $x')
    my $var_node = $factory->make('Constant', const_type => 'variable', value => '$x');
    my $vardecl = $factory->make('Constructor',
        'class'       => 'VarDecl',
        variable    => $var_node,
        initializer => undef,
    );
    my $op_node   = $factory->make('Constant', const_type => 'string', value => '=');
    my $rhs_node  = $factory->make('Constant', const_type => 'integer', value => '42');

    # Build a parent context with leaves: [VarDecl, '=', 42]
    my $ctx = make_parent_ctx(
        make_leaf_ctx($vardecl),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    # Set cfg_state with an empty scope on the input context
    my $scope = Chalk::Bootstrap::Scope->new();
    $sa->set_cfg_state($ctx, {
        control => $factory->make('Start'),
        scope   => $scope,
    });

    my $result = $sa->on_complete($ctx, 'AssignmentExpression', 0, 0, 0);
    ok(defined $result, 'VarDecl assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'result has an IR node');
    ok($node isa Chalk::IR::Node, 'result is an IR node');
    is($node->class(), 'VarDecl', 'result is a VarDecl');

    # Verify the scope was updated
    my $state = $sa->cfg_state($result);
    ok(defined $state, 'result context has cfg_state');
    if (defined $state) {
        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x is in scope after VarDecl assignment');
        is($x_binding, $node, '$x is bound to the VarDecl IR node');
    }
}

# --- Case 2: Plain variable reassignment updates scope ---
# AssignmentExpression(Constant(variable, '$x'), '=', Constant(2))
# Should create a VarDecl and bind '$x' in scope with the new VarDecl
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    # Simulate '$x = 2' — LHS is a raw variable Constant
    my $var_node  = $factory->make('Constant', const_type => 'variable', value => '$x');
    my $op_node   = $factory->make('Constant', const_type => 'string', value => '=');
    my $rhs_node  = $factory->make('Constant', const_type => 'integer', value => '2');

    my $ctx = make_parent_ctx(
        make_leaf_ctx($var_node),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    # Pre-populate scope with existing $x binding (value 1)
    my $old_x = $factory->make('Constant', const_type => 'integer', value => '1');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $old_x);

    $sa->set_cfg_state($ctx, {
        control => $factory->make('Start'),
        scope   => $scope,
    });

    my $result = $sa->on_complete($ctx, 'AssignmentExpression', 0, 0, 0);
    ok(defined $result, 'plain assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'plain assignment: result has an IR node');
    ok($node isa Chalk::IR::Node, 'plain assignment: result is an IR node');
    is($node->class(), 'BinaryExpr', 'plain assignment: result is a BinaryExpr (Assign)');

    # Verify scope was updated with the Assign node
    my $state = $sa->cfg_state($result);
    ok(defined $state, 'plain assignment: result has cfg_state');
    if (defined $state) {
        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x is in scope after plain assignment');
        is($x_binding, $node, '$x binding is updated to the new VarDecl node');
        isnt($x_binding, $old_x, '$x binding is not the old value anymore');
    }
}

# --- Case 3: Compound assignment ($x += 5) updates scope ---
# AssignmentExpression(Constant(variable, '$x'), '+=', Constant(5))
# Should create a CompoundAssign and bind '$x' in scope
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $var_node  = $factory->make('Constant', const_type => 'variable', value => '$x');
    my $op_node   = $factory->make('Constant', const_type => 'string', value => '+=');
    my $rhs_node  = $factory->make('Constant', const_type => 'integer', value => '5');

    my $ctx = make_parent_ctx(
        make_leaf_ctx($var_node),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    # Pre-populate scope
    my $old_x = $factory->make('Constant', const_type => 'integer', value => '0');
    my $scope = Chalk::Bootstrap::Scope->new();
    $scope = $scope->define('$x', $old_x);

    $sa->set_cfg_state($ctx, {
        control => $factory->make('Start'),
        scope   => $scope,
    });

    my $result = $sa->on_complete($ctx, 'AssignmentExpression', 0, 0, 0);
    ok(defined $result, 'compound assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'compound assignment: result has an IR node');
    ok($node isa Chalk::IR::Node, 'compound assignment: result is an IR node');
    is($node->class(), 'CompoundAssign', 'compound assignment: result is a CompoundAssign');

    # Verify scope was updated with the CompoundAssign node
    my $state = $sa->cfg_state($result);
    ok(defined $state, 'compound assignment: result has cfg_state');
    if (defined $state) {
        my $x_binding = $state->{scope}->lookup('$x');
        ok(defined $x_binding, '$x is in scope after compound assignment');
        is($x_binding, $node, '$x binding is updated to the CompoundAssign node');
        isnt($x_binding, $old_x, '$x binding is not the old value anymore');
    }
}

# --- Case 4: Assignment with no scope (no cfg_state) — backward compat ---
# If no cfg_state, AssignmentExpression should still produce a VarDecl/CompoundAssign
# but without crashing, and with no scope update
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $var_node = $factory->make('Constant', const_type => 'variable', value => '$y');
    my $op_node  = $factory->make('Constant', const_type => 'string', value => '=');
    my $rhs_node = $factory->make('Constant', const_type => 'integer', value => '99');

    # No cfg_state set on this context
    my $ctx = make_parent_ctx(
        make_leaf_ctx($var_node),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    my $result = $sa->on_complete($ctx, 'AssignmentExpression', 0, 0, 0);
    ok(defined $result, 'no-scope assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'no-scope assignment: result has an IR node');
    is($node->class(), 'BinaryExpr', 'no-scope assignment: returns BinaryExpr (Assign)');
}

done_testing();

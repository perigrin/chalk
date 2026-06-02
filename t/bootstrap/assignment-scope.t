# ABOUTME: Tests that AssignmentExpression updates scope on variable assignment
# ABOUTME: Covers VarDecl target, plain variable assignment, and compound assignment
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;
use Chalk::Bootstrap::Bindings;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Actions;
use Chalk::Bootstrap::Context;
my $factory = Chalk::IR::NodeFactory->new();
my $typed   = Chalk::IR::NodeFactory->new;

# Helper: build a leaf Context wrapping an IR node (simulates a completed sub-rule)
my sub make_leaf_ctx($node) {
    return Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => undef,
    );
}

# Helper: build a parent Context with specified leaf children (focus=undef) and scope.
# Scope carries the control input node as per the new scope-based API.
my sub make_parent_ctx($bindings, $control_head, @children) {
    return Chalk::Bootstrap::Context->new(
        focus        => undef,
        children     => \@children,
        position     => 0,
        rule         => undef,
        bindings     => $bindings,
        control_head => $control_head,
        factory      => $factory,
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

# --- Case 1: VarDecl target assignment updates scope ---
# AssignmentExpression(VarDecl_with_no_init, '=', Constant(42))
# Should create a new VarDecl with initializer and bind '$x' in scope
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    # Simulate a VarDecl node with no initializer yet (from 'my $x')
    my $var_node = $factory->make('Constant', const_type => 'variable', value => '$x');
    my $vardecl = $typed->make('VarDecl',
        inputs       => [$var_node, undef],
        compat_class => 'VarDecl',
    );
    my $op_node   = $factory->make('Constant', const_type => 'string', value => '=');
    my $rhs_node  = $factory->make('Constant', const_type => 'integer', value => '42');

    # Build a parent context with leaves: [VarDecl, '=', 42], control_head carries Start.
    my $scope = Chalk::Bootstrap::Bindings->new();
    my $ctx = make_parent_ctx($scope, $factory->make('Start'),
        make_leaf_ctx($vardecl),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'AssignmentExpression', 0, 0, 0));
    ok(defined $result, 'VarDecl assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'result has an IR node');
    ok($node isa Chalk::IR::Node, 'result is an IR node');
    is($node->class(), 'VarDecl', 'result is a VarDecl');

    # Verify the scope was updated via scope field on result
    my $result_scope = $result->scope();
    ok(defined $result_scope, 'result context has scope');
    if (defined $result_scope) {
        my $x_binding = $result_scope->lookup('$x');
        ok(defined $x_binding, '$x is in scope after VarDecl assignment');
        is($x_binding, $node, '$x is bound to the VarDecl IR node');
    }
}

# --- Case 2: Plain variable reassignment updates scope ---
# AssignmentExpression(Constant(variable, '$x'), '=', Constant(2))
# Should create a VarDecl and bind '$x' in scope with the new VarDecl
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    # Simulate '$x = 2' — LHS is a raw variable Constant
    my $var_node  = $factory->make('Constant', const_type => 'variable', value => '$x');
    my $op_node   = $factory->make('Constant', const_type => 'string', value => '=');
    my $rhs_node  = $factory->make('Constant', const_type => 'integer', value => '2');

    # Pre-populate scope with existing $x binding (value 1)
    my $old_x = $factory->make('Constant', const_type => 'integer', value => '1');
    my $scope = Chalk::Bootstrap::Bindings->new()->define('$x', $old_x);

    my $ctx = make_parent_ctx($scope, $factory->make('Start'),
        make_leaf_ctx($var_node),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'AssignmentExpression', 0, 0, 0));
    ok(defined $result, 'plain assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'plain assignment: result has an IR node');
    ok($node isa Chalk::IR::Node, 'plain assignment: result is an IR node');
    # class() returns the typed operation 'Assign'. The action makes the node
    # via make('Assign') with no compat_class, so class() falls through to
    # operation() — the legacy 'BinaryExpr' compat_class is no longer set.
    is($node->class(), 'Assign', 'plain assignment: result is an Assign node');

    # Verify scope was updated with the Assign node
    my $result_scope = $result->scope();
    ok(defined $result_scope, 'plain assignment: result has scope');
    if (defined $result_scope) {
        my $x_binding = $result_scope->lookup('$x');
        ok(defined $x_binding, '$x is in scope after plain assignment');
        is($x_binding, $node, '$x binding is updated to the new VarDecl node');
        isnt($x_binding, $old_x, '$x binding is not the old value anymore');
    }
}

# --- Case 3: Compound assignment ($x += 5) updates scope ---
# AssignmentExpression(Constant(variable, '$x'), '+=', Constant(5))
# Should create a CompoundAssign and bind '$x' in scope
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $var_node  = $factory->make('Constant', const_type => 'variable', value => '$x');
    my $op_node   = $factory->make('Constant', const_type => 'string', value => '+=');
    my $rhs_node  = $factory->make('Constant', const_type => 'integer', value => '5');

    # Pre-populate scope
    my $old_x = $factory->make('Constant', const_type => 'integer', value => '0');
    my $scope = Chalk::Bootstrap::Bindings->new()->define('$x', $old_x);

    my $ctx = make_parent_ctx($scope, $factory->make('Start'),
        make_leaf_ctx($var_node),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'AssignmentExpression', 0, 0, 0));
    ok(defined $result, 'compound assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'compound assignment: result has an IR node');
    ok($node isa Chalk::IR::Node, 'compound assignment: result is an IR node');
    is($node->class(), 'CompoundAssign', 'compound assignment: result is a CompoundAssign');

    # Verify scope was updated with the CompoundAssign node
    my $result_scope = $result->scope();
    ok(defined $result_scope, 'compound assignment: result has scope');
    if (defined $result_scope) {
        my $x_binding = $result_scope->lookup('$x');
        ok(defined $x_binding, '$x is in scope after compound assignment');
        is($x_binding, $node, '$x binding is updated to the CompoundAssign node');
        isnt($x_binding, $old_x, '$x binding is not the old value anymore');
    }
}

# --- Case 4: Assignment with no scope — backward compat ---
# If no scope on context, AssignmentExpression should still produce a VarDecl/CompoundAssign
# but without crashing, and with no scope update
{

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(
        actions => $actions,
    );

    my $var_node = $factory->make('Constant', const_type => 'variable', value => '$y');
    my $op_node  = $factory->make('Constant', const_type => 'string', value => '=');
    my $rhs_node = $factory->make('Constant', const_type => 'integer', value => '99');

    # No scope on this context
    my $ctx = make_parent_ctx(undef, undef,
        make_leaf_ctx($var_node),
        make_leaf_ctx($op_node),
        make_leaf_ctx($rhs_node),
    );

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'AssignmentExpression', 0, 0, 0));
    ok(defined $result, 'no-scope assignment: on_complete returns a result');

    my $node = $result->extract();
    ok(defined $node, 'no-scope assignment: result has an IR node');
    is($node->class(), 'Assign', 'no-scope assignment: returns an Assign node');
}

done_testing();

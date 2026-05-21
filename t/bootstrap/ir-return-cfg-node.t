# ABOUTME: Tests that ReturnStatement action produces Chalk::IR::Node::Return CFG nodes.
# ABOUTME: Verifies Bootstrap::IR::NodeFactory::make_cfg and migration from Constructor:ReturnStmt.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Constant;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Actions;
use Chalk::Bootstrap::Context;
use Chalk::IR::Node::Return;

my $factory = Chalk::IR::NodeFactory->new();

# Helper: build a complete-annotated Context for multiply() calls.
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

# Helper: build a leaf Context wrapping an IR node
my sub make_leaf_ctx($node) {
    return Chalk::Bootstrap::Context->new(
        focus    => $node,
        children => [],
        position => 0,
        rule     => undef,
    );
}

# Helper: build a parent Context with children
my sub make_parent_ctx(@children) {
    return Chalk::Bootstrap::Context->new(
        focus    => undef,
        children => \@children,
        position => 0,
        rule     => undef,
    );
}

# ---- Test 1: Bootstrap::IR::NodeFactory has make_cfg ----
subtest 'Bootstrap::IR::NodeFactory has make_cfg' => sub {
    my $f = Chalk::IR::NodeFactory->new();

    ok($f->can('make_cfg'), 'factory has make_cfg method');

    my $start = $f->make('Start');
    my $val   = $f->make('Constant', const_type => 'string', value => 'result');
    my $ret   = $f->make_cfg('Return', inputs => [$start, $val]);

    ok(defined $ret, 'make_cfg Return returns a node');
    isa_ok($ret, 'Chalk::IR::Node::Return', 'make_cfg Return is Chalk::IR::Node::Return');
    is($ret->operation(), 'Return', 'operation is Return');
    is(scalar $ret->inputs()->@*, 2, 'Return has 2 inputs (control + value)');
    is($ret->inputs()->[0], $start, 'inputs[0] is the control node');
    is($ret->inputs()->[1], $val,   'inputs[1] is the value node');
};

# ---- Test 2: make_cfg Return nodes are always unique (CFG semantics) ----
subtest 'make_cfg Return nodes are always unique' => sub {
    my $f = Chalk::IR::NodeFactory->new();

    my $start = $f->make('Start');
    my $val   = $f->make('Constant', const_type => 'string', value => 'x');
    my $ret1  = $f->make_cfg('Return', inputs => [$start, $val]);
    my $ret2  = $f->make_cfg('Return', inputs => [$start, $val]);

    ok($ret1 != $ret2, 'two Return nodes with same inputs are distinct (CFG semantics)');
};

# ---- Test 3: ReturnStatement action produces Chalk::IR::Node::Return ----
subtest 'ReturnStatement action produces Chalk::IR::Node::Return' => sub {

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa      = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => $actions);

    my $return_kw = $factory->make('Constant', const_type => 'string', value => 'return');
    my $expr_val  = $factory->make('Constant', const_type => 'string', value => 'something');

    # Build context: [return_keyword, expression_value]
    my $ctx = make_parent_ctx(
        make_leaf_ctx($return_kw),
        make_leaf_ctx($expr_val),
    );

    # Set cfg_state with a control node
    my $scope   = Chalk::Bootstrap::Scope->new();
    my $start   = $factory->make('Start');
    $sa->set_cfg_state($ctx, { control => $start, scope => $scope });

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'ReturnStatement', 0, 0, 0));
    ok(defined $result, 'ReturnStatement multiply returns a result');

    my $node = $result->extract();
    ok(defined $node, 'result has an IR node');
    isa_ok($node, 'Chalk::IR::Node::Return', 'ReturnStatement produces Chalk::IR::Node::Return');
    is($node->operation(), 'Return', 'operation is Return');
    is(scalar $node->inputs()->@*, 2, 'Return node has 2 inputs (control + value)');
    is($node->inputs()->[1], $expr_val, 'Return value is the expression');
};

# ---- Test 4: ReturnStatement with bare return (no expression) ----
subtest 'ReturnStatement bare return produces Return with undef value' => sub {

    my $actions = Chalk::Bootstrap::Perl::Actions->new();
    my $sa      = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => $actions);

    # Only a return keyword, no following expression
    my $return_kw = $factory->make('Constant', const_type => 'string', value => 'return');
    my $ctx = make_parent_ctx(make_leaf_ctx($return_kw));

    my $scope = Chalk::Bootstrap::Scope->new();
    my $start = $factory->make('Start');
    $sa->set_cfg_state($ctx, { control => $start, scope => $scope });

    my $result = $sa->multiply($ctx, $make_complete->($ctx, 'ReturnStatement', 0, 0, 0));
    ok(defined $result, 'bare ReturnStatement multiply returns a result');

    my $node = $result->extract();
    ok(defined $node, 'result has an IR node');
    isa_ok($node, 'Chalk::IR::Node::Return', 'bare ReturnStatement produces Chalk::IR::Node::Return');
    is(scalar $node->inputs()->@*, 2, 'Return node has 2 inputs');
};

done_testing();

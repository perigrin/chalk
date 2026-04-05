# ABOUTME: Integration test: Shim translation works correctly when called directly.
# ABOUTME: Old NodeFactory shim activation is disabled until Phase 4 migrates isa checks.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::NodeFactory;
use Chalk::IR::Shim;

# --- Part 1: Shim translation (called directly, not through old factory) ---

my $nf = Chalk::IR::NodeFactory->new();

# Helper to create Constant nodes in the new factory
sub nconst ($val, $ct = 'string') {
    $nf->make('Constant', value => $val, const_type => $ct);
}

# BinaryExpr → Add
{
    my $op    = nconst('+');
    my $left  = nconst('1', 'integer');
    my $right = nconst('2', 'integer');
    my $node  = Chalk::IR::Shim::translate($nf, 'BinaryExpr',
        op => $op, left => $left, right => $right);

    isa_ok($node, 'Chalk::IR::Node::Add', 'Shim: BinaryExpr(+) → Add');
    isa_ok($node, 'Chalk::IR::Node::BinOp', 'Shim: Add isa BinOp');
    is($node->class(), 'BinaryExpr', 'Shim: class() compat');
    is($node->op_str(), '+', 'Shim: op_str()');
    is($node->left(), $left, 'Shim: left()');
    is($node->right(), $right, 'Shim: right()');
    is(scalar $node->inputs()->@*, 3, 'Shim: 3 inputs for migration compat');
}

# UnaryExpr → Not
{
    my $op      = nconst('!');
    my $operand = nconst('true');
    my $node    = Chalk::IR::Shim::translate($nf, 'UnaryExpr',
        op => $op, operand => $operand);

    isa_ok($node, 'Chalk::IR::Node::Not', 'Shim: UnaryExpr(!) → Not');
    is($node->class(), 'UnaryExpr', 'Shim: class() compat');
    is($node->operand(), $operand, 'Shim: operand()');
}

# MethodCallExpr → Call(method)
{
    my $invocant = nconst('$self');
    my $method   = nconst('foo');
    my $node     = Chalk::IR::Shim::translate($nf, 'MethodCallExpr',
        invocant => $invocant, method_name => $method, args => []);

    isa_ok($node, 'Chalk::IR::Node::Call', 'Shim: MethodCallExpr → Call');
    is($node->class(), 'MethodCallExpr', 'Shim: class() compat');
    is($node->dispatch_kind(), 'method', 'Shim: dispatch_kind');
}

# BuiltinCall → Call(builtin)
{
    my $name = nconst('push');
    my $node = Chalk::IR::Shim::translate($nf, 'BuiltinCall',
        name => $name, args => [nconst('x')]);

    isa_ok($node, 'Chalk::IR::Node::Call', 'Shim: BuiltinCall → Call');
    is($node->class(), 'BuiltinCall', 'Shim: class() compat');
    is($node->dispatch_kind(), 'builtin', 'Shim: dispatch_kind');
}

# Structural types return undef
{
    is(Chalk::IR::Shim::translate($nf, 'Program', statements => []),
        undef, 'Shim: Program not translated');
}

# --- Part 2: Old factory still produces Constructor (shim disabled) ---

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

my $op    = $f->make('Constant', const_type => 'string', value => '+');
my $left  = $f->make('Constant', const_type => 'integer', value => '1');
my $right = $f->make('Constant', const_type => 'integer', value => '2');
my $add   = $f->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);

isa_ok($add, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Old factory: BinaryExpr still Constructor (shim disabled)');
is($add->class(), 'BinaryExpr', 'Old factory: class() works');

done_testing();

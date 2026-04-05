# ABOUTME: Integration test: Shim translation works correctly when called directly.
# ABOUTME: Verifies activation gating: translate() only produces typed nodes when class is enabled.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::NodeFactory;
use Chalk::IR::Shim;

# Start with a clean activation state
Chalk::IR::Shim::reset_enabled();

# --- Part 1: Shim translation (called directly, with activation) ---

my $nf = Chalk::IR::NodeFactory->new();

# Helper to create Constant nodes in the new factory
sub nconst ($val, $ct = 'string') {
    $nf->make('Constant', value => $val, const_type => $ct);
}

# BinaryExpr — Add
{
    Chalk::IR::Shim::enable_class('BinaryExpr');
    my $op    = nconst('+');
    my $left  = nconst('1', 'integer');
    my $right = nconst('2', 'integer');
    my $node  = Chalk::IR::Shim::translate($nf, 'BinaryExpr',
        op => $op, left => $left, right => $right);

    isa_ok($node, 'Chalk::IR::Node::Add', 'Shim: BinaryExpr(+) produces Add');
    isa_ok($node, 'Chalk::IR::Node::BinOp', 'Shim: Add isa BinOp');
    is($node->class(), 'BinaryExpr', 'Shim: class() compat');
    is($node->op_str(), '+', 'Shim: op_str()');
    is($node->left(), $left, 'Shim: left()');
    is($node->right(), $right, 'Shim: right()');
    is(scalar $node->inputs()->@*, 3, 'Shim: 3 inputs for migration compat');
    Chalk::IR::Shim::reset_enabled();
}

# UnaryExpr — Not
{
    Chalk::IR::Shim::enable_class('UnaryExpr');
    my $op      = nconst('!');
    my $operand = nconst('true');
    my $node    = Chalk::IR::Shim::translate($nf, 'UnaryExpr',
        op => $op, operand => $operand);

    isa_ok($node, 'Chalk::IR::Node::Not', 'Shim: UnaryExpr(!) produces Not');
    is($node->class(), 'UnaryExpr', 'Shim: class() compat');
    is($node->operand(), $operand, 'Shim: operand()');
    Chalk::IR::Shim::reset_enabled();
}

# MethodCallExpr — Call(method)
{
    Chalk::IR::Shim::enable_class('MethodCallExpr');
    my $invocant = nconst('$self');
    my $method   = nconst('foo');
    my $node     = Chalk::IR::Shim::translate($nf, 'MethodCallExpr',
        invocant => $invocant, method_name => $method, args => []);

    isa_ok($node, 'Chalk::IR::Node::Call', 'Shim: MethodCallExpr produces Call');
    is($node->class(), 'MethodCallExpr', 'Shim: class() compat');
    is($node->dispatch_kind(), 'method', 'Shim: dispatch_kind');
    Chalk::IR::Shim::reset_enabled();
}

# BuiltinCall — Call(builtin)
{
    Chalk::IR::Shim::enable_class('BuiltinCall');
    my $name = nconst('push');
    my $node = Chalk::IR::Shim::translate($nf, 'BuiltinCall',
        name => $name, args => [nconst('x')]);

    isa_ok($node, 'Chalk::IR::Node::Call', 'Shim: BuiltinCall produces Call');
    is($node->class(), 'BuiltinCall', 'Shim: class() compat');
    is($node->dispatch_kind(), 'builtin', 'Shim: dispatch_kind');
    Chalk::IR::Shim::reset_enabled();
}

# Structural types return undef even when no class is enabled
{
    is(Chalk::IR::Shim::translate($nf, 'Program', statements => []),
        undef, 'Shim: Program not translated');
}

# --- Part 2: Old factory still produces Constructor for structural types ---

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

# Program is structural — never translated by the shim
my $prog = $f->make('Constructor', class => 'Program', statements => []);
isa_ok($prog, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Old factory: Program is Constructor (structural, not translated)');
is($prog->class(), 'Program', 'Old factory: class() works');

# BinaryExpr IS now default-enabled — produces typed Add
my $op    = $f->make('Constant', const_type => 'string', value => '+');
my $left  = $f->make('Constant', const_type => 'integer', value => '1');
my $right = $f->make('Constant', const_type => 'integer', value => '2');
my $add   = $f->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);
isa_ok($add, 'Chalk::IR::Node::Add',
    'Old factory: BinaryExpr produces typed Add (default-enabled)');
is($add->class(), 'BinaryExpr', 'Old factory: class() compat works');

done_testing();

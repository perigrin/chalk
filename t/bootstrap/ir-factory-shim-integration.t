# ABOUTME: Integration test: old NodeFactory produces new typed nodes via shim.
# ABOUTME: Verifies make('Constructor', class=>'X', ...) returns Chalk::IR::Node::* types.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;

Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

# BinaryExpr(+) produces typed Add node
my $op    = $f->make('Constant', const_type => 'string', value => '+');
my $left  = $f->make('Constant', const_type => 'integer', value => '1');
my $right = $f->make('Constant', const_type => 'integer', value => '2');
my $add   = $f->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);

isa_ok($add, 'Chalk::IR::Node::Add',   'BinaryExpr(+) produces Add');
isa_ok($add, 'Chalk::IR::Node::BinOp', 'Add isa BinOp');
is($add->class(),   'BinaryExpr', 'class() returns BinaryExpr for compat');
is($add->op_str(),  '+',          'op_str() works');
is($add->left(),    $left,        'left() accessor works');
is($add->right(),   $right,       'right() accessor works');
# Migration compat: 3 inputs preserved
is(scalar $add->inputs()->@*, 3, '3 inputs for compat');
is($add->inputs()->[0], $op, 'inputs[0] is op Constant');

# UnaryExpr(!) produces typed Not node
my $not_op  = $f->make('Constant', const_type => 'string', value => '!');
my $operand = $f->make('Constant', const_type => 'string', value => 'true');
my $not     = $f->make('Constructor', class => 'UnaryExpr',
    op => $not_op, operand => $operand);
isa_ok($not, 'Chalk::IR::Node::Not', 'UnaryExpr(!) produces Not');
is($not->class(),   'UnaryExpr', 'class() compat');
is($not->operand(), $operand,    'operand() accessor works');

# MethodCallExpr produces Call(method)
my $invocant = $f->make('Constant', const_type => 'variable', value => '$self');
my $method   = $f->make('Constant', const_type => 'string',   value => 'foo');
my $call     = $f->make('Constructor', class => 'MethodCallExpr',
    invocant => $invocant, method_name => $method, args => []);
isa_ok($call, 'Chalk::IR::Node::Call', 'MethodCallExpr produces Call');
is($call->class(),         'MethodCallExpr', 'class() compat');
is($call->dispatch_kind(), 'method',         'dispatch_kind');

# BuiltinCall produces Call(builtin)
my $bname   = $f->make('Constant', const_type => 'string', value => 'push');
my $bargs   = [$f->make('Constant', const_type => 'string', value => 'x')];
my $builtin = $f->make('Constructor', class => 'BuiltinCall',
    name => $bname, args => $bargs);
isa_ok($builtin, 'Chalk::IR::Node::Call', 'BuiltinCall produces Call');
is($builtin->class(),         'BuiltinCall', 'class() compat');
is($builtin->dispatch_kind(), 'builtin',     'dispatch_kind');

# Hash consing: same BinaryExpr produces same typed node
my $add2 = $f->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);
ok($add == $add2, 'Translated nodes are hash-consed');

# Structural types still produce old Constructor
my $program = $f->make('Constructor', class => 'Program', statements => []);
isa_ok($program, 'Chalk::Bootstrap::IR::Node::Constructor', 'Program still Constructor');
is($program->class(), 'Program', 'Program class unchanged');

# VarDecl translates to new type
my $var  = $f->make('Constant', const_type => 'variable', value => '$x');
my $init = $f->make('Constant', const_type => 'integer',  value => '0');
my $vd   = $f->make('Constructor', class => 'VarDecl',
    variable => $var, initializer => $init);
isa_ok($vd, 'Chalk::IR::Node::VarDecl', 'VarDecl translates');
is($vd->class(), 'VarDecl', 'class() compat');

done_testing();

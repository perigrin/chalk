# ABOUTME: Tests the shim activation API (enable_class/disable_class/is_enabled).
# ABOUTME: Verifies that the shim translates all computation classes by default.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::Shim;

# All computation types are enabled by default
ok(Chalk::IR::Shim::is_enabled('BinaryExpr'), 'BinaryExpr is enabled by default');
ok(Chalk::IR::Shim::is_enabled('VarDecl'),    'VarDecl is enabled by default');
ok(Chalk::IR::Shim::is_enabled('MethodCallExpr'), 'MethodCallExpr is enabled by default');
ok(Chalk::IR::Shim::is_enabled('BuiltinCall'), 'BuiltinCall is enabled by default');

# Program is not a computation type and is not in the shim
ok(!Chalk::IR::Shim::is_enabled('Program'), 'Program is not a shim class');

# BinaryExpr(+) produces typed Add via NodeFactory
{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $f = Chalk::Bootstrap::IR::NodeFactory->instance();
    my $op    = $f->make('Constant', const_type => 'string',  value => '+');
    my $left  = $f->make('Constant', const_type => 'integer', value => '1');
    my $right = $f->make('Constant', const_type => 'integer', value => '2');
    my $add = $f->make('Constructor', class => 'BinaryExpr',
        op => $op, left => $left, right => $right);

    isa_ok($add, 'Chalk::IR::Node::Add', 'BinaryExpr(+) produces Add');
    is($add->class(), 'BinaryExpr', 'class() compat preserved');
}

# disable_class/enable_class affect the shim API (does not affect NodeFactory)
Chalk::IR::Shim::disable_class('BinaryExpr');
ok(!Chalk::IR::Shim::is_enabled('BinaryExpr'), 'BinaryExpr can be disabled via shim API');

Chalk::IR::Shim::enable_class('BinaryExpr');
ok(Chalk::IR::Shim::is_enabled('BinaryExpr'), 'BinaryExpr can be re-enabled via shim API');

# Reset to default
Chalk::IR::Shim::reset_enabled();
ok(Chalk::IR::Shim::is_enabled('BinaryExpr'), 'BinaryExpr enabled after reset');

done_testing();

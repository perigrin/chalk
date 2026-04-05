# ABOUTME: Tests the shim activation mechanism (enable_class/disable_class).
# ABOUTME: Verifies that only enabled Constructor classes produce typed nodes.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::Shim;

# Start clean, then disable BinaryExpr to test the off→on transition
Chalk::IR::Shim::reset_enabled();
Chalk::IR::Shim::disable_class('BinaryExpr');

# With BinaryExpr disabled: produces Constructor
Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f = Chalk::Bootstrap::IR::NodeFactory->instance();

my $op = $f->make('Constant', const_type => 'string', value => '+');
my $left = $f->make('Constant', const_type => 'integer', value => '1');
my $right = $f->make('Constant', const_type => 'integer', value => '2');
my $add_old = $f->make('Constructor', class => 'BinaryExpr',
    op => $op, left => $left, right => $right);

isa_ok($add_old, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Disabled: BinaryExpr is Constructor');

# Re-enable BinaryExpr
Chalk::IR::Shim::enable_class('BinaryExpr');
ok(Chalk::IR::Shim::is_enabled('BinaryExpr'), 'BinaryExpr is enabled');
ok(!Chalk::IR::Shim::is_enabled('Program'), 'Program is not enabled');

# Need fresh factory to avoid cache hits from previous Constructor
Chalk::Bootstrap::IR::NodeFactory::reset_for_testing();
my $f2 = Chalk::Bootstrap::IR::NodeFactory->instance();

my $op2 = $f2->make('Constant', const_type => 'string', value => '+');
my $left2 = $f2->make('Constant', const_type => 'integer', value => '1');
my $right2 = $f2->make('Constant', const_type => 'integer', value => '2');
my $add_new = $f2->make('Constructor', class => 'BinaryExpr',
    op => $op2, left => $left2, right => $right2);

isa_ok($add_new, 'Chalk::IR::Node::Add',
    'After enable: BinaryExpr produces Add');
is($add_new->class(), 'BinaryExpr', 'class() compat works');

# Program still Constructor (not enabled)
my $prog = $f2->make('Constructor', class => 'Program', statements => []);
isa_ok($prog, 'Chalk::Bootstrap::IR::Node::Constructor',
    'Program still Constructor');

# Disable and verify
Chalk::IR::Shim::disable_class('BinaryExpr');
ok(!Chalk::IR::Shim::is_enabled('BinaryExpr'), 'BinaryExpr disabled');

# Reset for other tests
Chalk::IR::Shim::reset_enabled();

done_testing();

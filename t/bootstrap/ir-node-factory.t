# ABOUTME: Tests for Chalk::IR::NodeFactory hash consing and node creation.
# ABOUTME: Verifies make/make_cfg, deduplication, and CFG uniqueness.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;

my $f = Chalk::IR::NodeFactory->new();

# make() creates data nodes with hash consing
my $c1 = $f->make('Constant', value => '42', const_type => 'integer');
isa_ok($c1, 'Chalk::IR::Node::Constant');
is($c1->value(), '42', 'Constant value');

# Same arguments return same object (hash consing)
my $c2 = $f->make('Constant', value => '42', const_type => 'integer');
ok($c1 == $c2, 'identical Constants are same object');

# Different values produce different objects
my $c3 = $f->make('Constant', value => '99', const_type => 'integer');
ok($c1 != $c3, 'different Constants are different objects');

# BinOp nodes via make()
my $left  = $f->make('Constant', value => '1', const_type => 'integer');
my $right = $f->make('Constant', value => '2', const_type => 'integer');
my $add = $f->make('Add', inputs => [$left, $right]);
isa_ok($add, 'Chalk::IR::Node::Add');
isa_ok($add, 'Chalk::IR::Node::BinOp');
is($add->left(), $left, 'Add left is correct');
is($add->right(), $right, 'Add right is correct');

# Same Add is hash-consed
my $add2 = $f->make('Add', inputs => [$left, $right]);
ok($add == $add2, 'identical Add nodes are same object');

# make_cfg() creates unique CFG nodes
my $start1 = $f->make_cfg('Start');
my $start2 = $f->make_cfg('Start');
isa_ok($start1, 'Chalk::IR::Node::Start');
ok($start1 != $start2, 'CFG nodes are always unique');

# make_cfg with inputs
my $cond = $f->make('Constant', value => 'true', const_type => 'string');
my $if = $f->make_cfg('If', inputs => [$start1, $cond]);
isa_ok($if, 'Chalk::IR::Node::If');

# Proj with index
my $proj = $f->make_cfg('Proj', inputs => [$if], index => 0);
isa_ok($proj, 'Chalk::IR::Node::Proj');
is($proj->index(), 0, 'Proj index preserved');

# Return and Unwind
my $ret = $f->make_cfg('Return', inputs => [$start1, $c1]);
isa_ok($ret, 'Chalk::IR::Node::Return');
my $unw = $f->make_cfg('Unwind', inputs => [$start1, $c1]);
isa_ok($unw, 'Chalk::IR::Node::Unwind');

# Call node
my $call = $f->make('Call', dispatch_kind => 'builtin', name => 'push', inputs => [$c1]);
isa_ok($call, 'Chalk::IR::Node::Call');
is($call->dispatch_kind(), 'builtin');
is($call->name(), 'push');

# PadAccess and FieldAccess
my $pad = $f->make('PadAccess', targ => 0, varname => '$x');
isa_ok($pad, 'Chalk::IR::Node::PadAccess');
my $fa = $f->make('FieldAccess', field_index => 1, field_stash => 'Foo');
isa_ok($fa, 'Chalk::IR::Node::FieldAccess');

# Consumer registration
is(scalar $left->consumers()->@*, 1, 'left has 1 consumer (add)');
is($left->consumers()->[0], $add, 'left consumer is add');

done_testing();

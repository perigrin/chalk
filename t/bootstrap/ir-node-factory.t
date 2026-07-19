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

# make_unique() bypasses hash-consing entirely, even for data ops that would
# otherwise dedupe by content_hash. B::SoN's FromOptree scout walk (a
# throwaway pre-pass that detects loop-carried slot mutation) builds
# placeholder Constants that must stay independently identifiable by object
# identity ($after != $ph) -- if two placeholders with identical content
# hash-consed to ONE node, that mutation-detection would break silently.
my $ph1 = $f->make_unique('Constant', value => 'scout', const_type => 'string');
my $ph2 = $f->make_unique('Constant', value => 'scout', const_type => 'string');
isa_ok($ph1, 'Chalk::IR::Node::Constant');
ok($ph1 != $ph2, 'make_unique never hash-conses, even with identical content');

# make_unique() output is invisible to make()'s content-hash cache: a
# subsequent make() call with the same content builds yet another distinct
# object, never reusing $ph1/$ph2 -- proving make_unique never populates the
# content-hash cache key make() looks up.
my $consed = $f->make('Constant', value => 'scout', const_type => 'string');
ok($consed != $ph1 && $consed != $ph2,
    'make() never returns a make_unique-built node for matching content');

# make_unique() still registers consumers, same as make()/make_cfg().
my $unique_add = $f->make_unique('Add', inputs => [$ph1, $ph2]);
ok((grep { $_ == $unique_add } $ph1->consumers()->@*),
    'make_unique registers the new node as a consumer of its inputs');

done_testing();

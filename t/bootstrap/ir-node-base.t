# ABOUTME: Tests for Chalk::IR::Node base class.
# ABOUTME: Verifies id, inputs, consumers, stamp, operation, and content_hash.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;

# Base class exists and can be instantiated
my $node = Chalk::IR::Node->new(id => 'test_1');
isa_ok($node, 'Chalk::IR::Node');

# Fields have correct defaults
is($node->id(), 'test_1', 'id is set');
is_deeply($node->inputs(), [], 'inputs default to empty array');
is_deeply($node->consumers(), [], 'consumers default to empty array');
is($node->stamp(), undef, 'stamp defaults to undef');

# operation() is abstract — base class dies
eval { $node->operation() };
like($@, qr/must implement operation/, 'base operation() dies');

# Consumer tracking
my $producer = Chalk::IR::Node->new(id => 'p1');
my $consumer = Chalk::IR::Node->new(id => 'c1');
$producer->add_consumer($consumer);
is(scalar $producer->consumers()->@*, 1, 'add_consumer adds one');
is($producer->consumers()->[0]->id(), 'c1', 'consumer is correct node');

$producer->remove_consumer($consumer);
is(scalar $producer->consumers()->@*, 0, 'remove_consumer removes it');

# TWO CONSUMERS OF ONE ID (content-hashed ids collide: Analysis replaces a
# Coerce with a new one of the same content) are two consumers: removing
# the old one dropped the new one too, and a print's Coerce went missing
# from its operand's consumers.
{
    my $p   = Chalk::IR::Node->new(id => 'p2');
    my $old = Chalk::IR::Node->new(id => 'same');
    my $new = Chalk::IR::Node->new(id => 'same');
    $p->add_consumer($old);
    $p->add_consumer($new);
    $p->remove_consumer($old);
    is(scalar $p->consumers()->@*, 1, 'remove_consumer removes that node, not every node of its id');
    ok($p->consumers()->[0] == $new, '...and the one left is the other');
}

# Stamp can be set via constructor
my $stamped = Chalk::IR::Node->new(id => 's1', stamp => 'Int');
is($stamped->stamp(), 'Int', 'stamp is set from constructor');

# Stamp can be patched post-construction via set_stamp (mirrors
# set_control_in/set_representation's late-binding-setter style). A loop
# header Phi's stamp is only knowable after the body walk computes the
# back-edge value's stamp, so the producer patches it in after the fact.
my $late_stamped = Chalk::IR::Node->new(id => 's2');
is($late_stamped->stamp(), undef, 'stamp defaults to undef before set_stamp');
$late_stamped->set_stamp('Num');
is($late_stamped->stamp(), 'Num', 'set_stamp patches the stamp post-construction');

# class() returns compat_class when set
my $compat = Chalk::IR::Node->new(id => 'compat_1', compat_class => 'BinaryExpr');
is($compat->class(), 'BinaryExpr', 'class() returns compat_class when set');

# class() without compat_class — can't fully test on base (operation() dies)
# Tested via subclass: class() falls back to operation()
use Chalk::IR::Node::Start;
my $start = Chalk::IR::Node::Start->new(id => 'start_class_test');
is($start->class(), 'Start', 'class() falls back to operation() when no compat_class');

# class() with compat_class on a subclass overrides operation()
my $overridden = Chalk::IR::Node::Start->new(id => 'start_override', compat_class => 'BinaryExpr');
is($overridden->class(), 'BinaryExpr', 'class() returns compat_class on subclass when set');

done_testing();

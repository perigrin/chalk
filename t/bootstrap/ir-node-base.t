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
like($@, qr/Subclass must implement/, 'base operation() dies');

# Consumer tracking
my $producer = Chalk::IR::Node->new(id => 'p1');
my $consumer = Chalk::IR::Node->new(id => 'c1');
$producer->add_consumer($consumer);
is(scalar $producer->consumers()->@*, 1, 'add_consumer adds one');
is($producer->consumers()->[0]->id(), 'c1', 'consumer is correct node');

$producer->remove_consumer($consumer);
is(scalar $producer->consumers()->@*, 0, 'remove_consumer removes it');

# Stamp can be set via constructor
my $stamped = Chalk::IR::Node->new(id => 's1', stamp => 'Int');
is($stamped->stamp(), 'Int', 'stamp is set from constructor');

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

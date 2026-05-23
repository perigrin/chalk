# ABOUTME: Tests for Chalk::Scheduler::ScheduleMeta abstract base.
# ABOUTME: Verifies the base class exists, carries a $node ref, and is subclassable.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::Scheduler::ScheduleMeta;

my $node = Chalk::IR::Node->new(id => 'fake_1');

my $meta = Chalk::Scheduler::ScheduleMeta->new(node => $node);
isa_ok($meta, 'Chalk::Scheduler::ScheduleMeta', 'base ScheduleMeta instantiates');
is($meta->node(), $node, 'node reader returns the IR node');

# Constructor requires node param.
eval { Chalk::Scheduler::ScheduleMeta->new() };
ok($@, 'missing node param dies') or diag("got: '$@'");

done_testing();

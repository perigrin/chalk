# ABOUTME: Tests for Chalk::IR::Node->schedule_data field.
# ABOUTME: Lazy-init: undef by default, set via set_schedule_data, excluded from content_hash.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::IR::Node::Loop;
use Chalk::Scheduler::EagerPinning::Loop;

# Defaults to undef.
my $node = Chalk::IR::Node->new(id => 'n_1');
is($node->schedule_data, undef, 'schedule_data defaults undef');

# set_schedule_data populates the field.
my $loop = Chalk::IR::Node::Loop->new(id => 'loop_1');
my $sd   = Chalk::Scheduler::EagerPinning::Loop->new(node => $loop);
$loop->set_schedule_data($sd);
is($loop->schedule_data, $sd, 'set_schedule_data stores the meta');
isa_ok($loop->schedule_data, 'Chalk::Scheduler::EagerPinning::Loop');

# schedule_data is excluded from content_hash: two nodes with identical
# inputs but different schedule_data still hash-cons to the same node.
my $bare_a = Chalk::IR::Node::Loop->new(id => 'a');
my $bare_b = Chalk::IR::Node::Loop->new(id => 'b');
is($bare_a->content_hash, $bare_b->content_hash,
   'baseline: identical Loops content-hash equal');

my $sd_a = Chalk::Scheduler::EagerPinning::Loop->new(node => $bare_a, is_for_style => true);
$bare_a->set_schedule_data($sd_a);
is($bare_a->content_hash, $bare_b->content_hash,
   'schedule_data does not perturb content_hash');

done_testing();

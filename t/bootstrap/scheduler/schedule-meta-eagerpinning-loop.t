# ABOUTME: Tests for Chalk::Scheduler::EagerPinning::Loop schedule_data.
# ABOUTME: Carries iterator/list/is_for_style/for_init/for_step set by parser actions.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Node;
use Chalk::Scheduler::EagerPinning::Loop;

my $node = Chalk::IR::Node->new(id => 'loop_1');

# A plain Loop's ScheduleMeta with no extra info (e.g., bare `while`).
my $bare = Chalk::Scheduler::EagerPinning::Loop->new(node => $node);
isa_ok($bare, 'Chalk::Scheduler::EagerPinning::Loop');
isa_ok($bare, 'Chalk::Scheduler::ScheduleMeta', 'inherits from ScheduleMeta');
is($bare->iterator,    undef, 'iterator defaults undef');
is($bare->list,        undef, 'list defaults undef');
is($bare->is_for_style, false, 'is_for_style defaults false');
is($bare->for_init,    undef, 'for_init defaults undef');
is($bare->for_step,    undef, 'for_step defaults undef');

# A foreach: iterator + list populated.
my $iter = Chalk::IR::Node->new(id => 'iter_1');
my $list = Chalk::IR::Node->new(id => 'list_1');
my $foreach = Chalk::Scheduler::EagerPinning::Loop->new(
    node     => $node,
    iterator => $iter,
    list     => $list,
);
is($foreach->iterator, $iter, 'foreach iterator preserved');
is($foreach->list,     $list, 'foreach list preserved');
is($foreach->is_for_style, false, 'foreach is not for-style');

# A C-style for: is_for_style true + for_init/for_step.
my $init = Chalk::IR::Node->new(id => 'init_1');
my $step = Chalk::IR::Node->new(id => 'step_1');
my $cfor = Chalk::Scheduler::EagerPinning::Loop->new(
    node         => $node,
    is_for_style => true,
    for_init     => $init,
    for_step     => $step,
);
is($cfor->is_for_style, true, 'C-style for: is_for_style true');
is($cfor->for_init, $init, 'C-style for: for_init preserved');
is($cfor->for_step, $step, 'C-style for: for_step preserved');

done_testing();

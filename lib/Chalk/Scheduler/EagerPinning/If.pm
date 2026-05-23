# ABOUTME: EagerPinning-dialect ScheduleMeta for IR::Node::If.
# ABOUTME: Carries the `next`/`last` keyword when the If is a loop-jump shortcut.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::Scheduler::ScheduleMeta;

class Chalk::Scheduler::EagerPinning::If :isa(Chalk::Scheduler::ScheduleMeta) {
    field $is_loop_jump :param :reader = undef;
}

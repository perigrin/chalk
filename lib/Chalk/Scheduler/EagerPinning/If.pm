# ABOUTME: EagerPinning-dialect ScheduleMeta for IR::Node::If.
# ABOUTME: Carries the `next`/`last` keyword when the If is a loop-jump shortcut.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::Scheduler::ScheduleMeta;

class Chalk::Scheduler::EagerPinning::If :isa(Chalk::Scheduler::ScheduleMeta) {
    field $is_loop_jump :param :reader = undef;

    # Branch-body statements as captured by the parser. The current
    # IR does not chain-thread through If's true/false projections,
    # so the scheduler relies on these arrays to know what belongs
    # inside each branch. then_stmts is always an arrayref; else_stmts
    # is undef when the source had no else clause and an arrayref
    # (possibly empty) when it did, so the scheduler can tell the
    # difference between `if (X) {...}` and `if (X) {...} else {}`.
    field $then_stmts :param :reader = [];
    field $else_stmts :param :reader = undef;
}

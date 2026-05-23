# ABOUTME: EagerPinning-dialect ScheduleMeta for IR::Node::Loop.
# ABOUTME: Carries surface-syntax recovery hints set by parser actions.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::Scheduler::ScheduleMeta;

class Chalk::Scheduler::EagerPinning::Loop :isa(Chalk::Scheduler::ScheduleMeta) {
    field $iterator     :param :reader = undef;
    field $list         :param :reader = undef;
    field $is_for_style :param :reader = false;
    field $for_init     :param :reader = undef;
    field $for_step     :param :reader = undef;

    # Body statements as captured by the parser. The current IR does
    # not chain-thread through the Loop's body Proj, so the scheduler
    # relies on this array to know what belongs in the loop body.
    # Same pattern as EagerPinning::If's then_stmts/else_stmts.
    # Always an arrayref (possibly empty for empty-body loops).
    field $body_stmts :param :reader = [];
}

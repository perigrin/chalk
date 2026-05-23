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
}

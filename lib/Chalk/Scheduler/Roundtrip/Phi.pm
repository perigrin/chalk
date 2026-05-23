# ABOUTME: Roundtrip-dialect ScheduleMeta for IR::Node::Phi.
# ABOUTME: Carries emit_slot — the VarDecl whose surface identifier the Phi resolves to.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::Scheduler::ScheduleMeta;

class Chalk::Scheduler::Roundtrip::Phi :isa(Chalk::Scheduler::ScheduleMeta) {
    field $emit_slot :param :reader = undef;
}

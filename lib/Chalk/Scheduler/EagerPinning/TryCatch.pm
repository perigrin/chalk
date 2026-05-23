# ABOUTME: EagerPinning-dialect ScheduleMeta for IR::Node::TryCatch.
# ABOUTME: Carries catch_var plus the try/catch statement arrays set by TryStatement action.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::Scheduler::ScheduleMeta;

class Chalk::Scheduler::EagerPinning::TryCatch :isa(Chalk::Scheduler::ScheduleMeta) {
    field $catch_var   :param :reader = undef;
    field $try_stmts   :param :reader = [];
    field $catch_stmts :param :reader = [];
}

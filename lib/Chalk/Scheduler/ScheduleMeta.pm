# ABOUTME: Abstract base class for per-node scheduler interpretation metadata.
# ABOUTME: Each scheduler implementation owns its own subclass tree under Chalk::Scheduler::<Dialect>::*.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

class Chalk::Scheduler::ScheduleMeta {
    field $node :param :reader;
}

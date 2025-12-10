# ABOUTME: Global Code Motion optimization pass for Sea of Nodes IR
# ABOUTME: Schedules floating nodes optimally using early and late scheduling phases
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Optimizer::GCM {

    # Instance method for pipeline compatibility
    # Returns optimized graph (not a hashref)
    method apply($graph) {
        my $result = $self->run_gcm($graph);
        return $result->{graph};
    }

    # Run Global Code Motion optimization pass
    # Returns: { graph => graph, schedule => final_schedule, metrics => { ... } }
    method run_gcm($graph) {
        # Phase 1: Early scheduling - schedule nodes as early as possible
        # This places nodes at the deepest dominating control point of their inputs
        my $early_schedule = $graph->schedule_early();

        # Phase 2: Late scheduling - move nodes down to shallowest loop nest
        # This hoists loop-invariant code and minimizes register pressure
        my $late_schedule = $graph->schedule_late($early_schedule);

        # The schedule maps node_id => control_node_id
        # This determines where each floating node should be placed
        # For code generation, nodes would be emitted at their scheduled control points

        return {
            graph => $graph,
            schedule => $late_schedule,
            metrics => {
                scheduled_nodes => scalar(keys %{$late_schedule}),
            }
        };
    }
}

1;

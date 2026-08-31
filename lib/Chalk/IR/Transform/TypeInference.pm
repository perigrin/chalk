# ABOUTME: T1 -- type inference over one graph, target-independent.
# ABOUTME: Normalizes absences to Unknown at entry and reports what it found.
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util qw(blessed);
use Chalk::IR::Value;

class Chalk::IR::Transform::TypeInference {
    # THE REPORT (spec §9.4). Populated by run(); undef before the first one.
    #
    # `arrived_absent` is the FRONTEND metric and it is reported whether or not
    # T1 later types the node. That is the point: a node T1 successfully infers
    # is still evidence the producer failed to say anything about it, and
    # collapsing the two would make the frontend defect invisible the moment
    # inference got good enough to paper over it.
    field $report :reader = undef;

    # run($graph) -> $graph
    #
    # ONE GRAPH, not a set (spec §2). A graph reaches its siblings through the
    # MOP edge it already carries -- graph -> mop -> graphs -- so T1 needs no
    # hash passed alongside it.
    method run ($graph) {
        my $arrived_absent = _normalize_entry($graph);

        $report = {
            arrived_absent => $arrived_absent,
            # The remaining spec §9.4 fields land with step 3, which runs
            # TypedInvariant over stamps as part of the report. Declared here
            # as undef rather than omitted: an absent key and a key holding
            # "not measured" are different claims, and this file is where the
            # distinction is supposed to be enforced.
            unknown_at_exit       => undef,
            narrowed_count        => undef,
            widened_without_merge => undef,
        };

        return $graph;
    }

    # _normalize_entry($graph) -> count of nodes that ARRIVED ABSENT
    #
    # Spec §4: ABSENT and `Unknown` are different and must not be conflated.
    # `Unknown` is the lattice top, a real answer meaning "inference did not
    # determine this". An absence is a node nobody ever stamped, and it forces
    # every downstream consumer to invent its own meaning for undef -- which is
    # exactly how `$repr // 'Int'` guesses got written.
    #
    # So this does BOTH halves and neither alone is sufficient: it replaces the
    # absence (so no pass downstream sees undef) and counts it (so the frontend
    # defect stays measurable after the replacement hides it).
    sub _normalize_entry ($graph) {
        my $absent = 0;
        for my $node (($graph->nodes // [])->@*) {
            next unless blessed($node) && $node->isa('Chalk::IR::Value');
            next if defined $node->representation;
            $absent++;
            $node->set_representation('Unknown');
        }
        return $absent;
    }
}

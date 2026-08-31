# ABOUTME: T1 -- type inference over one graph, target-independent.
# ABOUTME: Normalizes absences to Unknown at entry and reports what it found.
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util qw(blessed);
use Chalk::IR::Value;
use Chalk::Grammar::Perl::TypeLibrary ();

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

        # SNAPSHOT BEFORE, so narrowing and widening are OBSERVED rather than
        # inferred from what the passes claim to have done. A pass that reports
        # its own effect is the shape that let a silent widening ship before.
        my %before = _stamp_snapshot($graph);

        # THE SEAM. Inference itself is still the loader's Analysis sequence;
        # step 4 moves the call to here. It is a named method rather than
        # nothing so the report is measured AROUND it -- when the body arrives,
        # the measurement does not have to be rewritten, and a test can
        # substitute a body today to prove the counters actually move.
        $self->_infer($graph);

        my %after = _stamp_snapshot($graph);

        my ($narrowed, $widened) = (0, 0);
        for my $id (sort keys %after) {
            my $was = $before{$id} // next;
            my $now = $after{$id};
            next if $was eq $now;
            # NARROWED: the new type is a subtype of the old -- more was
            # determined. WIDENED: the reverse, and spec §3/§9.3 forbid it
            # unless a merge required it. Counted, not refused: the number is
            # the finding.
            if (Chalk::Grammar::Perl::TypeLibrary::is_subtype($now, $was)) {
                $narrowed++;
            }
            elsif (Chalk::Grammar::Perl::TypeLibrary::is_subtype($was, $now)) {
                $widened++;
            }
        }

        $report = {
            arrived_absent        => $arrived_absent,
            unknown_at_exit       => _count_unknown($graph),
            narrowed_count        => $narrowed,
            widened_without_merge => $widened,
        };

        return $graph;
    }

    # _infer($graph) -> void. The inference body.
    #
    # EMPTY TODAY, deliberately and visibly. The loader still runs the Analysis
    # sequence inline (step 4 moves it here), so T1 currently normalizes and
    # measures without inferring. An empty method that is CALLED is honest
    # about that; folding it away would make the report's zeros look like
    # findings rather than like the absence of a body.
    method _infer ($graph) { return }

    # _stamp_snapshot($graph) -> (node id => repr) for every typed Value node.
    sub _stamp_snapshot ($graph) {
        my %seen;
        for my $node (($graph->nodes // [])->@*) {
            next unless blessed($node) && $node->isa('Chalk::IR::Value');
            my $r = $node->representation // next;
            $seen{ $node->id } = $r;
        }
        return %seen;
    }

    # _count_unknown($graph) -> Value nodes still holding the lattice top.
    #
    # This is the number spec §9.4 exists to surface, and it is REPORTED rather
    # than asserted. `_assert_value_nodes_are_typed` (Analysis.pm) is the
    # assertion version and it is commented out at its call site because 18
    # cases fail it -- a check that must be disabled to ship is not a check.
    # A count can be driven down deliberately; an all-or-nothing assertion can
    # only be switched off.
    sub _count_unknown ($graph) {
        my $n = 0;
        for my $node (($graph->nodes // [])->@*) {
            next unless blessed($node) && $node->isa('Chalk::IR::Value');
            my $r = $node->representation // next;
            $n++ if $r eq 'Unknown';
        }
        return $n;
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

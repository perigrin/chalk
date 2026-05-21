# ABOUTME: Dead Code Elimination pass for the optimizer pipeline.
# ABOUTME: Removes IR nodes unreachable from the root set. Accepts Graph or arrayref of roots.
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util qw(blessed);

use Chalk::Bootstrap::Optimizer::Pass;
use Chalk::IR::Graph;

class Chalk::Bootstrap::Optimizer::DCE :isa(Chalk::Bootstrap::Optimizer::Pass) {

    method name() { return 'DCE' }

    # DCE operates on a single computation graph at a time. The Phase 5
    # contract is run($graph) -> $graph. The legacy arrayref-of-roots
    # form remains accepted for back-compat with callers that haven't
    # migrated yet.
    method scope() { return 'graph' }

    method run($input, $factory) {
        # Polymorphic on input shape:
        #   - Chalk::IR::Graph: treat the graph's reachable nodes as
        #     roots; returns the same graph after pruning.
        #   - arrayref of nodes (legacy): treat as the root set; returns
        #     the same arrayref.
        #
        # $factory: required. The Chalk::IR::NodeFactory whose cache DCE
        # walks for its sweep and evict phases.
        my $is_graph = defined($input) && blessed($input)
            && $input isa Chalk::IR::Graph;
        my $is_roots_array = !$is_graph
            && defined($input) && ref($input) eq 'ARRAY';

        die "run() requires a Chalk::IR::Graph or an arrayref of IR roots"
            unless $is_graph || $is_roots_array;

        my $roots = $is_graph ? $input->nodes() : $input;

        # Mark: collect all reachable node IDs via iterative worklist
        my %reachable;
        $self->_mark_reachable($roots, \%reachable);

        # Sweep: find dead nodes (in cache but not reachable)
        my @dead_ids;
        for my $id ($factory->all_node_ids()->@*) {
            push @dead_ids, $id unless $reachable{$id};
        }

        # Cleanup: remove dead nodes from consumer lists of their inputs
        for my $dead_id (@dead_ids) {
            my $dead_node = $factory->get_node($dead_id);
            next unless defined $dead_node;

            for my $input ($dead_node->inputs()->@*) {
                next unless defined $input;
                if (ref($input) eq 'ARRAY') {
                    for my $element ($input->@*) {
                        $element->remove_consumer($dead_node) if defined $element;
                    }
                }
                else {
                    $input->remove_consumer($dead_node);
                }
            }
        }

        # Evict: delete dead nodes from factory cache
        for my $dead_id (@dead_ids) {
            $factory->remove_node($dead_id);
        }

        return $input;
    }

    # Walk roots and all transitive inputs, collecting reachable node IDs
    # Uses iterative worklist to avoid stack overflow on deep graphs
    method _mark_reachable($roots, $reachable) {
        my @worklist = grep { defined } $roots->@*;

        while (my $node = shift @worklist) {
            next if $reachable->{$node->id()};
            $reachable->{$node->id()} = true;

            for my $input ($node->inputs()->@*) {
                next unless defined $input;
                if (ref($input) eq 'ARRAY') {
                    push @worklist, grep { defined } $input->@*;
                }
                else {
                    push @worklist, $input;
                }
            }
        }
    }
}

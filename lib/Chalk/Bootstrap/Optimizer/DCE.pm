# ABOUTME: Dead Code Elimination pass for the optimizer pipeline.
# ABOUTME: Removes IR nodes unreachable from the root set (Constructor:Rule nodes).
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::Bootstrap::Optimizer::Pass;
use Chalk::Bootstrap::IR::NodeFactory;

class Chalk::Bootstrap::Optimizer::DCE :isa(Chalk::Bootstrap::Optimizer::Pass) {

    method name() { return 'DCE' }

    method run($ir) {
        die "run() requires an arrayref of IR roots"
            unless defined($ir) && ref($ir) eq 'ARRAY';

        my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

        # Mark: collect all reachable node IDs via iterative worklist
        my %reachable;
        $self->_mark_reachable($ir, \%reachable);

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

        return $ir;
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

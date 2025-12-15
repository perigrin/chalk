# ABOUTME: Optimization pipeline for composing multiple IR optimization passes
# ABOUTME: Enables chaining and reordering of optimizations like GVN, constant folding, etc.

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::OptimizerPipeline {

    field $optimizers :param :reader;

    # Apply all optimizers in sequence to a graph
    # Returns the final optimized graph
    method apply($graph) {
        my $current_graph = $graph;

        for my $optimizer ($optimizers->@*) {
            # All optimizers must implement the apply() method
            $current_graph = $optimizer->apply($current_graph);
        }

        return $current_graph;
    }
}

1;

# ABOUTME: Abstract base class for optimizer passes.
# ABOUTME: Subclasses implement name(), scope(), and run($X) -> $X for their scope level.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Optimizer::Pass {
    method name() {
        die "Subclass must implement name()";
    }

    # The scope at which this pass operates. Returns either:
    #   - 'graph': pass takes a Chalk::IR::Graph and returns one. The
    #     pipeline iterates the MOP and invokes the pass once per
    #     method/sub graph.
    #   - 'mop':   pass takes the whole Chalk::MOP and returns one.
    #
    # Per Phase 5, every concrete Pass must declare scope() so the
    # pipeline orchestrator can pick the right argument shape.
    method scope() {
        die "Subclass must implement scope()";
    }

    method run($input) {
        die "Subclass must implement run()";
    }
}

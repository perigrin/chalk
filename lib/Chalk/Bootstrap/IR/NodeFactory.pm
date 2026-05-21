# ABOUTME: Back-compat shim around Chalk::IR::NodeFactory for legacy callers.
# ABOUTME: Production code uses Chalk::IR::NodeFactory directly; this shim
# ABOUTME: preserves the singleton API for ~120 test files still calling
# ABOUTME: instance()/reset_for_testing(). Delegate-only; no own state.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::NodeFactory;

class Chalk::Bootstrap::IR::NodeFactory {

    # Singleton instance — created lazily; cleared by reset_for_testing.
    # Holds a Chalk::IR::NodeFactory and forwards every operation to it.
    my $instance;

    # The wrapped per-instance typed factory.
    field $_typed;

    ADJUST {
        $_typed = Chalk::IR::NodeFactory->new();
    }

    # Get singleton instance. Lazily allocates a fresh one if reset.
    sub instance {
        $instance //= Chalk::Bootstrap::IR::NodeFactory->new;
        return $instance;
    }

    # Reset singleton for testing. Next instance() call gets a fresh
    # typed factory underneath, which means CFG counters and the
    # hash-cons cache start over.
    sub reset_for_testing {
        $instance = undef;
        return;
    }

    # Permissive node construction — delegates to the typed factory's
    # make() which accepts every op Bootstrap's make() historically
    # accepted (Constants/Start/Return/Unwind hash-consed, If/Proj/
    # Region/Loop/Phi allocated fresh with cfg-counter ids, named
    # input-keyword translation via %INPUT_SPECS).
    method make($operation, %params) {
        return $_typed->make($operation, %params);
    }

    # CFG-node construction with fresh allocation per call.
    method make_cfg($operation, %params) {
        return $_typed->make_cfg($operation, %params);
    }

    # Cache-inspection API used by passes that walk all data nodes.
    method node_count()    { return $_typed->node_count }
    method all_node_ids()  { return $_typed->all_node_ids }
    method get_node($id)   { return $_typed->get_node($id) }
    # Bootstrap historically protected the hash-cons invariant by dying
    # when remove_node was called on a node with consumers. Preserve that
    # behavior here; the typed factory's remove_node is permissive.
    method remove_node($id) {
        my $node = $_typed->get_node($id);
        if (defined $node && scalar($node->consumers()->@*) > 0) {
            die "Cannot remove node '$id' that still has consumers";
        }
        return $_typed->remove_node($id);
    }
}

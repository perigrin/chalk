# ABOUTME: Legacy base class for Bootstrap IR nodes in the Sea of Nodes representation.
# ABOUTME: Inherits from Chalk::IR::Node; kept for backward compat with Bootstrap subclasses.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

# Migration bridge: inheriting from Chalk::IR::Node ensures Bootstrap nodes
# pass `isa Chalk::IR::Node` checks in Actions.pm and related modules.
# Bootstrap subclasses (Constant, Constructor, etc.) continue to use this
# as their immediate parent without modification.
class Chalk::Bootstrap::IR::Node :isa(Chalk::IR::Node) {

    # Abstract method - subclasses must implement
    method operation() {
        die "Subclass must implement operation()";
    }
}

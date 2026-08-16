# ABOUTME: Backtick (shell command) expression node in the Chalk IR.
# ABOUTME: Represents a backtick or qx// expression that captures shell output.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::BacktickExpr :isa(Chalk::IR::Node) {
    method operation() { 'BacktickExpr' }
    method staleness_kind() { 'opaque' }

    # FIXED: qx// runs a command: a host-process effect
    method is_fixed() { return true }
}

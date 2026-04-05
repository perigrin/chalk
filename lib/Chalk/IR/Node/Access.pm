# ABOUTME: Empty base class for all access IR nodes in the Chalk Sea of Nodes graph.
# ABOUTME: Groups PadAccess, FieldAccess, StashAccess, and Subscript under a common type.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Access :isa(Chalk::IR::Node) {
}

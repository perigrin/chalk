# ABOUTME: Intermediate base class for aggregate constructor IR nodes.
# ABOUTME: Groups HashRef, ArrayRef, and Interpolate nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Aggregate :isa(Chalk::IR::Node) {
}

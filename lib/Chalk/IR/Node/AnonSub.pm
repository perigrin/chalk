# ABOUTME: Anonymous subroutine (closure) node in the Chalk IR.
# ABOUTME: Holds a nested Chalk::IR::Graph for the sub body.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::AnonSub :isa(Chalk::IR::Node) {
    field $graph :param :reader = undef;

    method operation() { 'AnonSub' }
}

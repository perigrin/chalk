# ABOUTME: The exceptional way out of a node that may die (wire v2's `eval` profile): a control
# ABOUTME: node whose one input is that node; its value is the exception in flight.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

# What follows an Exc (control_in) runs only when its node died: the restores
# of the `local`s live there, then the eval's catch Region.
class Chalk::IR::Node::Exc :isa(Chalk::IR::Node) {
    method operation() { 'Exc' }
    method staleness_kind() { 'opaque' }
}

1;

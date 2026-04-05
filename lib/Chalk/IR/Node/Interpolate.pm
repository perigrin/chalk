# ABOUTME: String interpolation node in the Chalk IR.
# ABOUTME: Represents a double-quoted string assembled from literal and variable parts.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Aggregate;

class Chalk::IR::Node::Interpolate :isa(Chalk::IR::Node::Aggregate) {
    method operation() { 'Interpolate' }
}

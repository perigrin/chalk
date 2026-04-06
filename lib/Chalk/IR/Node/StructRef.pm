# ABOUTME: Struct reference constructor from the StructPromotion optimizer.
# ABOUTME: Represents a promoted hash-to-struct with a named schema and field values.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Node;

class Chalk::IR::Node::StructRef :isa(Chalk::IR::Node) {
    method operation() { 'StructRef' }
}

# ABOUTME: IR node representing compile-time constant values
# ABOUTME: Stores const_type ('string', 'integer', 'enum') and value
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::IR::Node::Constant :isa(Chalk::Bootstrap::IR::Node) {
    # Type of constant: 'string', 'integer', or 'enum'
    field $const_type :param :reader;

    # The actual constant value
    field $value :param :reader;

    method operation() {
        return 'Constant';
    }
}

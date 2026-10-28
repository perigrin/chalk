# ABOUTME: Intermediate base class for aggregate constructor IR nodes.
# ABOUTME: Groups HashRef, ArrayRef, and Interpolate nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::Aggregate :isa(Chalk::IR::Value) {
    # The variable a literal is the contents of, as B::SoN names it: `@x`'s
    # `x`, a package one's `@main::x`. Undef when the wire names none.
    field $symbol :param :reader = undef;
}

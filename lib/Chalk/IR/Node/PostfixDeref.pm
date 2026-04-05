# ABOUTME: Postfix dereference node in the Chalk IR.
# ABOUTME: Carries the sigil (@, %, $) indicating the dereference type.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::PostfixDeref :isa(Chalk::IR::Node) {
    field $sigil :param :reader;

    method operation() { 'PostfixDeref' }

    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        return "PostfixDeref|sigil=" . $sigil . "|" . join('|', @input_ids);
    }
}

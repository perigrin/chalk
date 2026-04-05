# ABOUTME: Anonymous subroutine (closure) node in the Chalk IR.
# ABOUTME: Holds a nested Chalk::IR::Graph for the sub body.
use 5.42.0;
use utf8;
use experimental 'class';

use Scalar::Util 'refaddr';
use Chalk::IR::Node;

class Chalk::IR::Node::AnonSub :isa(Chalk::IR::Node) {
    field $graph :param :reader = undef;

    method operation() { 'AnonSub' }

    # Each anonymous sub is semantically unique (different closure body),
    # so include the graph identity to prevent incorrect deduplication.
    method content_hash() {
        my @input_ids = map { $_->id() } $self->inputs()->@*;
        my $graph_id = defined $graph ? (refaddr($graph) // "$graph") : 'none';
        return "AnonSub|graph=" . $graph_id . "|" . join('|', @input_ids);
    }
}

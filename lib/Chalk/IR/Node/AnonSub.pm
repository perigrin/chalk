# ABOUTME: Anonymous subroutine (closure) node in the Chalk IR.
# ABOUTME: Holds a nested Chalk::IR::Graph for the sub body.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::AnonSub :isa(Chalk::IR::Node) {
    # Deterministic counter for unique AnonSub identity
    my $anon_counter = 0;

    field $graph    :param :reader = undef;
    field $anon_id  :reader;

    ADJUST {
        $anon_id = $anon_counter++;
    }

    method operation() { 'AnonSub' }

    # Each anonymous sub is semantically unique (different closure body),
    # so include a sequential counter to prevent incorrect deduplication.
    method content_hash() {
        my @input_ids = map { defined($_) ? $_->id() : 'undef' } $self->inputs()->@*;
        return "AnonSub|anon_id=" . $anon_id . "|" . join('|', @input_ids);
    }
}

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
    method staleness_kind() { 'opaque' }

    # per_call, achieved by a THIRD mechanism: this class routes down make()'s
    # hash-consing branch (it is in none of the per-call tables) but defeats
    # the dedup from inside, by baking $anon_id into content_hash. The observed
    # behaviour is per-call, so that is what this reports — identity_kind
    # describes what make() DOES, not which branch it took.
    sub identity_kind { 'per_call' }

    # Each anonymous sub is semantically unique (different closure body),
    # so include a sequential counter to prevent incorrect deduplication.
    method content_hash() {
        return join('|', 'AnonSub', "anon_id=$anon_id", $self->_serialize_inputs());
    }
}

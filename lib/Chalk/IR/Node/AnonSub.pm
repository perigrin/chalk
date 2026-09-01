# ABOUTME: Anonymous subroutine (closure) node in the Chalk IR.
# ABOUTME: Holds a nested Chalk::IR::Graph for the sub body.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::AnonSub :isa(Chalk::IR::Value) {
    field $graph    :param :reader = undef;

    # The body's `methods` key: `<enclosing>::__ANON__:<line>:<targ>`.
    #
    # THIS IS THE NODE'S IDENTITY. A non-capturing anon sub has ONE CV PER
    # SITE, not one per evaluation -- measured against perl 5.42.0:
    #
    #   map { sub { 7 } } (1,2,3)          1 distinct CV
    #   for (1..3) { push @r, sub {7} }    1 distinct CV
    #   sub mk { sub {7} } (mk(), mk())    SHARED, across CALL FRAMES
    #
    # so the name picks out exactly what perl treats as one CV, and two
    # AnonSubs with the same name ARE the same sub.
    #
    # Undef for a graph built in-process by the frontend, which has no wire
    # name; such a node falls back to per-node identity below.
    field $name :param :reader = undef;

    # Fallback identity for a nameless (frontend-built) AnonSub. Two distinct
    # anon subs must not merge just because their bodies match -- two
    # capturing subs with identical bodies are different VALUES -- so a
    # nameless node stays per-node. A named one does not need this.
    my $anon_counter = 0;
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

    # Keyed on the NAME when there is one: the name encodes the site, the site
    # is the identity, and merging two same-named AnonSubs is what perl itself
    # does rather than merely being harmless.
    #
    # anon_id stood here alone until the name reached the wire, and it had
    # three defects the name closes:
    #
    #   1. It is a PROCESS-GLOBAL CONSTRUCTION COUNTER and is NOT serialized,
    #      so a reloaded AnonSub hashed differently from the graph that wrote
    #      it. Measured: loading one document twice in one process gave
    #      anon_id=0 then anon_id=2 for the same node.
    #   2. It varied with how many AnonSubs were built earlier in the process,
    #      i.e. with load order across documents -- a determinism hazard
    #      against the byte-identical-codegen requirement.
    #   3. Uniqueness came from counting rather than from anything about the
    #      sub.
    #
    # It survives as the fallback for a frontend-built node with no name,
    # where per-node identity is still the safe answer: a body-only hash would
    # merge two capturing subs with identical bodies, which are different
    # values.
    method content_hash() {
        my $identity = defined $name ? "name=$name" : "anon_id=$anon_id";
        return join('|', 'AnonSub', $identity, $self->_serialize_inputs());
    }
}

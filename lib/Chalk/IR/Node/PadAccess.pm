# ABOUTME: IR node for accessing a lexical pad slot by target index and variable name.
# ABOUTME: Used to represent $x, @arr, %hash style variable reads in the Sea of Nodes graph.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

class Chalk::IR::Node::PadAccess :isa(Chalk::IR::Node::Access) {
    field $targ   :param :reader;

    # The sigil and the bare symbol are carried SEPARATELY, matching the wire
    # and perl's own terms: the symbol table is sigil-free and the sigil selects
    # a slot within the glob, so `symbol` is 'x', never '$x'.
    #
    # Both are required. A sigil-less variable lookup is not expressible, for
    # the same reason it is not expressible on EntryDef: `_` alone names the
    # scalar `$_`, the array `@_`, and the `-f _` filetest handle, and a
    # name-only identity hash-cons collapses unrelated variables into one node.
    field $sigil  :param :reader;
    field $symbol :param :reader;
    # A FILE LEXICAL SHARED WITH A NAMED SUB (B::SoN `shared`): one variable
    # read and written from several graphs, so a location reached through
    # memory rather than an SSA value. Its symbol is unique in the program
    # (the producer spells a second of one name apart).
    field $shared :param :reader = 0;

    method operation() { 'PadAccess' }
    sub identity_kind { q(hash_consed) }

    # A SCALAR THAT IS A LOCATION is read and stored through memory, not
    # bound as an SSA value: a shared file lexical, or a `my $x` the producer
    # keeps in memory (handed to a call, so `@_` aliases it) -- its input is
    # then a memory version, not a VarDecl. The producer spells a second of
    # one name in one sub apart, so (graph, symbol) names the variable.
    method is_location() {
        return 0 unless $sigil eq '$';
        return 1 if $shared;
        my $in = $self->inputs->[0];
        return ( defined $in && $in->can('operation') && $in->operation ne 'VarDecl' ) ? 1 : 0;
    }

    # The qualified spelling, composed in ONE place. Consumers comparing against
    # a sigil-carrying string ('$self', a signature parameter name) read this
    # rather than re-joining the halves, because a site that composes it itself
    # and is later missed fails SILENTLY -- the comparison simply stops matching.
    method name() { $sigil . $symbol }

    method content_hash() {
        # Identity is the qualified variable name plus inputs. `targ` (the
        # pad-slot index) is CV-local and unstable across compilation units, so
        # it is NOT identity-bearing: two semantically identical reads at
        # different pad indices must hash-cons together. `targ` is retained as a
        # field for diagnostics / round-trip only (no consumer reads it
        # behaviorally; PadAccess resolves to its VarDecl via inputs[0]).
        return join('|', 'PadAccess', 'name=' . $self->name(),
            ($shared ? 'shared' : ()), $self->_serialize_inputs());
    }
}

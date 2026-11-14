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
    # ...and of those, the FILE's (B::SoN `file`): the program's own, or one a
    # named sub reaches out to -- not a sub's own aggregate a closure captures.
    field $file :param :reader = 0;

    method operation() { 'PadAccess' }

    # memory_operand -> a variable kept in memory is read at its input's version.
    method memory_operand() { return $self->is_location ? $self->inputs->[0] : undef }
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

    # is_my_hash -> true for A `my %h` NAMED, NOT MADE HERE (`my %e;`): one hash
    # per variable, made at its function's entry. A shared one is read at a
    # memory version, and is still the one hash.
    method is_my_hash() { return ( $sigil // '' ) eq '%' && ( !$self->inputs->@* || $shared ) }

    # is_my_array -> true for A `my @a` NAMED, NOT MADE HERE: an array declared
    # once in its sub (one declared in a loop body or an arm is an ArrayLiteral
    # pinned there, made each time).
    method is_my_array() { return ( $sigil // '' ) eq '@' && ( !$self->inputs->@* || $shared ) }

    # is_named_hash -> a `my %h` is a named hash.
    method is_named_hash() { return $self->is_my_hash }

    # is_assign_target -> true where this `my` is named as an assign's target
    # -- a list assign's, or a scalar one's (B::SoN versions it by the memory
    # before that assign): a write, not a read.
    method is_assign_target() {
        return scalar grep {
            my $asg = $_;
            blessed($asg) && $asg->operation eq 'Assign'
                && grep { blessed($_) && refaddr($_) == refaddr($self) }
                        $asg->inputs->@[ 0 .. ( $asg->can('targets') && defined $asg->targets ? $asg->targets - 1 : 0 ) ]
        } $self->consumers->@*;
    }
}

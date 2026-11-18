# ABOUTME: Assignment operation node in the Chalk IR.
# ABOUTME: Binary data node wrapping the = operator.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::BinOp;

class Chalk::IR::Node::Assign :isa(Chalk::IR::Node::BinOp) {
    method operation() { 'Assign' }

    # A MEMORY VERSION: a store (a read after it reads at it).
    method is_memory_version() { return 1 }
    method staleness_kind() { 'opaque' }

    # FIXED: a store: it writes, so it is pinned to a point in the chain
    method is_fixed() { return true }
    method op_str()    { '=' }

    # A LIST assignment's target count: inputs[0 .. targets-1] are the
    # targets, the rest the values. Undef for a scalar assign. In the content
    # hash, since Assign(a, b, c) means a different store for 1 than for 2.
    # A `local` store: perl puts the old value back when its scope ends.
    field $local :param :reader = 0;
    field $targets :param :reader = undef;

    # is_placed -> true where this store is on the control chain AND every
    # read of an array or hash it fills comes after it: the read (or what it
    # is made into) is on the chain after this assign, or reads memory at a
    # version that is (this assign's, one after it, a merge's after it).
    # B::SoN leaves some list assigns off the chain, or on it with later reads
    # still at the memory before (`my ($f, @rest) = (1, 2, 3)`; `($x, @r) =
    # f()`): not placed -- a reader ordering itself by its memory would read
    # the array before it is filled.
    method is_placed() {
        return 0 unless $self->is_pinned;
        # (what control reaches from here, as Region::reached_by walks it)
        my ( %after, @q );
        @q = ($self);
        while ( defined( my $n = shift @q ) ) {
            next if $after{ refaddr($n) }++;
            push @q, grep { blessed($_) && ( $_->operation eq 'Region'
                            || ( $_->can('control_in') && blessed( $_->control_in ) && refaddr( $_->control_in ) == refaddr($n) )
                            || $_->operation eq 'Proj' && $n->operation =~ /\A(?:If|Loop)\z/ && blessed( $_->inputs->[0] ) && refaddr( $_->inputs->[0] ) == refaddr($n) ) }
                ( $n->consumers // [] )->@*;
        }
        my %seen;
        my $comes_after;
        $comes_after = sub ($u) {
            return 1 if !blessed($u) || $seen{ refaddr($u) }++ || $after{ refaddr($u) };
            return 0 if $u->operation eq 'MemStart';
            return $u->is_memory ? ( blessed( $u->region ) && $after{ refaddr( $u->region ) } ? 1 : 0 )
                                 : !grep { !$comes_after->($_) } ( $u->consumers // [] )->@*
                if $u->operation eq 'Phi';
            return 0 if $u->is_pinned;   # (on the chain, and not after)
            my $m = $u->memory_operand;
            return $comes_after->($m) if blessed($m);
            return !grep { !$comes_after->($_) } ( $u->consumers // [] )->@*;
        };
        return !grep { !$comes_after->($_) }
            map { ( $_->consumers // [] )->@* }
            grep { blessed($_) && $_->operation eq 'PadAccess' && ( $_->sigil // '' ) ne '$' }
            $self->inputs->@[ 0 .. ( $targets // 1 ) - 1 ];
    }
    method content_hash() {
        return join('|', 'Assign', (defined $targets ? "targets=$targets" : ()), ($local ? 'local' : ()),
            $self->_serialize_inputs());
    }

    # is_args_list_assign -> true for `my (...) = @_`: a list assign from the
    # arguments.
    method is_args_list_assign() {
        return defined $targets && blessed( $self->inputs->[-1] ) && $self->inputs->[-1]->operation eq 'ArgsSource';
    }
}

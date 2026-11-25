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
    # A BINDING RECORD, NOT A STORE (wire v2 `record`): off both chains, it
    # names what a `my` list is bound to; nothing runs it.
    field $record :param :reader = 0;

    method content_hash() {
        return join('|', 'Assign', (defined $targets ? "targets=$targets" : ()), ($local ? 'local' : ()),
            $self->_serialize_inputs());
    }

    # is_args_list_assign -> true for `my (...) = @_`: a list assign from the
    # arguments.
    method is_args_list_assign() {
        # ( ON THE RIGHT, after the targets: `@_ = ()` stores  itself)
        return defined $targets && $self->inputs->@* > $targets
            && blessed( $self->inputs->[-1] ) && $self->inputs->[-1]->operation eq 'ArgsSource';
    }
}

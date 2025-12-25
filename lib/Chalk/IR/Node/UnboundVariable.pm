# ABOUTME: IR node for unbound variable references - preserves name for later resolution
# ABOUTME: Used when variable not in scope; can be resolved to Parm or error in strict mode
use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Type::Integer;

class Chalk::IR::Node::UnboundVariable {
    field $name :param :reader;           # Variable name with sigil (e.g., '$x')
    field $source_info :param :reader = undef;
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method op() { 'UnboundVariable' }

    method inputs() { [] }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'UnboundVariable',
            inputs => [],
            attributes => {
                name => $name,
            },
        };
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    # Type is unknown until resolved
    method type() {
        use Chalk::Grammar::Chalk::Type::Any;
        return Chalk::Grammar::Chalk::Type::Any->new();
    }

    method compute_type() {
        return $self->type();
    }

    # Type inference for peephole - return unknown integer type
    method compute() {
        return Chalk::IR::Type::Integer->TOP();
    }

    # For strict mode: this would be fatal at compile/execution time
    # For now, just provide a way to check
    method is_unbound() { 1 }

    # Placeholder execute - in strict mode this should error
    method execute($context) {
        die "UnboundVariable: variable '$name' used but not declared (strict mode)";
    }

    # Peephole: UnboundVariable can't be optimized
    method peephole($graph = undef) {
        return $self;
    }
}

1;

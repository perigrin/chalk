# ABOUTME: IR node for function parameter - projects argument from function entry
# ABOUTME: Per Sea of Nodes: Parm nodes extract arguments from the Start/Call tuple
use 5.42.0;
use experimental qw(class);
use utf8;
use Chalk::IR::Type::Integer;

class Chalk::IR::Node::Parm {
    field $name :param :reader;           # Parameter name with sigil (e.g., '$x')
    field $index :param :reader;          # Parameter index (0-based)
    field $source_info :param :reader = undef;
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method op() { 'Parm' }

    method inputs() { [] }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Parm',
            inputs => [],
            attributes => {
                name  => $name,
                index => $index,
            },
        };
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    # Type is unknown/Any for now - could be refined with type annotations
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

    # Execute: look up argument value from context
    method execute($context) {
        # Arguments should be passed via context
        my $args = $context->("args:");
        return undef unless defined $args && ref($args) eq 'ARRAY';
        return $args->[$index];
    }

    # Peephole: Parm nodes can't be optimized away
    method peephole($graph = undef) {
        return $self;
    }
}

1;

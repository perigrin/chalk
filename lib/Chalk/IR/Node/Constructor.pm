# ABOUTME: Constructor node for Object::Pad-style class instantiation
# ABOUTME: Allocates heap object and initializes :param fields from named arguments
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Constructor {
    use Scalar::Util qw(refaddr);
    use Chalk::Grammar::Chalk::TypeRegistry;

    field $class_name :param :reader;            # Name of class to construct
    field $args :param :reader = {};             # Hash: field_name => IR node
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method inputs() {
        # All arg nodes are inputs
        return [ map { $_->id } values $args->%* ];
    }

    method op() { 'Constructor' }

    method to_hash() {
        my %args_hash;
        for my $name (keys $args->%*) {
            $args_hash{$name} = $args->{$name}->id;
        }

        return {
            id => $self->id,
            op => 'Constructor',
            inputs => $self->inputs,
            attributes => {
                class_name => $class_name,
                args => \%args_hash,
            },
        };
    }

    method execute($context) {
        my $env = $context->('env:');

        # Allocate a new heap ID for this object
        my $heap_id = $env->allocate_heap();

        # Initialize fields from args
        for my $field_name (keys $args->%*) {
            my $arg_node = $args->{$field_name};
            my $value = $context->("node:" . $arg_node->id);
            $env->store_heap($heap_id, $field_name, $value);
        }

        # Return the heap ID - this is the "object reference"
        return $heap_id;
    }

    method compute_type() {
        # Look up the class type from the registry
        my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
        return $registry->lookup($class_name);
    }

    # Compatibility methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    method record_transform(@args) {
        return;
    }

    method clone_with_inputs($new_inputs, $node_map, $new_attributes = {}) {
        my %new_args;
        my $input_idx = 0;
        for my $name (keys $args->%*) {
            my $input_id = $new_inputs->[$input_idx++];
            $new_args{$name} = $node_map->{$input_id}
                // die "Arg node not found in node_map: $input_id";
        }

        return Chalk::IR::Node::Constructor->new(
            class_name  => $new_attributes->{class_name} // $class_name,
            args        => \%new_args,
            source_info => $source_info,
        );
    }
}

1;

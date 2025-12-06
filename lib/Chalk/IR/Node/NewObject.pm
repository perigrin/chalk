# ABOUTME: Allocates a new object in the heap and returns its heap ID
# ABOUTME: Creates discrete heap context for object storage in CEK interpreter
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::NewObject {
    use Chalk::IR::Node::Constant;
    use Chalk::Grammar::Chalk::Type::Maybe;

    field $class_type :param :reader = undef;
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

    # No inputs for NewObject (leaf node)
    method inputs() { return []; }

    method op() { 'NewObject' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NewObject',
            inputs => [],
            attributes => {
                class_type => $class_type,
            },
        };
    }

    # Return hash of fields that should be initialized to null
    method initialized_fields() {
        return {} unless defined $class_type;

        my %init_fields;
        my $fields = $class_type->fields();
        return {} unless defined $fields;

        # Find all reference fields (Maybe types) and initialize to null
        for my $field_name (keys %$fields) {
            my $field_type = $fields->{$field_name};
            if ($field_type isa Chalk::Grammar::Chalk::Type::Maybe) {
                # Create a null constant with this Maybe type
                $init_fields{$field_name} = Chalk::IR::Node::Constant->new(
                    value => undef,
                    type  => $field_type,
                );
            }
        }

        return \%init_fields;
    }

    method execute($context) {
        # Allocate a new heap ID for this object
        # The environment must be accessible via a special context key
        my $env = $context->('env:');
        my $heap_id = $env->allocate_heap_id();

        # Initialize reference fields to null in the heap
        if (defined $class_type) {
            my $init_fields = $self->initialized_fields();
            for my $field_name (keys %$init_fields) {
                my $null_constant = $init_fields->{$field_name};
                # Execute the constant to get undef, then store in heap
                my $null_value = $null_constant->execute();
                $env->set_heap($heap_id, $field_name, $null_value);
            }
        }

        # Return the heap ID - this is the "object reference"
        return $heap_id;
    }

    # Compatibility methods
    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        return $self;
    }

    # Stub for transform tracking
    method record_transform(@args) {
        return;
    }
}

1;

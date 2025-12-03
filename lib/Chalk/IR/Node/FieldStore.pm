# ABOUTME: Stores a value into an object field in the heap
# ABOUTME: Uses heap ID, field name, and value to store field in discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::FieldStore :isa(Chalk::IR::Node::Base) {
    field $object_id :param :reader;
    field $field_id :param :reader;
    field $value_id :param :reader;
    field $alias_class :param :reader = undef;

    method op() { 'FieldStore' }

    method to_hash() {
        my %attrs = (
            object_id => $object_id,
            field_id => $field_id,
            value_id => $value_id,
        );
        $attrs{alias_class} = $alias_class if defined $alias_class;

        return {
            id     => $self->id,
            op     => 'FieldStore',
            inputs => $self->inputs,
            attributes => \%attrs,
        };
    }

    method compute($graph) {
        use Chalk::IR::Type::Memory;
        return Chalk::IR::Type::Memory->new(
            alias_class => $alias_class,
        );
    }

    method execute($context) {
        # Get the heap ID from the object node
        my $heap_id = $context->("node:$object_id");

        # Get the field name
        my $field = $context->("node:$field_id");

        # Get the value to store
        my $value = $context->("node:$value_id");

        # Get the environment
        my $env = $context->('env:');

        # Store the value in the heap at this field
        $env->set_heap($heap_id, $field, $value);

        # Return the heap ID (the object reference)
        return $heap_id;
    }
}

1;

# ABOUTME: Stores a value into an object field in the heap
# ABOUTME: Uses heap ID, field name, and value to store field in discrete heap context
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::FieldStore :isa(Chalk::IR::Node::Base) {
    field $mem_id :param :reader = undef;  # Previous memory state (for peephole optimization)
    field $object_id :param :reader;
    field $field_id :param :reader;
    field $value_id :param :reader;
    field $field_index :param :reader = undef;  # For XS ObjectFIELDS[index] access
    field $alias_class :param :reader = undef;

    method op() { 'FieldStore' }

    method to_hash() {
        my %attrs = (
            object_id => $object_id,
            field_id => $field_id,
            value_id => $value_id,
        );
        $attrs{mem_id} = $mem_id if defined $mem_id;
        $attrs{field_index} = $field_index if defined $field_index;
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

    # Peephole optimization for FieldStore
    # Implements Store-to-Store elimination and Store-after-Load elimination
    # following Simple's chapter10 design
    method peephole($graph = undef) {
        return $self unless $graph;
        return $self unless defined $mem_id;

        # Get the previous memory state
        my $prev_mem = $graph->get_node($mem_id);
        return $self unless $prev_mem;

        # Store-after-Load elimination:
        # If we're storing a value that was just loaded from the same location,
        # the store is redundant (we're writing back what's already there)
        if ($prev_mem->isa('Chalk::IR::Node::FieldLoad') &&
            $prev_mem->object_id == $object_id &&
            $value_id == $prev_mem->id &&  # Storing the load result itself
            defined $alias_class &&
            defined $prev_mem->alias_class &&
            $alias_class == $prev_mem->alias_class) {

            # The store is redundant - return the load node instead
            # (The load node represents reading the value, which is what we want)
            return $prev_mem;
        }

        # Store-to-Store elimination:
        # If previous memory is a FieldStore to the same object and field,
        # and the intermediate store has no other uses, we can bypass it
        if ($prev_mem->isa('Chalk::IR::Node::FieldStore') &&
            $prev_mem->object_id == $object_id &&
            defined $alias_class &&
            defined $prev_mem->alias_class &&
            $alias_class == $prev_mem->alias_class) {

            # Check that the intermediate store has exactly one use (this node)
            my $prev_uses = $graph->get_uses($prev_mem->id);
            if (scalar($prev_uses->@*) == 1 && $prev_uses->[0] == $self->id) {
                # Bypass the intermediate store - connect to its memory input
                my $new_store = Chalk::IR::Node::FieldStore->new(
                    inputs => [
                        (defined $prev_mem->mem_id ? $prev_mem->mem_id : ()),
                        $object_id,
                        $field_id,
                        $value_id
                    ],
                    mem_id => $prev_mem->mem_id,
                    object_id => $object_id,
                    field_id => $field_id,
                    value_id => $value_id,
                    alias_class => $alias_class,
                );
                return $new_store;
            }
        }

        return $self;
    }
}

1;

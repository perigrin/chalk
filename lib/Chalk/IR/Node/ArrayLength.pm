# ABOUTME: ArrayLength node returns the length of a fixed-size array
# ABOUTME: Corresponds to the "#" implicit field in TypeStruct representation
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::ArrayLength :isa(Chalk::IR::Node::Base) {
    field $array :param :reader;

    method op() { 'ArrayLength' }

    method to_hash() {
        return {
            id => $self->id,
            op => 'ArrayLength',
            inputs => $self->inputs,
            attributes => {
                array_id => $array->id,
            },
        };
    }

    method peephole($graph = undef) {
        # Constant folding: if array is NewArray with constant length, fold
        if ($array->isa('Chalk::IR::Node::NewArray') && defined($array->length)) {
            my $len_node = $array->length;
            if ($len_node->isa('Chalk::IR::Node::Constant')) {
                use Chalk::IR::Node::Constant;
                use Chalk::IR::Type::Integer;
                return Chalk::IR::Node::Constant->new(
                    value => $len_node->value,
                    type => Chalk::IR::Type::Integer->TOP()
                );
            }
        }

        return $self;
    }

    method execute($context) {
        my $env = $context->('env:');
        my $heap_id = $context->("node:" . $array->id);
        return $env->get_array_length($heap_id);
    }

    method compute_type() {
        use Chalk::IR::Type::Integer;
        return Chalk::IR::Type::Integer->TOP();
    }
}

1;

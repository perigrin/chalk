# ABOUTME: Field definition IR node representing a class field
# ABOUTME: Stores field metadata including name, index, type, default value, and attributes
use 5.42.0;
use experimental qw(class);
use utf8;
use Scalar::Util qw(blessed refaddr);

class Chalk::IR::Node::Field {
    field $name :param :reader;
    field $index :param :reader;
    field $field_type :param :reader = undef;
    field $default :param :reader = undef;
    field $field_attributes :param :reader = undef;
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

    method op() { 'Field' }

    # Dynamically compute inputs from default node
    # This ensures graph traversal finds dependencies
    method inputs() {
        return [] unless defined $default;
        return [] unless blessed($default) && $default->can('id');
        return [$default->id];
    }

    method is_param() {
        return 0 unless defined $field_attributes;
        return $field_attributes->{param} // 0;
    }

    method is_reader() {
        return 0 unless defined $field_attributes;
        return $field_attributes->{reader} // 0;
    }

    method attributes() {
        return $field_attributes // {};
    }

    method to_hash() {
        my %attrs = (
            name  => $name,
            index => $index,
        );

        $attrs{field_type} = $field_type if defined $field_type;
        $attrs{default_id} = $default->id if defined $default;
        $attrs{field_attributes} = $field_attributes if defined $field_attributes;

        return {
            id     => $self->id,
            op     => 'Field',
            inputs => $self->inputs,
            attributes => \%attrs,
        };
    }

    # Compatibility methods for code expecting Base methods
    method peephole($graph = undef) {
        return $self;
    }

    method compute() {
        # Field nodes don't participate in type inference directly
        return Chalk::IR::Type::Top->top();
    }

    method idealize() {
        return;
    }

    method record_transform(@args) {
        return;
    }

    method get_transform_chain() {
        return [$transform_chain->@*];
    }
}

1;

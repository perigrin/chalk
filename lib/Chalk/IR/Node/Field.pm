# ABOUTME: Field definition IR node representing a class field
# ABOUTME: Stores field metadata including name, index, type, default value, and attributes
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Field :isa(Chalk::IR::Node::Base) {
    field $name :param :reader;
    field $index :param :reader;
    field $field_type :param :reader = undef;
    field $default :param :reader = undef;
    field $field_attributes :param :reader = undef;

    method op() { 'Field' }

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
}

1;

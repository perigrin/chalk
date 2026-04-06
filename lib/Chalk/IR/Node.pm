# ABOUTME: Base class for all IR nodes in the Chalk Sea of Nodes representation.
# ABOUTME: Provides id, use-def chains, content_hash, stamp, and compat_class fields.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node {

    # Stable content-based ID for the node
    field $id :param :reader;

    # Producer nodes - nodes that produce values consumed by this node
    field $inputs :param :reader = [];

    # Consumer nodes - nodes that consume values produced by this node
    # This is mutable to allow building the graph
    field $consumers :reader = [];

    # Optional stamp for identifying parse-origin or generation context
    field $stamp        :param :reader = undef;

    # Optional compat_class overrides the result of class() for back-compat
    field $compat_class :param :reader = undef;

    # Add a consumer to this node's consumer list
    method add_consumer($node) {
        push $consumers->@*, $node;
    }

    # Remove a consumer from this node's consumer list
    method remove_consumer($node) {
        my $target_id = $node->id();
        $consumers->@* = grep { $_->id() ne $target_id } $consumers->@*;
    }

    # Abstract method - subclasses must implement
    method operation() {
        die ref($self) . " must implement operation()";
    }

    method class() {
        return $compat_class if defined $compat_class;
        return $self->operation();
    }

    # Serialize inputs to a list of ID strings for content_hash.
    # Handles undef, nested arrayrefs, and plain node inputs.
    method _serialize_inputs() {
        my @parts;
        for my $input ($self->inputs()->@*) {
            if (!defined $input) {
                push @parts, 'undef';
            } elsif (ref($input) eq 'ARRAY') {
                my @ids = map { defined($_) ? $_->id() : 'undef' } $input->@*;
                push @parts, '[' . join(',', @ids) . ']';
            } else {
                push @parts, $input->id();
            }
        }
        return @parts;
    }

    method content_hash() {
        return join('|', $self->operation(), $self->_serialize_inputs());
    }
}

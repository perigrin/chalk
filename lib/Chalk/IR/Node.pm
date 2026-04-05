# ABOUTME: Base class for all IR nodes in the Chalk Sea of Nodes representation.
# ABOUTME: Provides id, inputs, consumers, stamp fields with use-def chain tracking.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::IR::Node {
    field $id        :param :reader;
    field $inputs    :param :reader = [];
    field $consumers :reader        = [];
    field $stamp     :param :reader = undef;

    method add_consumer($node) {
        push $consumers->@*, $node;
    }

    method remove_consumer($node) {
        my $target_id = $node->id();
        $consumers->@* = grep { $_->id() ne $target_id } $consumers->@*;
    }

    method operation() {
        die "Subclass must implement operation()";
    }

    method content_hash() {
        my $op = $self->operation();
        my @input_ids = map { defined($_) ? $_->id() : 'undef' } $inputs->@*;
        return $op . '|' . join('|', @input_ids);
    }
}

# ABOUTME: IR Phi node for merging values at CFG join points (Sea of Nodes).
# ABOUTME: Holds a region reference and supports set_backedge for loop back-edge wiring.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Phi :isa(Chalk::IR::Node) {
    field $region :param :reader;

    method operation() { 'Phi' }

    method content_hash() {
        my @input_ids = map { defined($_) ? $_->id() : 'undef' } $self->inputs()->@*;
        return "Phi|region=" . $region->id() . "|" . join('|', @input_ids);
    }

    method set_backedge($value) {
        my $old = $self->inputs()->[1];
        $old->remove_consumer($self) if defined $old;
        $self->inputs()->[1] = $value;
        $value->add_consumer($self) if defined $value;
    }
}

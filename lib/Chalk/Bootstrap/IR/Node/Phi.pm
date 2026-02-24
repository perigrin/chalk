# ABOUTME: IR node representing value selection at a control merge point
# ABOUTME: Phi nodes select which value to use based on which control path was taken
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Phi :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Phi';
    }

    # Set the backedge value (second element of the values array).
    # This is the only mutation point — backedges don't exist at construction time.
    method set_backedge($value) {
        $self->inputs()->[1][1] = $value;
    }
}

# ABOUTME: IR node representing a loop header in control flow
# ABOUTME: Loop nodes are special Region nodes with entry and backedge control inputs
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::IR::Node::Loop :isa(Chalk::Bootstrap::IR::Node) {
    method operation() {
        return 'Loop';
    }

    # Set the backedge control input (second element of inputs).
    # This is the only mutation point — backedges don't exist at construction time.
    method set_backedge_ctrl($ctrl) {
        $self->inputs()->[1] = $ctrl;
    }
}

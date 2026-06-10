# ABOUTME: RegexCapture node — reads capture group N ($1..$9) of a regex match.
# ABOUTME: inputs[0] is the RegexMatch/Match node; the value is a slot of that match's result.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::RegexCapture :isa(Chalk::IR::Node) {
    # Capture group number (1-based, $1..$9). The whole-match bounds (group 0)
    # are not exposed through this node ($& is a tracked follow-up).
    field $n :param :reader;

    method operation() { 'RegexCapture' }

    method content_hash() {
        return join('|', 'RegexCapture', "n=$n", $self->_serialize_inputs());
    }
}

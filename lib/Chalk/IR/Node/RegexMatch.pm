# ABOUTME: Regex match operation node in the Chalk IR.
# ABOUTME: Represents a pattern match (m//) against an input expression.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Regex;

class Chalk::IR::Node::RegexMatch :isa(Chalk::IR::Node::Regex) {
    method operation() { 'RegexMatch' }

    # A MEMORY VERSION where pinned: B::SoN versions memory at a pinned match
    # (a /g's pos); no value changes there.
    method is_memory_version() { return $self->is_pinned }
    method staleness_kind() { 'opaque' }

    # FIXED: sets the capture state a later $N read depends on
    method is_fixed() { return true }
}

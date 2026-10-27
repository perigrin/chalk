# ABOUTME: Regex substitution operation node in the Chalk IR.
# ABOUTME: Represents a substitution (s///) applied to an input expression.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Regex;

class Chalk::IR::Node::RegexSubst :isa(Chalk::IR::Node::Regex) {
    field $replacement :param :reader = '';
    # A replacement B::SoN makes per match (/ge): the graph that computes it.
    field $replacement_body :param :reader = undef;

    method operation() { 'RegexSubst' }
    method staleness_kind() { 'opaque' }

    # FIXED: s/// mutates its subject
    method is_fixed() { return true }

    method content_hash() {
        return join('|', 'RegexSubst', "pattern=" . $self->pattern,
            "replacement=$replacement", "flags=" . $self->flags, "body=" . ( $replacement_body // '' ),
            $self->_serialize_inputs());
    }
}

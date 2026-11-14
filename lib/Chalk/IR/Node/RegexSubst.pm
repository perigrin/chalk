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
    # The pattern is input 1, made at run time (an interpolated one), not `pattern`.
    field $pattern_is_input :param :reader = 0;

    method operation() { 'RegexSubst' }

    # is_in_place -> true for one that WRITES ITS SUBJECT: pinned, not /r, of a
    # variable (B::SoN gives a copy's -- `(my $t = $s) =~ s///` -- as the value
    # it was given: the node's value is then the new string).
    method is_in_place() {
        my $subj = $self->inputs->[0];
        return ( $self->flags // '' ) !~ /r/ && $self->is_pinned
            && blessed($subj) && $subj->operation eq 'PadAccess';
    }

    # A MEMORY VERSION where pinned: it stores its subject's new string (in place).
    method is_memory_version() { return $self->is_pinned }
    method staleness_kind() { 'opaque' }

    # FIXED: s/// mutates its subject
    method is_fixed() { return true }

    method content_hash() {
        return join('|', 'RegexSubst', "pattern=" . $self->pattern,
            "replacement=$replacement", "flags=" . $self->flags, "body=" . ( $replacement_body // '' ), "pin=$pattern_is_input",
            $self->_serialize_inputs());
    }
}

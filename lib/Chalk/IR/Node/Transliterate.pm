# ABOUTME: tr/// and y/// (B::SoN): maps characters of one set to another, in place like s///.
# ABOUTME: from, to and flags as written; d cannot be read off an empty to, so the flags ride along.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';
use Chalk::IR::Value;
class Chalk::IR::Node::Transliterate :isa(Chalk::IR::Value) {
    field $from  :param :reader = '';
    field $to    :param :reader = '';
    field $flags :param :reader = '';
    method operation() { 'Transliterate' }

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
    method is_fixed() { return true }
}

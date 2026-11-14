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

    # A MEMORY VERSION where pinned: it stores its subject's new string (in place).
    method is_memory_version() { return $self->is_pinned }
    method staleness_kind() { 'opaque' }
    method is_fixed() { return true }
}

# ABOUTME: IR node for `@_`, the argument list a caller passes to a sub.
# ABOUTME: Distinct from StashAccess: an argument list, not a name defined outside.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

# `@_` is the ARGUMENT LIST, created by the CALLER and dynamically scoped to the
# innermost enclosing sub call.
#
# It rode on StashAccess(main, '_') because `@_` is reachable as the package
# array *main::_ -- true, and useless. StashAccess's job after the package-scalar
# SSA migration is the ENTRY DEFINITION: naming a value defined outside this unit
# and carrying no value of its own. An argument list is not that.
#
# Sharing one node cost a real defect: with identity keyed on name alone, `$_`
# and `@_` hash-consed into ONE node feeding both a `shift @_` and a RegexMatch
# subject.
#
# NO FIELDS: there is exactly one `@_` per sub invocation, so hash-consing one
# per graph is correct rather than a collision.
class Chalk::IR::Node::ArgsSource :isa(Chalk::IR::Node::Access) {
    method operation() { 'ArgsSource' }
    sub identity_kind { q(hash_consed) }

    method content_hash() {
        return join('|', 'ArgsSource', $self->_serialize_inputs());
    }
}

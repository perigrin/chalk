# ABOUTME: Method, subroutine, or builtin call node in the Chalk IR.
# ABOUTME: Carries dispatch kind (method/sub/builtin) and callee name.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::Call :isa(Chalk::IR::Node) {
    field $dispatch_kind :param :reader;
    field $name          :param :reader;

    # paren_form: true when the source used the parens-bounded call form
    # (e.g., `push(@arr, $x)`) rather than the bare list-op form
    # (e.g., `push @arr, $x`). Threaded from CallExpression alt 0 (paren
    # form) at parse time; defaults to false for backward compatibility
    # with the many sites that construct Call without setting it.
    # Used by _push_methodcall_inward / _push_deref_inward to distinguish
    # legitimate paren-form chains (no peel) from filter-gap merge
    # artifacts (peel correct).
    field $paren_form :param :reader = false;

    method operation() { 'Call' }

    method content_hash() {
        return join('|', 'Call',
            "dispatch_kind=$dispatch_kind",
            "name=$name",
            ($paren_form ? "paren_form=1" : ()),
            $self->_serialize_inputs());
    }
}

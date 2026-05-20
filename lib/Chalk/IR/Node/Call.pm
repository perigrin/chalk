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

    # Resolved callee handle (Chalk::MOP::Method or Chalk::MOP::Sub).
    # Per Phase 4, CallExpression resolves the symbolic name via
    # $mop->find_method() and stores the metaobject reference here so
    # codegen can read the callee's graph/params/return-type directly
    # without going through the symbol table at emit time.
    # May be undef for builtins or unresolved calls (still uses $name).
    #
    # Not part of content_hash: the SAME call signature (same dispatch,
    # name, inputs) should hash-cons to a single node regardless of
    # whether its target has been resolved yet. Resolution is a late
    # decoration applied by ClassBlock's post-pass after all methods
    # in scope have been registered on the MOP.
    field $target :param :reader = undef;

    method operation() { 'Call' }

    method content_hash() {
        return join('|', 'Call',
            "dispatch_kind=$dispatch_kind",
            "name=$name",
            ($paren_form ? "paren_form=1" : ()),
            $self->_serialize_inputs());
    }

    # Late-binding setter for the resolved callee. Used by ClassBlock's
    # Phase 4 post-pass once the MOP has every class's methods registered.
    method set_target($mop_method) {
        $target = $mop_method;
        return;
    }
}

# ABOUTME: IR node for a declared signature parameter, identified by position.
# ABOUTME: Pure and zero-input: a parameter is a value, not a load or an event.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node::Access;

# A PARAMETER IS A VALUE, NOT A SLOT.
#
# The producer's `argelem` handler previously minted a PadAccess -- perl's
# STORAGE for the parameter rather than the parameter itself -- discarding both
# the position and the sigil that the op carries. That is the same layering leak
# as reading a lexical through its pad index: it re-implements perl's
# implementation instead of expressing perl's semantics.
#
# Modelled on TurboFan's Parameter (common-operator.cc, verified verbatim):
#
#     IrOpcode::kParameter, Operator::kPure,     // opcode
#     "Parameter",                               // name
#     1, 0, 0, 1, 0, 0,                          // counts
#     ParameterInfo(index, debug_name));
#
# PURE and ZERO-INPUT. Both V8 pipelines agree that a parameter is pure
# (TurboFan `Operator::kPure`, Turboshaft `OpEffects()`), so it floats, CSEs and
# hoists. Turboshaft's is likewise arity 0, with V8's own comment "on the callee
# side a parameter doesn't have an input". This matters concretely here: `$_[0]`
# reaches the backend as `Subscript(ArgsSource, 0, MemStart)` -- a MEMORY READ,
# ordered against every other memory op for no semantic reason.
#
# HASH-CONSED BY INDEX. TurboFan's `hash_value(ParameterInfo p)` returns
# `p.index()`, so two reads of parameter 0 are ONE node. The NAME is debug
# information and must not split identity.
#
# TYPED FROM ITS SIGIL. A slurpy is NOT always an array -- `sub f(%h)` is a
# hash. The producer does not stamp these (its lattice has ArrayRef/HashRef,
# which are REFERENCES, and no Array/Hash), so the sigil is what a consumer
# types from on this side, where Array and Hash do exist.
class Chalk::IR::Node::Parameter :isa(Chalk::IR::Node::Access) {
    field $index :param :reader;
    field $name  :param :reader = undef;
    field $sigil :param :reader = '$';
    # How a signature default applies: 'absent' (`$b = 3`), 'undef' (`//=`)
    # or 'false' (`||=`); undef for a parameter with none. The default's
    # value is inputs[0].
    field $default_when :param :reader = undef;

    method operation() { 'Parameter' }

    # INDEX ONLY -- see the hash-consing note above. Including the name would
    # make identity depend on debug information, and a synthesized parameter
    # with no pad name would fail to cons with its named twin.
    method content_hash() {
        return join( '|', 'Parameter', "index=$index" );
    }
}

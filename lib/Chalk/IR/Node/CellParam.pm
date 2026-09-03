# ABOUTME: A capture cell arriving inside a closure body -- the binding, not the value.
# ABOUTME: Distinct from Parameter on purpose: a capture is not a positional argument.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Value;

class Chalk::IR::Node::CellParam :isa(Chalk::IR::Value) {

    # Which of the closure's captured cells this is. Positional within the
    # AnonSub's cell inputs, NOT within the caller's argument list.
    field $index :param :reader = 0;

    # The captured variable's name, for diagnostics. Not an identity: two
    # closures capturing different `$i` cells from different loop iterations
    # share this name.
    field $name :param :reader = undef;

    # A DISTINCT NODE KIND RATHER THAN A FLAG ON Parameter, deliberately.
    #
    # `Parameter` means "positional argument N of this sub's signature" and
    # lowers to %argN. A capture is none of that: not positional in the
    # caller's list, not supplied by the caller, and with no declared index of
    # its own.
    #
    # A `Parameter` carrying an `is_cell` flag would make ONE spelling mean TWO
    # things, so every existing Parameter consumer would need a check it does
    # not currently do -- and the ones that forget get a capture where they
    # expect argument 0, silently. A distinct op makes the same consumer GAP on
    # an unknown operation instead. Refusal over miscompile.
    #
    # This is the mirror of a defect already paid for: a forwarded parameter
    # spelled as PadAccess instead of Parameter cost three separate layers of
    # blind spot (typing, ABI, lowering). One thing with two spellings is
    # expensive; two things with one spelling is worse, because it fails
    # silently rather than loudly.
    method operation() { 'CellParam' }
    method staleness_kind() { 'opaque' }
}

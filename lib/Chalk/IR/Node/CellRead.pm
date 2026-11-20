# ABOUTME: Reads the current value out of a capture cell, through the memory chain.
# ABOUTME: Program-point-dependent -- a later CellWrite changes what an identical read returns.
use 5.42.0;
use utf8;
use experimental 'class';
no warnings 'experimental::class';

use Chalk::IR::Value;

class Chalk::IR::Node::CellRead :isa(Chalk::IR::Value) {

    # inputs[0] is the cell (a MakeCell or a CellParam); inputs[1] is the
    # memory version this read observes.
    #
    # THE MEMORY INPUT IS WHAT MAKES SHARING VISIBLE. Two closures over one
    # cell must see each other's writes:
    #
    #   my $c = 0; my $inc = sub { $c = $c + 1 }; my $rd = sub { $c };
    #   $inc->(); $inc->();   $rd->() is 2
    #
    # so `$rd`'s read has to observe `$inc`'s write. Threading it on the
    # memory chain is what the optimizer already understands for element
    # stores, and reusing that machinery is why the cell is modelled this way
    # rather than as an opaque box.
    method operation() { 'CellRead' }

    # A MUTABLE-LOCATION LOAD, exactly like PadAccess/Subscript/FieldAccess.
    # Its lowered value is program-point-dependent -- a later write changes
    # what an identical read returns -- so it must re-lower at every
    # consumption point and never be served from the value cache.
    method staleness_kind() { 'mutable_read' }
}

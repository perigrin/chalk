# ABOUTME: Intermediate base class for aggregate constructor IR nodes.
# ABOUTME: Groups HashRef, ArrayRef, and Interpolate nodes.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::Aggregate :isa(Chalk::IR::Value) {
    # The variable a literal is the contents of, as B::SoN names it: `@x`'s
    # `x`, a package one's `@main::x`. Undef when the wire names none.
    field $symbol :param :reader = undef;

    # stored_whole($literal) -> the package aggregate (an EntryDef) a named
    # Array/HashLiteral is stored into whole -- B::SoN's `@a = LIST` -- or
    # undef. Not a `local`'s fresh one: that is bound, not stored. (A function:
    # ArrayLiteral and HashLiteral answer it, not every Aggregate.)
    sub stored_whole($literal) {
        for my $w ( $literal->consumers->@* ) {
            next unless blessed($w) && $w->operation eq 'EntryWrite' && !$w->binds
                && blessed( $w->inputs->[1] ) && refaddr( $w->inputs->[1] ) == refaddr($literal);
            return $w->inputs->[0] if blessed( $w->inputs->[0] ) && $w->inputs->[0]->is_package_aggregate;
        }
        return undef;
    }
}

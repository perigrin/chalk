# ABOUTME: First-class IR node for comma-separated expression lists.
# ABOUTME: Represents the parameter list of a call or any other list context.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Value;

class Chalk::IR::Node::ExpressionList :isa(Chalk::IR::Value) {
    method operation() { 'ExpressionList' }
    method staleness_kind() { 'opaque' }
    sub identity_kind { 'hash_consed' }

    # Items are stored as a single arrayref in inputs->[0].
    # Empty list is permitted: ExpressionList(inputs => [[]]).
    method items() {
        my $inputs = $self->inputs();
        return [] unless $inputs && $inputs->@*;
        my $first = $inputs->[0];
        return ref($first) eq 'ARRAY' ? $first : [];
    }
}

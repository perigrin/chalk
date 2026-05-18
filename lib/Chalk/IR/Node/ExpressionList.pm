# ABOUTME: First-class IR node for comma-separated expression lists.
# ABOUTME: Represents the parameter list of a call or any other list context.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::Node;

class Chalk::IR::Node::ExpressionList :isa(Chalk::IR::Node) {
    method operation() { 'ExpressionList' }

    # Items are stored as a single arrayref in inputs->[0].
    # Empty list is permitted: ExpressionList(inputs => [[]]).
    method items() {
        my $inputs = $self->inputs();
        return [] unless $inputs && $inputs->@*;
        my $first = $inputs->[0];
        return ref($first) eq 'ARRAY' ? $first : [];
    }
}

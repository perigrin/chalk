# ABOUTME: Well-typed-graph invariant checker for the typed-IR-representation model.
# ABOUTME: Walks a node list and flags unbridged representation mismatches (H2 from the arch review).
package Chalk::IR::Graph::TypedInvariant;
use 5.42.0;
use utf8;

use Chalk::IR::Node::Coerce;

# Required-operand-representation for each operation.
# An op listed here requires ALL its data inputs to carry the given representation
# (or be a Coerce node whose to_repr equals that representation).
# Only ops whose operand representations are structurally enforced at the IR level
# are listed. Ops NOT listed here are unchecked (the invariant applies only to
# operations with a declared requirement).
my %OP_REQUIRED_REPR = (
    Add      => 'Int',
    Subtract => 'Int',
    Multiply => 'Int',
    Divide   => 'Num',  # Perl `/` is always float division; inputs must be Num
    Modulo   => 'Int',
    Concat   => 'Str',  # String concatenation requires Str operands (G3)
);

# check(\@nodes) -> { ok => bool, violations => [ { node_id, message } ] }
#
# Walks the provided node list. For each operation node whose operation() is
# in %OP_REQUIRED_REPR, checks that every input's representation either:
#   (a) matches the required representation, or
#   (b) is undef (not yet assigned — skip; undef is "not yet checked", not wrong), or
#   (c) the input is a Coerce node whose to_repr matches the required representation.
#
# Any other combination is a violation: the operand has a definite, wrong
# representation and no Coerce bridges the gap.
sub check {
    my ($class, $nodes) = @_;
    my @violations;

    for my $node ($nodes->@*) {
        my $op = $node->operation();
        my $required = $OP_REQUIRED_REPR{$op};
        next unless defined $required;

        my $inputs = $node->inputs();
        next unless defined $inputs;

        for my $i (0 .. $inputs->$#*) {
            my $input = $inputs->[$i];
            next unless defined $input;
            # Skip nested arrayrefs (e.g. Call arg lists)
            next if ref($input) eq 'ARRAY';

            my $input_repr = $input->representation();
            # undef = not yet assigned; skip (not a violation)
            next unless defined $input_repr;

            # If the input IS a Coerce node, check its to_repr
            if ($input->isa('Chalk::IR::Node::Coerce')) {
                if ($input->to_repr() ne $required) {
                    push @violations, {
                        node_id => $node->id(),
                        message => sprintf(
                            'op %s at position %d: Coerce node to_repr=%s does not match required %s',
                            $op, $i, $input->to_repr(), $required
                        ),
                    };
                }
                next;
            }

            # Plain node: representation must match required
            if ($input_repr ne $required) {
                push @violations, {
                    node_id => $node->id(),
                    message => sprintf(
                        'op %s input[%d] has representation=%s, required=%s, no Coerce bridge',
                        $op, $i, $input_repr, $required
                    ),
                };
            }
        }
    }

    return {
        ok         => @violations == 0 ? 1 : 0,
        violations => \@violations,
    };
}

1;

# ABOUTME: Peephole optimizer for Sea of Nodes CFG graph.
# ABOUTME: Applies local rewrites: Phi collapse, Region bypass, constant-If elimination.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::IR::Optimizer;

# Collapse Phi(Region, X, X) → X when all value inputs are the same node.
# Returns the collapsed value or the original Phi if inputs differ.
sub collapse_phi($, $phi) {
    my $values = $phi->inputs();  # values arrayref (inputs are Phi values directly)
    return $phi unless ref($values) eq 'ARRAY' && $values->@* > 0;

    my $first = $values->[0];
    return $phi unless defined $first;

    for my $v ($values->@*) {
        return $phi unless defined $v && refaddr($v) == refaddr($first);
    }

    return $first;
}

# Collapse Region([single_ctrl]) → single_ctrl when there's only one control input.
# Returns the single control or the original Region if multiple inputs exist.
sub collapse_region($, $region) {
    my $controls = $region->inputs()->[0];  # controls arrayref
    return $region unless ref($controls) eq 'ARRAY';
    return $controls->[0] if $controls->@* == 1;
    return $region;
}

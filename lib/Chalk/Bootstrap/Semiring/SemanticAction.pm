# ABOUTME: Semantic action semiring for building IR nodes from parse results.
# ABOUTME: Values are Contexts, operations combine contexts for sequences and alternatives.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Semiring::SemanticAction {
    field $actions :param = undef;

    # zero returns undef (parse failure)
    method zero() {
        return undef;
    }

    # one returns empty context with undef focus
    method one() {
        return Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            position => 0,
            rule     => undef,
        );
    }

    # Check if value is zero (undef)
    method is_zero($value) {
        return !defined $value;
    }

    # Multiply combines two contexts in sequence
    # Creates parent context with both as children
    method multiply($left, $right) {
        # Propagate zero
        return undef if !defined $left;
        return undef if !defined $right;

        # Create parent context with both children
        # Focus will be computed by semantic action later
        return Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [$left, $right],
            position => $right->position(),
            rule     => undef,
        );
    }

    # on_scan: create a Context for the matched text and multiply with existing value
    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $scan_ctx = Chalk::Bootstrap::Context->new(
            focus    => $matched_text,
            children => [],
            position => 0,
            rule     => undef,
        );
        return $self->multiply($item->{value}, $scan_ctx);
    }

    # on_complete: apply semantic action for a completed rule
    # Looks up action by rule_name via can(), applies via extend, sets rule field
    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return undef if !defined $value;

        my $rule_name = $item->{rule}->name();
        my $method = $actions ? $actions->can($rule_name) : undef;
        my $result;
        if ($method) {
            # Call the method via the actions object instance
            $result = $value->extend(sub { $actions->$method(@_) });
        } else {
            # No action registered - preserve value as-is
            $result = $value;
        }

        # Set the rule name on the result context
        return Chalk::Bootstrap::Context->new(
            focus    => $result->extract(),
            children => $result->children(),
            position => $result->position(),
            rule     => $rule_name,
        );
    }

    # Add combines alternative derivations.
    # Upstream semirings (Precedence, TypeInference, Structural) MUST
    # disambiguate before SemanticAction sees the alternatives. If both
    # are non-zero here, the parse is genuinely ambiguous and we must
    # reject it rather than silently picking one.
    method add($left, $right) {
        # If left is zero, return right
        return $right if !defined $left;

        # If right is zero, return left
        return $left if !defined $right;

        # Same context on both sides means Composite already disambiguated
        # via selects_alternative and is passing the winner through
        return $left if $left == $right;

        # Both non-zero AND different: ambiguous parse — upstream disambiguation failed
        die "Ambiguous parse: SemanticAction::add() received two non-zero alternatives. "
            . "Upstream semirings must disambiguate before semantic actions run.";
    }
}

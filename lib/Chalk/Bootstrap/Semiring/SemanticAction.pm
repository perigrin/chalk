# ABOUTME: Semantic action semiring for building IR nodes from parse results.
# ABOUTME: Values are Contexts, operations combine contexts for sequences and alternatives.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Semiring::SemanticAction {
    field $action_package :param = undef;

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

    # Return semiring value for a scanned terminal match
    # Creates a Context with the matched text as focus
    method scan_value($text) {
        return Chalk::Bootstrap::Context->new(
            focus    => $text,
            children => [],
            position => 0,
            rule     => undef,
        );
    }

    # Apply semantic action for a completed rule
    # Looks up action by rule_name via can(), applies via extend, sets rule field
    method complete_value($value, $rule_name) {
        return undef if !defined $value;

        my $action = $action_package ? $action_package->can($rule_name) : undef;
        my $result;
        if ($action) {
            $result = $value->extend($action);
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

    # Add combines alternative derivations
    # For now, just return first alternative (disambiguation later)
    method add($left, $right) {
        # If left is zero, return right
        return $right if !defined $left;

        # If right is zero, return left
        return $left if !defined $right;

        # Both non-zero: return first alternative
        # TODO: Log that multiple parses exist if debug enabled
        return $left;
    }
}

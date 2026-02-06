# ABOUTME: Composite semiring running Boolean and SemanticAction together.
# ABOUTME: Values are 2-tuples [bool_value, semantic_value], operations delegate to both.
use 5.42.0;
use utf8;
use feature 'class';
no warnings 'experimental::class';

class Chalk::Bootstrap::Semiring::Composite {
    field $boolean  :param :reader;
    field $semantic :param :reader;

    # zero returns tuple of both zeros
    method zero() {
        return [$boolean->zero(), $semantic->zero()];
    }

    # one returns tuple of both ones
    method one() {
        return [$boolean->one(), $semantic->one()];
    }

    # Check if value is zero by checking boolean component
    method is_zero($value) {
        return $boolean->is_zero($value->[0]);
    }

    # Multiply delegates to both semirings
    method multiply($left, $right) {
        my $bool_result = $boolean->multiply($left->[0], $right->[0]);
        my $sem_result = $semantic->multiply($left->[1], $right->[1]);
        return [$bool_result, $sem_result];
    }

    # Return semiring value for a scanned terminal match, delegates to both
    method scan_value($text) {
        return [$boolean->scan_value($text), $semantic->scan_value($text)];
    }

    # Apply semantic action for a completed rule, delegates to both
    method complete_value($value, $rule_name) {
        my $bool_result = $boolean->complete_value($value->[0], $rule_name);
        my $sem_result = $semantic->complete_value($value->[1], $rule_name);
        return [$bool_result, $sem_result];
    }

    # Add delegates to both semirings
    method add($left, $right) {
        my $bool_result = $boolean->add($left->[0], $right->[0]);
        my $sem_result = $semantic->add($left->[1], $right->[1]);
        return [$bool_result, $sem_result];
    }
}

# ABOUTME: Boolean recognition semiring for parse acceptance/rejection.
# ABOUTME: Provides zero, one, multiply, add operations with reference-based zero detection.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::Boolean {
    # Use a unique reference for zero value (identity checked via refaddr).
    # Chalk does not support bless — we use feature class exclusively.
    my $ZERO = [];

    method zero() {
        return $ZERO;
    }

    method one() {
        return true;
    }

    method is_zero($value) {
        # Use reference equality for zero detection
        my $value_addr = refaddr($value);
        my $zero_addr = refaddr($ZERO);

        # If either is not a reference, they can't be equal
        return false unless defined $value_addr;
        return false unless defined $zero_addr;

        return $value_addr == $zero_addr;
    }

    method multiply($left, $right) {
        # Sequence: if either is zero, result is zero
        return $ZERO if $self->is_zero($left);
        return $ZERO if $self->is_zero($right);
        return true;
    }

    method add($left, $right) {
        # Alternative: if either is non-zero, result is non-zero
        return true unless $self->is_zero($left);
        return true unless $self->is_zero($right);
        return $ZERO;
    }

    # on_scan: combine existing item value with one() for successful scan
    method on_scan($item, $alt_idx, $pos, $matched_text) {
        return $self->multiply($item->{value}, $self->one());
    }

    # on_complete: no-op for Boolean, return value unchanged
    method on_complete($item, $alt_idx, $pos) {
        return $item->{value};
    }

    # should_scan: gate for scan operation, called after regex match succeeds
    # Returns true to proceed with scan, false to skip it.
    # Default: always return true (no filtering).
    method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
        return true;
    }

    # Leo optimization is safe for Boolean: on_complete is identity,
    # multiply is associative, skipping intermediate completions is correct.
    method supports_leo() {
        return true;
    }
}

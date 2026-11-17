# ABOUTME: Boolean recognition semiring for parse acceptance/rejection.
# ABOUTME: Participates in FilterComposite via the 'boolean' annotation slot.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Semiring::Boolean {
    # Boolean has exactly two values, and each is one shared Context: zero()
    # for failure, one() for a live parse. Every operation returns one of the
    # two. Recognition asks only whether a parse exists, so no value records
    # how it was derived; a Context per multiply or add would keep the whole
    # derivation history of the input alive for nothing.
    my $ZERO_CTX;
    my $ONE_CTX;

    method zero() {
        $ZERO_CTX //= Chalk::Bootstrap::Context->new(
            focus       => undef,
            children    => [],
            is_zero     => true,
            annotations => { boolean => false },
        );
        return $ZERO_CTX;
    }

    method one() {
        $ONE_CTX //= Chalk::Bootstrap::Context->new(
            focus       => true,
            children    => [],
            is_zero     => false,
            annotations => { boolean => true },
        );
        return $ONE_CTX;
    }

    # Pass-through: Boolean semiring does not carry control state.
    # The lateral-seed channel is handled at the SemanticAction layer.
    method one_with_control($node) { return $self->one() }

    # is_zero reads the Context's is_zero flag directly.
    method is_zero($value) {
        return $value->is_zero();
    }

    # multiply combines two parse branches. Both must be live for the
    # product to be live (boolean AND). Scan and completion events arrive
    # as live right operands and leave the value as it is.
    method multiply($left, $right) {
        return $self->zero() if $left->is_zero();
        return $self->zero() if $right->is_zero();
        return $self->one();
    }

    # add combines two alternatives. At least one must be live for the sum
    # to be live (boolean OR). When both are live, Boolean has no opinion on
    # which derivation to prefer: the sum is one(), which both inputs
    # already are, so it singles out neither. FilterComposite reads a result
    # identical to both inputs as "Boolean abstains".
    method add($left, $right) {
        return $self->zero() if $left->is_zero() && $right->is_zero();
        return $self->one();
    }

    # slot_name: Boolean reads/writes the 'boolean' annotation slot.
    method slot_name() {
        return 'boolean';
    }
}

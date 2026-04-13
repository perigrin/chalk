# ABOUTME: Boolean recognition semiring for parse acceptance/rejection.
# ABOUTME: Returns Context objects so the parse tree shape survives for graph-equivalence testing.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Semiring::Boolean {
    # Lazy singletons keep zero()/one() identity stable — useful for ref-eq checks
    # in callers that hash-cons on semiring results. Boolean has only two atomic
    # states; leaves (one) and failure (zero) are both content-free, so sharing
    # the same Context object per state is safe and deterministic.
    my $ZERO_CTX;
    my $ONE_CTX;

    method zero() {
        $ZERO_CTX //= Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [],
            is_zero  => true,
        );
        return $ZERO_CTX;
    }

    method one() {
        $ONE_CTX //= Chalk::Bootstrap::Context->new(
            focus    => true,
            children => [],
            is_zero  => false,
        );
        return $ONE_CTX;
    }

    # is_zero reads the Context's is_zero flag. Non-Context values are never
    # considered zero — they're foreign to this semiring's protocol and the
    # safest reading is "not zero" so we don't poison parses that leak them in.
    method is_zero($value) {
        return false unless defined $value;
        return false unless ref($value);
        return false unless blessed($value) && $value->isa('Chalk::Bootstrap::Context');
        return $value->is_zero() ? true : false;
    }

    # multiply builds a structural Context wrapping $left and $right as children.
    # The resulting tree preserves parse shape, which is what the Leo
    # graph-equivalence test needs to compare Leo-on vs Leo-off runs.
    # Short-circuits to the zero singleton if either operand is zero.
    method multiply($left, $right) {
        return $self->zero() if $self->is_zero($left);
        return $self->is_zero($right) ? $self->zero() : Chalk::Bootstrap::Context->new(
            focus    => true,
            children => [$left, $right],
            is_zero  => false,
        );
    }

    # add combines two alternatives. For pure recognition we only care whether
    # at least one alternative succeeded. If both are non-zero we keep $left
    # (deterministic tie-break); if only one is non-zero it wins; if both are
    # zero we return zero.
    method add($left, $right) {
        my $lz = $self->is_zero($left);
        my $rz = $self->is_zero($right);
        return $self->zero() if $lz && $rz;
        return $right if $lz;
        return $left;
    }

    # slot_name: Boolean operates through is_zero only — no annotation slot.
    method slot_name() {
        return undef;
    }
}

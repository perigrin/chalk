# ABOUTME: Boolean recognition semiring for parse acceptance/rejection.
# ABOUTME: Participates in FilterComposite via the 'boolean' annotation slot.
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

    # is_zero reads the Context's is_zero flag directly.
    method is_zero($value) {
        return $value->is_zero();
    }

    # multiply combines two live parse branches. Both must be live for the
    # product to be live (boolean AND). Returns a two-child Context so parse
    # shape is preserved for Leo graph-equivalence testing, tagged with
    # annotations->{boolean} = true so FilterComposite can read the slot.
    method multiply($left, $right) {
        return $self->zero() if $left->is_zero();
        return $self->zero() if $right->is_zero();
        return Chalk::Bootstrap::Context->new(
            focus       => true,
            children    => [$left, $right],
            is_zero     => false,
            annotations => { boolean => true },
        );
    }

    # add combines two alternatives. For pure recognition we only care whether
    # at least one alternative succeeded. Deterministic tie-break: return the
    # left operand when both are non-zero. Under FilterComposite, returning
    # $left when both are non-zero means "no preference" — the composite's
    # _filter_compare sees result-equals-left-not-right and defers to the
    # next filter semiring.
    method add($left, $right) {
        return $self->zero() if $left->is_zero() && $right->is_zero();
        return $right if $left->is_zero();
        return $left;
    }

    # slot_name: Boolean reads/writes the 'boolean' annotation slot.
    method slot_name() {
        return 'boolean';
    }
}

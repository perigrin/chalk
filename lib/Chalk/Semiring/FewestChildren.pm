# ABOUTME: Fewest children semiring for disambiguating between alternative parses
# ABOUTME: Prefers parses with fewer top-level children (more cohesive structure)

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;

class Chalk::Semiring::FewestChildrenElement :isa(Chalk::Element) {
    field $valid :param :reader = 1;
    field $child_count :param :reader = 0;
    field $context :param :reader = undef;  # EvalContext for this element

    method add($other, $swap = undef) {
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # If self is invalid, return other
        return $other if !$valid;

        # If other is invalid, return self
        return $self if !$other->valid;

        # Both valid - prefer FEWER children (more cohesive parse)
        if ($other->child_count < $child_count) {
            return $other;
        }

        return $self;
    }

    method multiply($other, $swap = undef) {
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        if (!$valid || !$other->valid) {
            return Chalk::Semiring::FewestChildrenElement->new(valid => 0);
        }

        # Prefer other's context if present, else keep self's context
        my $result_context = defined($other->context) ? $other->context : $context;

        # Sum children
        return Chalk::Semiring::FewestChildrenElement->new(
            valid       => 1,
            child_count => $child_count + $other->child_count,
            context     => $result_context
        );
    }

    method equals($other, $swap = undef) {
        return 0 unless defined $other;
        return 0 unless ref($other) eq ref($self);
        return $valid == $other->valid && $child_count == $other->child_count;
    }

    method score() {
        return $valid ? 1 : 0;
    }

    method to_string(@args) {
        return $valid ? "children:$child_count" : "invalid";
    }
}

class Chalk::Semiring::FewestChildren :isa(Chalk::Semiring) {
    field $mul_id :reader;
    field $add_id :reader;

    ADJUST {
        $add_id = Chalk::Semiring::FewestChildrenElement->new(valid => 0, child_count => 0);
        $mul_id = Chalk::Semiring::FewestChildrenElement->new(valid => 1, child_count => 0);
    }

    method zero() { return $add_id; }
    method one() { return $mul_id; }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef, $ctx = undef) {
        return Chalk::Semiring::FewestChildrenElement->new(
            valid       => 1,
            child_count => 0,
            context     => $ctx
        );
    }

    method multiply($x, $y) { return $x->multiply($y); }
    method plus($x, $y) { return $x->add($y); }

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # If element has context, create new context for scanned terminal
        if (defined($element->context)) {
            my $old_ctx = $element->context;
            my $match_length = length($matched_value // '');

            my $new_ctx = Chalk::EvalContext->new(
                focus     => $matched_value,
                children  => [],  # Terminal has no children
                start_pos => $pos,
                end_pos   => $pos + $match_length,
                env       => $old_ctx->env,
                grammar   => $old_ctx->grammar,
                rule      => $old_ctx->rule,
            );

            my $terminal = Chalk::Semiring::FewestChildrenElement->new(
                valid       => 1,
                child_count => 1,
                context     => $new_ctx
            );
            return $element->multiply($terminal);
        }

        # No context - use existing behavior (backward compatibility)
        my $terminal = Chalk::Semiring::FewestChildrenElement->new(valid => 1, child_count => 1);
        return $element->multiply($terminal);
    }

    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        return $completed_element;
    }
}

1;

# ABOUTME: Position semiring for tracking parse spans without SPPF complexity
# ABOUTME: Provides lightweight position tracking for incomplete parse detection

use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;

class Chalk::Semiring::PositionElement :isa(Chalk::Element) {
    field $start_pos :param :reader;
    field $end_pos   :param :reader;
    field $context :param :reader = undef;  # EvalContext for this element

    method add( $other, $swap = undef ) {
        # Choice: prefer whichever parse consumed more input (span length)
        # This correctly handles ambiguous parses - longer parse is more complete
        my $self_span = $end_pos - $start_pos;
        my $other_span = $other->end_pos - $other->start_pos;

        if ($other_span > $self_span) {
            return $other;
        } elsif ($self_span > $other_span) {
            return $self;
        } else {
            # Tie: prefer earlier start position (parses from beginning)
            return $start_pos <= $other->start_pos ? $self : $other;
        }
    }

    method multiply( $other, $swap = undef ) {
        # Sequence: combine spans [self.start, other.end]
        # Prefer other's context if present, else keep self's context
        my $result_context = defined($other->context) ? $other->context : $context;

        return Chalk::Semiring::PositionElement->new(
            start_pos => $start_pos,
            end_pos   => $other->end_pos,
            context   => $result_context
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return $start_pos == $other->start_pos
            && $end_pos == $other->end_pos;
    }

    method score() {
        # For compatibility - return span length
        return $end_pos - $start_pos;
    }

    method to_string(@args) {
        return "[$start_pos,$end_pos]";
    }
}

class Chalk::Semiring::Position :isa(Chalk::Semiring) {
    # Shared empty context singleton for identity elements
    field $empty_context :reader = Chalk::EvalContext->new(
        focus     => undef,
        children  => [],
        start_pos => 0,
        end_pos   => 0,
        env       => {},
        grammar   => undef,
        rule      => undef,
    );

    # Identity elements
    field $mul_id :reader = Chalk::Semiring::PositionElement->new(
        start_pos => 0,
        end_pos   => 0,
        context   => $empty_context
    );

    field $add_id :reader = Chalk::Semiring::PositionElement->new(
        start_pos => 0,
        end_pos   => 0,
        context   => $empty_context
    );

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef, $ctx = undef) {
        # Always create element with provided positions
        # Use provided context or shared empty context
        return Chalk::Semiring::PositionElement->new(
            start_pos => $start_pos,
            end_pos   => $end_pos,
            context   => defined($ctx) ? $ctx : $empty_context
        );
    }

    method multiply($x, $y) {
        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus($x, $y) {
        # For backward compatibility if called directly
        return $x->add($y);
    }

    method on_complete($completed_item, $completed_element, $metadata_element = undef) {
        # The completed element's span should already be correct from multiply operations
        # Just return it as-is
        return $completed_element;
    }

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        my $match_length = length($matched_value // '');

        # If element has context, create new context for scanned terminal
        if (defined($element->context)) {
            my $old_ctx = $element->context;

            my $new_ctx = Chalk::EvalContext->new(
                focus     => $matched_value,
                children  => [],  # Terminal has no children
                start_pos => $pos,
                end_pos   => $pos + $match_length,
                env       => $old_ctx->env,
                grammar   => $old_ctx->grammar,
                rule      => $old_ctx->rule,
            );

            # Use multiply to properly extend the span
            return $element->multiply(Chalk::Semiring::PositionElement->new(
                start_pos => $pos,
                end_pos   => $pos + $match_length,
                context   => $new_ctx
            ));
        }

        # No context - still need to update positions based on scan
        return $element->multiply(Chalk::Semiring::PositionElement->new(
            start_pos => $pos,
            end_pos   => $pos + $match_length,
            context   => $empty_context
        ));
    }
}

1;

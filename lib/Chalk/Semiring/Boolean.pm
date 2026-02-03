# ABOUTME: Boolean semiring for fast parse validation without position tracking
# ABOUTME: Provides simple true/false parsing for syntax checking similar to perl -c
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;

class Chalk::Semiring::BooleanElement :isa(Chalk::Element) {
    field $value :param :reader;
    field $context :param :reader = undef;

    method add( $other, $swap = undef ) {
        # Boolean OR for choice: either can succeed
        # For Boolean, we prefer to return existing elements when possible
        # to preserve context and match Precedence semiring pattern
        return $self if $value;  # If self is true, return self (preserves context)
        return $other if $other->value;  # If other is true, return other (preserves context)
        return $self;  # Both false, return self
    }

    method multiply( $other, $swap = undef ) {
        # Boolean AND for sequence: both must succeed
        # For Boolean, we prefer to return existing elements when possible
        # to preserve context and match Precedence semiring pattern
        return $self unless $value;  # If self is false, return self (fail fast, preserves context)
        return $other;  # self is true, result is other (preserves other's context)
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        return $value == $other->value;
    }

    method score() {
        return $value;
    }

    method to_string(@args) {
        return $value ? '1' : '0';
    }
}

class Chalk::Semiring::Boolean :isa(Chalk::Semiring) {
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

    # Identity elements for Boolean algebra
    field $mul_id :reader = Chalk::Semiring::BooleanElement->new(value => 1, context => $empty_context);
    field $add_id :reader = Chalk::Semiring::BooleanElement->new(value => 0, context => $empty_context);

    # Keywords from grammar/chalk.bnf line 65
    field $keywords :reader = {
        map { $_ => 1 } qw(
            class field if unless elsif else while until for foreach
            return last next redo my our state use no require
            and or not eq ne lt gt le ge cmp
        )
    };

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Reject keywords when they appear as identifiers
        my $is_identifier = defined($pattern_name) && $pattern_name eq 'IDENTIFIER';
        if ($is_identifier && defined($matched_value) && exists $keywords->{$matched_value}) {
            return $add_id;  # Return 0 (invalid parse)
        }

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

            # Return new element with updated context
            return Chalk::Semiring::BooleanElement->new(
                value => 1,
                context => $new_ctx
            );
        }

        # Otherwise return element unchanged (no context)
        return $element;
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef, $ctx = undef) {
        # If context provided, create element with it
        if (defined($ctx)) {
            return Chalk::Semiring::BooleanElement->new(
                value => 1,
                context => $ctx
            );
        }
        # Otherwise return cached mul_id (no context)
        return $mul_id;
    }

    method multiply($x, $y) {
        # For backward compatibility if called directly
        return $x->multiply($y);
    }

    method plus($x, $y) {
        # For backward compatibility if called directly
        return $x->add($y);
    }
}

1;

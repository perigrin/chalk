# ABOUTME: Boolean semiring for fast parse validation without position tracking
# ABOUTME: Provides simple true/false parsing for syntax checking similar to perl -c
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;

class Chalk::Semiring::BooleanElement :isa(Chalk::Element) {
    field $value :param :reader;
    field $semiring_add_id :param :reader = undef;  # Cached add_id from parent
    field $semiring_mul_id :param :reader = undef;  # Cached mul_id from parent
    field $context :param :reader = undef;          # EvalContext for this element

    ADJUST {
        # Identity elements are self-referential
        $semiring_add_id //= $self;
        $semiring_mul_id //= $self;
    }

    method add( $other, $swap = undef ) {
        # Boolean OR for choice: either can succeed
        # CONTRACT: Return $self or $other directly (not copies) to enable
        # Composite::add() reference equality checks for consensus detection
        my $result_value = $value || $other->value;

        # INSTRUMENTATION: Log Boolean.add() decisions
        if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
            my $self_val = $value ? 1 : 0;
            my $other_val = $other->value ? 1 : 0;
            warn "[BOOLEAN.add] self=$self_val vs other=$other_val\n";
        }

        # Return original reference when it matches the result
        if ($value == $result_value) {
            if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
                warn "[BOOLEAN.add]   => Choosing SELF\n";
            }
            return $self;
        }
        if ($other->value == $result_value) {
            if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
                warn "[BOOLEAN.add]   => Choosing OTHER\n";
            }
            return $other;
        }

        # Both false - return cached add_id
        if ($ENV{DEBUG_PARSE_ALTERNATIVES}) {
            warn "[BOOLEAN.add]   => Both false, returning add_id\n";
        }
        return $semiring_add_id;
    }

    method multiply( $other, $swap = undef ) {
        if ($ENV{DEBUG_CONTEXT}) {
            warn "[BOOLEAN.multiply] CALLED\n";
        }

        # Boolean AND for sequence: both must succeed
        my $result_value = $value && $other->value;

        # Return cached add_id if result is false (avoids creating new add_id instances)
        unless ($result_value) {
            if ($ENV{DEBUG_CONTEXT}) {
                warn "[BOOLEAN.multiply] result is FALSE, returning add_id\n";
            }
            return $semiring_add_id;
        }

        # Build new context from left + right contexts
        # Handle case where one or both elements don't have contexts
        my $new_context = undef;
        my $left_ctx = $context;
        my $right_ctx = $other->context;

        if ($ENV{DEBUG_CONTEXT}) {
            my $left_has = defined($left_ctx) ? "YES" : "NO";
            my $right_has = defined($right_ctx) ? "YES" : "NO";
            warn "[BOOLEAN.multiply] left_ctx=$left_has right_ctx=$right_has\n";
        }

        if (defined($left_ctx) || defined($right_ctx)) {
            # At least one has a context, build combined context
            # Use dummy values for missing contexts
            my @children;
            push @children, $left_ctx if defined($left_ctx);
            push @children, $right_ctx if defined($right_ctx);

            # Get positions and metadata from available context
            my $ctx_for_meta = $left_ctx // $right_ctx;

            if ($ENV{DEBUG_CONTEXT}) {
                warn "[BOOLEAN.multiply] Building context with " . scalar(@children) . " children\n";
            }

            $new_context = Chalk::EvalContext->new(
                focus     => $result_value,
                children  => \@children,
                start_pos => defined($left_ctx) ? $left_ctx->start_pos : 0,
                end_pos   => defined($right_ctx) ? $right_ctx->end_pos : 0,
                env       => $ctx_for_meta->env,
                grammar   => $ctx_for_meta->grammar,
                rule      => $ctx_for_meta->rule,
            );
        }

        # Always return new element with combined context if true
        # (Don't use cached mul_id for prototype - we need fresh elements)
        return Chalk::Semiring::BooleanElement->new(
            value => 1,
            semiring_add_id => $semiring_add_id,
            semiring_mul_id => $semiring_mul_id,
            context => $new_context
        );
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
    # Identity elements for Boolean algebra - self-referential via ADJUST
    field $mul_id :reader = Chalk::Semiring::BooleanElement->new(value => 1);
    field $add_id :reader = Chalk::Semiring::BooleanElement->new(value => 0);

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
        if ($is_identifier && defined($matched_value)) {
            my $token_value = ref($matched_value) && $matched_value->can('value') ? $matched_value->value : $matched_value;
            if (exists $keywords->{$token_value}) {
                return $add_id;  # Return 0 (invalid parse)
            }
        }

        if ($ENV{DEBUG_CONTEXT}) {
            my $has_ctx = defined($element->context) ? "YES" : "NO";
            warn "[BOOLEAN.on_scan] pos=$pos value='$matched_value' element_has_ctx=$has_ctx\n";
        }

        # For prototype: create context for scanned terminal
        # If element already has a context, use it as base
        if (defined($element->context)) {
            my $old_ctx = $element->context;
            my $match_length = length($matched_value);

            # Create new context for the scanned terminal with updated end position
            my $new_ctx = Chalk::EvalContext->new(
                focus     => $matched_value,
                children  => [],  # Terminal has no children
                start_pos => $pos,
                end_pos   => $pos + $match_length,
                env       => $old_ctx->env,
                grammar   => $old_ctx->grammar,
                rule      => $old_ctx->rule,
            );

            if ($ENV{DEBUG_CONTEXT}) {
                warn "[BOOLEAN.on_scan] Created new context: " . $new_ctx->to_string . "\n";
            }

            return Chalk::Semiring::BooleanElement->new(
                value => 1,
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                context => $new_ctx
            );
        }

        # Otherwise return element unchanged (backward compatibility)
        return $element;
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef, $ctx = undef) {
        # All rules start as true (1) - they exist and can be used
        # If context is provided, create new element with it
        if (defined($ctx)) {
            return Chalk::Semiring::BooleanElement->new(
                value => 1,
                semiring_add_id => $add_id,
                semiring_mul_id => $mul_id,
                context => $ctx
            );
        }
        # Return cached mul_id to avoid creating new instances (backward compatibility)
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

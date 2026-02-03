# ABOUTME: Generic semantic validation semiring for parse-time constraint checking
# ABOUTME: Validates semantic constraints using pluggable grammar-specific rules
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::EvalContext;

class Chalk::Semiring::SemanticValidationElement :isa(Chalk::Element) {
    use overload '""' => 'to_string';

    field $valid :param :reader;  # Boolean: 1 = semantically valid, 0 = invalid
    field $type :param :reader = undef;  # Inferred type (if known) - reserved for future use
    field $sppf_node :param :reader = undef;  # SPPF node for examining parse structure
    field $forest :param :reader = undef;  # Reference to SPPF forest
    field $rules :param :reader = undef;  # Grammar-specific semantic rules
    field $errors :param :reader = [];  # Accumulated error messages (arrayref)
    field $start_pos :param :reader = 0;  # Start position for error reporting
    field $end_pos :param :reader = 0;  # End position for error reporting
    field $context :param :reader = undef;  # EvalContext for this element

    method to_string(@args) {
        return $valid ? 'valid' : 'invalid';
    }

    method score() {
        return $valid ? 1 : 0;
    }

    method equals($other, $swap = undef) {
        return 0 unless ref($other) eq ref($self);
        return 0 unless $valid == $other->valid;

        # Compare types if both are defined (reserved for future type inference)
        if (defined($type) && defined($other->type)) {
            return 0 unless $type->equals($other->type);
        } elsif (defined($type) || defined($other->type)) {
            return 0;  # One defined, one not - not equal
        }

        return 1;
    }

    method add($other, $swap = undef) {
        # Choose between alternative parses based on semantic validity
        # Similar pattern to Precedence semiring

        # Handle undef or wrong type
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # Merge errors from both alternatives
        my @merged_errors = ($errors->@*, ($other->can('errors') ? $other->errors->@* : ()));

        # If self is invalid (add_id), return other
        return $other if !$valid;

        # If other is invalid, return self
        return $self if !$other->valid;

        # Both marked valid initially - validate their semantic constraints
        my $self_valid = $self->_validate_semantic_constraints();
        my $other_valid = $other->_validate_semantic_constraints();

        if ($self_valid && !$other_valid) {
            return $self;
        } elsif ($other_valid && !$self_valid) {
            return $other;
        } elsif (!$self_valid && !$other_valid) {
            # Neither valid - return invalid element with errors
            push @merged_errors, {
                type => 'semantic_validation_failed',
                message => 'No valid semantic alternative found',
                start_pos => $start_pos,
                end_pos => $end_pos
            };
            return Chalk::Semiring::SemanticValidationElement->new(
                valid => 0,
                forest => $forest,
                rules => $rules,
                errors => \@merged_errors,
                start_pos => $start_pos,
                end_pos => $end_pos
            );
        } else {
            # Both valid - prefer self (first alternative)
            return $self;
        }
    }

    method _validate_semantic_constraints() {
        # If no SPPF node, assume valid
        return 1 unless $sppf_node;

        # If no rules provided, assume valid
        return 1 unless $rules;

        # Get all packed alternatives
        my @packed_nodes = $sppf_node->packed_nodes;
        return 1 unless @packed_nodes;

        # Check if ANY packed alternative is semantically valid
        for my $packed (@packed_nodes) {
            if ($rules->validate($packed)) {
                return 1;
            }
        }

        return 0;  # No valid alternatives
    }

    method multiply($other, $swap = undef) {
        # Prefer other's context if present, else keep self's context
        my $result_context = defined($other) && ref($other) && $other->can('context') && defined($other->context) ? $other->context : $context;

        # Semantic validation doesn't need special multiply logic
        # Just combine the elements
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # Merge errors from both operands
        my @new_errors = ($errors->@*, ($other->can('errors') ? $other->errors->@* : ()));

        # Calculate combined position span
        my $other_start = $other->can('start_pos') ? $other->start_pos : 0;
        my $other_end = $other->can('end_pos') ? $other->end_pos : 0;
        my $new_start = $start_pos < $other_start ? $start_pos : $other_start;
        my $new_end = $end_pos > $other_end ? $end_pos : $other_end;

        # If either is invalid, result is invalid
        if (!$valid || !$other->valid) {
            return Chalk::Semiring::SemanticValidationElement->new(
                valid => 0,
                forest => $forest,
                rules => $rules,
                errors => \@new_errors,
                start_pos => $new_start,
                end_pos => $new_end
            );
        }

        # Both valid - return new element with combined errors and positions
        return Chalk::Semiring::SemanticValidationElement->new(
            valid => 1,
            sppf_node => $sppf_node,
            forest => $forest,
            rules => $rules,
            errors => \@new_errors,
            start_pos => $new_start,
            end_pos => $new_end,
            context => $result_context
        );
    }

    # Check if any errors have been recorded
    method has_errors() {
        return scalar($errors->@*) > 0;
    }

    # Format errors for display
    method format_errors($input_string = undef) {
        return '' unless $self->has_errors();

        my @lines;
        for my $err ($errors->@*) {
            my $msg = $err->{message} // 'Unknown error';
            my $pos = $err->{start_pos} // 0;

            # Calculate line/column from position if input string provided
            if (defined $input_string && $pos > 0) {
                my $line = 1;
                my $col = 1;
                for my $i (0 .. $pos - 1) {
                    if (substr($input_string, $i, 1) eq "\n") {
                        $line++;
                        $col = 1;
                    } else {
                        $col++;
                    }
                }
                push @lines, "Line $line, Col $col: $msg";
            } else {
                push @lines, "Position $pos: $msg";
            }
        }
        return join("\n", @lines);
    }
}

class Chalk::Semiring::SemanticValidation :isa(Chalk::Semiring) {
    field $rules :param :reader = undef;  # Grammar-specific semantic rules
    field $forest :reader = undef;  # Shared SPPF forest
    field $shared_context :param = undef;
    field $empty_context :reader;  # Shared empty context for identity elements
    field $mul_id :reader;  # Multiplicative identity (one)
    field $add_id :reader;  # Additive identity (zero)
    field @collected_errors;  # Errors collected during parsing

    ADJUST {
        # Extract forest from shared_context if provided
        if ($shared_context && ref($shared_context) eq 'HASH') {
            $forest = $shared_context->{forest};
        }

        # Create shared empty context for identity elements
        $empty_context = Chalk::EvalContext->new(
            focus     => undef,
            children  => [],
            start_pos => 0,
            end_pos   => 0,
            env       => {},
            grammar   => undef,
            rule      => undef,
        );

        # Initialize identity elements
        $add_id = Chalk::Semiring::SemanticValidationElement->new(
            valid => 0,
            forest => $forest,
            rules => $rules,
            errors => [],
            start_pos => 0,
            end_pos => 0,
            context => $empty_context
        );

        $mul_id = Chalk::Semiring::SemanticValidationElement->new(
            valid => 1,
            forest => $forest,
            rules => $rules,
            errors => [],
            start_pos => 0,
            end_pos => 0,
            context => $empty_context
        );
    }

    method zero() {
        return $add_id;
    }

    method one() {
        return $mul_id;
    }

    method from_symbol($symbol, $start_pos, $end_pos, $sppf_node = undef) {
        # Find the corresponding SPPF node if we have a forest
        my $actual_sppf_node = $sppf_node;

        if ($forest && !$actual_sppf_node) {
            my $key = "${symbol}|${start_pos}|${end_pos}";
            my $nodes = $forest->nodes;
            $actual_sppf_node = $nodes->{$key};
        }

        return Chalk::Semiring::SemanticValidationElement->new(
            valid => 1,
            sppf_node => $actual_sppf_node,
            forest => $forest,
            rules => $rules,
            errors => [],
            start_pos => $start_pos,
            end_pos => $end_pos
        );
    }

    method from_terminal($symbol, $start_pos, $end_pos) {
        # Terminals are always valid
        return Chalk::Semiring::SemanticValidationElement->new(
            valid => 1,
            forest => $forest,
            rules => $rules,
            errors => [],
            start_pos => $start_pos,
            end_pos => $end_pos
        );
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef, $ctx = undef) {
        # If context provided, create element with it
        if (defined($ctx)) {
            return Chalk::Semiring::SemanticValidationElement->new(
                valid => 1,
                forest => $forest,
                rules => $rules,
                errors => [],
                start_pos => $start_pos,
                end_pos => $end_pos,
                context => $ctx
            );
        }
        # Otherwise return cached mul_id (no context)
        return $mul_id;
    }

    # Collect an error for later retrieval
    method collect_error($error) {
        push @collected_errors, $error;
    }

    # Get all collected errors
    method collected_errors() {
        return @collected_errors;
    }

    # Clear collected errors (for new parse)
    method clear_errors() {
        @collected_errors = ();
    }

    # Called when a token is scanned - create context for terminal
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

            return Chalk::Semiring::SemanticValidationElement->new(
                valid => 1,
                forest => $forest,
                rules => $rules,
                errors => [],
                start_pos => $pos,
                end_pos => $pos + $match_length,
                context => $new_ctx
            );
        }

        # No context - return element unchanged (backward compatibility)
        return $element;
    }
}

1;

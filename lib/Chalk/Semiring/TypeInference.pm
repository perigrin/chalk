# ABOUTME: Type Inference semiring for semantic validation during parsing
# ABOUTME: Validates type correctness and semantic constraints like statement modifiers
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::TypeInferenceElement :isa(Chalk::Element) {
    use overload '""' => 'to_string';

    field $valid :param :reader;  # Boolean: 1 = semantically valid, 0 = invalid
    field $type :param :reader = undef;  # Inferred type (if known)
    field $sppf_node :param :reader = undef;  # SPPF node for examining parse structure
    field $forest :param :reader = undef;  # Reference to SPPF forest
    field $context :param :reader = undef;  # Parse context for rule information

    method to_string(@args) {
        return $valid ? 'valid' : 'invalid';
    }

    method score() {
        return $valid ? 1 : 0;
    }

    method equals($other, $swap = undef) {
        return 0 unless ref($other) eq ref($self);
        return 0 unless $valid == $other->valid;

        # Compare types if both are defined
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
            # Neither valid - return add_id
            return Chalk::Semiring::TypeInferenceElement->new(
                valid => 0,
                forest => $forest
            );
        } else {
            # Both valid - prefer self (first alternative)
            return $self;
        }
    }

    method _validate_semantic_constraints() {
        # If no SPPF node, assume valid
        return 1 unless $sppf_node;

        # Get all packed alternatives
        my @packed_nodes = $sppf_node->packed_nodes;
        return 1 unless @packed_nodes;

        # Check if ANY packed alternative is semantically valid
        for my $packed (@packed_nodes) {
            if ($self->_validate_packed_node($packed)) {
                return 1;
            }
        }

        return 0;  # No valid alternatives
    }

    method _validate_packed_node($packed) {
        my $rule = $packed->rule;
        return 1 unless $rule;  # Non-rule nodes valid by default

        # VALIDATION: Statement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
        # This is the postfix conditional modifier rule
        # It should NOT apply when the base Statement is already a block-form conditional
        if ($rule->lhs eq 'Statement' && $self->_is_postfix_conditional_rule($rule)) {
            return $self->_validate_postfix_conditional($packed);
        }

        # Add more validation rules here as needed
        # - Type checking for operations
        # - Return type validation
        # - Variable scope validation
        # etc.

        return 1;  # Default: valid
    }

    method _is_postfix_conditional_rule($rule) {
        # Check if this is: Statement -> Statement WS_OPT ConditionalKeyword WS_OPT Expression
        my $rhs = $rule->rhs;
        return 0 unless $rhs && ref($rhs) eq 'ARRAY';
        return 0 unless scalar($rhs->@*) == 5;

        return ($rhs->[0] eq 'Statement' &&
                $rhs->[1] eq 'WS_OPT' &&
                $rhs->[2] eq 'ConditionalKeyword' &&
                $rhs->[3] eq 'WS_OPT' &&
                $rhs->[4] eq 'Expression');
    }

    method _validate_postfix_conditional($packed) {
        my @children = $packed->children;
        return 1 unless @children;

        # First child should be the base Statement
        my $base_stmt_node = $children[0];
        return 1 unless $base_stmt_node && $base_stmt_node->isa('Chalk::ParseForest::SymbolNode');

        # Check if base statement is a Block (which includes ConditionalStatement)
        # If it is, this postfix application is INVALID
        return !$self->_statement_is_block_form($base_stmt_node);
    }

    method _statement_is_block_form($stmt_node) {
        # Check if Statement -> Block
        my @packed = $stmt_node->packed_nodes;
        return 0 unless @packed;

        for my $packed (@packed) {
            my $rule = $packed->rule;
            next unless $rule;

            # Statement -> Block rule
            if ($rule->lhs eq 'Statement' && $self->_is_block_rule($rule)) {
                return 1;  # Yes, this is a block-form statement
            }
        }

        return 0;  # Not a block-form statement
    }

    method _is_block_rule($rule) {
        my $rhs = $rule->rhs;
        return 0 unless $rhs && ref($rhs) eq 'ARRAY';
        return 0 unless scalar($rhs->@*) == 1;
        return $rhs->[0] eq 'Block';
    }

    method multiply($other, $swap = undef) {
        # Type inference doesn't need special multiply logic
        # Just combine the elements
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # If either is invalid, result is invalid
        if (!$valid || !$other->valid) {
            return Chalk::Semiring::TypeInferenceElement->new(
                valid => 0,
                forest => $forest
            );
        }

        # Both valid - return self (could do type unification here later)
        return $self;
    }
}

class Chalk::Semiring::TypeInference :isa(Chalk::Semiring) {
    field $forest :reader = undef;  # Shared SPPF forest
    field $shared_context :param = undef;
    field $mul_id :reader;  # Multiplicative identity (one)
    field $add_id :reader;  # Additive identity (zero)

    ADJUST {
        # Extract forest from shared_context if provided
        if ($shared_context && ref($shared_context) eq 'HASH') {
            $forest = $shared_context->{forest};
        }

        # Initialize identity elements
        $add_id = Chalk::Semiring::TypeInferenceElement->new(
            valid => 0,
            forest => $forest
        );

        $mul_id = Chalk::Semiring::TypeInferenceElement->new(
            valid => 1,
            forest => $forest
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

        return Chalk::Semiring::TypeInferenceElement->new(
            valid => 1,
            sppf_node => $actual_sppf_node,
            forest => $forest
        );
    }

    method from_terminal($symbol, $start_pos, $end_pos) {
        # Terminals are always valid
        return $self->one();
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # All rules start as valid (1) - they are syntactically correct
        # Semantic validation happens in add() when choosing between alternatives
        return $self->one();
    }
}

1;

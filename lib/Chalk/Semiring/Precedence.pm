# ABOUTME: Precedence semiring for operator precedence validation during parsing
# ABOUTME: Implements proactive pruning via precedence table with left/right associativity
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

class Chalk::Semiring::PrecedenceElement :isa(Chalk::Element) {
    field $valid :param :reader;  # Boolean: 1 = valid precedence, 0 = invalid
    field $operator :param :reader = undef;  # Operator symbol (if known)
    field $precedence_level :param :reader = undef;  # Index in precedence table
    field $associativity :param :reader = undef;  # Associativity type: left, right, nonassoc, chained, chain/na
    field $forest :param :reader = undef;  # Reference to SPPF forest for examining parse structure (optional)
    field $sppf_node :param :reader = undef;  # SPPF node for this element's parse
    field $start_pos :param :reader = undef;  # Parse span start
    field $end_pos :param :reader = undef;    # Parse span end
    field $operator_index :param :reader = undef;  # Hash mapping operators to precedence info

    # Lookup operator precedence and associativity from operator_index
    method lookup_operator($op) {
        return unless $operator_index;
        return $operator_index->{$op};
    }

    method add( $other, $swap = undef ) {
        # Choose between alternative parses based on precedence validation
        # $self and $other represent two different parse alternatives
        # Return the one with valid precedence, or add_id if neither is valid

        # Handle undef or wrong type for $other
        return $self unless defined $other;
        return $self unless ref($other) && $other->can('valid');

        # If self is already invalid (add_id), return other
        return $other if !$valid;

        # If other is invalid, return self
        return $self if !$other->valid;

        # Both marked as valid initially - need to validate their SPPF structures
        # If we don't have SPPF nodes, can't validate - use simple preference
        my $self_has_sppf = $sppf_node && defined($start_pos) && defined($end_pos);
        my $other_has_sppf = $other->sppf_node && defined($other->start_pos) && defined($other->end_pos);

        return $self unless $self_has_sppf || $other_has_sppf;

        # Validate each alternative's precedence structure
        my $self_valid = $self->_validate_element_precedence();
        my $other_valid = $other->_validate_element_precedence();

        # Return based on validation results
        if ($self_valid && !$other_valid) {
            return $self;
        } elsif ($other_valid && !$self_valid) {
            return $other;
        } elsif ($self_valid && $other_valid) {
            # Both valid - prefer the one with SPPF (has precedence info)
            # If only one has SPPF, prefer that one
            if ($self_has_sppf && !$other_has_sppf) {
                return $self;
            } elsif ($other_has_sppf && !$self_has_sppf) {
                return $other;
            } else {
                # Both have SPPF or neither - prefer self (first alternative)
                return $self;
            }
        } else {
            # Neither valid - return add_id to mark parse as invalid
            return Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index);
        }
    }

    # Validate this element's SPPF structure for precedence correctness
    method _validate_element_precedence() {
        # If no SPPF node, assume valid (can't validate what we don't have)
        return 1 unless $sppf_node;

        # Get all packed alternatives for this SPPF node
        my @packed_nodes = $sppf_node->packed_nodes;
        return 1 unless @packed_nodes;  # No alternatives = valid

        # Check if ANY packed alternative has valid precedence
        # (The SPPF may have multiple alternatives, we just need one valid one)
        for my $packed (@packed_nodes) {
            if ($self->_validate_packed_node_precedence($packed)) {
                return 1;  # Found at least one valid alternative
            }
        }

        return 0;  # No valid alternatives found
    }

    # Helper: Validate precedence of a packed node alternative
    method _validate_packed_node_precedence($packed) {
        my $rule = $packed->rule;
        return 1 unless $rule;  # Non-rule nodes are always valid

        # Only validate ArithmeticOp rules
        return 1 unless $rule->lhs eq 'ArithmeticOp';

        # Get operator and children from packed node
        my @children = $packed->children;
        return 1 unless @children;  # No children = valid

        # Extract operator from composite_element on PackedNode (contains actual matched value)
        my $operator;
        my $current_level;

        if ($packed->can('composite_element') && $packed->composite_element) {
            my $comp_elem = $packed->composite_element;
            if ($comp_elem->can('elements')) {
                my @elements = $comp_elem->elements->@*;
                # Find the Precedence element (usually at index 1 after SPPF)
                for my $elem (@elements) {
                    if ($elem->can('operator') && defined($elem->operator)) {
                        $operator = $elem->operator;
                        my $op_info = $self->lookup_operator($operator);
                        $current_level = $op_info->{level} if $op_info;
                        last;
                    }
                }
            }
        }

        # FAIL CLOSED: If we can't find the operator in an ArithmeticOp rule, that's invalid
        return 0 unless defined($operator) && defined($current_level);

        # Check left and right children for nested operators
        # Children are SPPF nodes - need to extract their operators recursively
        for my $child (@children) {
            next unless $child;
            next unless $child->can('symbol');  # Only SymbolNodes have symbol
            next unless $child->symbol eq 'ArithmeticOp';

            # This child is an ArithmeticOp - extract its operator
            my $child_op = $self->_extract_operator_from_node($child);
            next unless $child_op;

            my $child_op_info = $self->lookup_operator($child_op);
            next unless $child_op_info;
            my $child_level = $child_op_info->{level};

            # Precedence rule: Lower precedence (higher level number) cannot be child of higher precedence (lower level number)
            # Example: (1+2)*3 is INVALID because + (level 6) is child of * (level 5)
            # Example: 1+(2*3) is VALID because * (level 5) is child of + (level 6)
            if ($child_level > $current_level) {
                # Child has lower precedence than parent - INVALID
                return 0;
            }
        }

        return 1;  # All precedence checks passed
    }

    # Helper: Extract operator from an SPPF node by examining its packed alternatives
    method _extract_operator_from_node($node) {
        return undef unless $node->can('packed_nodes');

        my @packed = $node->packed_nodes;
        return undef unless @packed;

        # Check first packed node's composite_element for operator
        my $first_packed = $packed[0];

        if ($first_packed->can('composite_element') && $first_packed->composite_element) {
            my $comp_elem = $first_packed->composite_element;
            if ($comp_elem->can('elements')) {
                my @elements = $comp_elem->elements->@*;
                # Find the Precedence element with operator information
                for my $elem (@elements) {
                    if ($elem->can('operator') && defined($elem->operator)) {
                        return $elem->operator;
                    }
                }
            }
        }

        return undef;
    }

    # Prune invalid alternatives from IntermediateNodes in SPPF
    # This mutates the SPPF to remove parse alternatives that violate precedence rules
    method _prune_invalid_intermediate_node_alternatives($node, $visited = {}) {
        return unless $node && $node->can('packed_nodes');

        # Cycle detection: check if we've already visited this node
        my $node_key = refaddr($node);
        return if $visited->{$node_key};
        $visited->{$node_key} = 1;

        my @packed = $node->packed_nodes;
        return unless @packed;

        # Traverse each PackedNode to find IntermediateNode children
        for my $packed_node (@packed) {
            my @children = $packed_node->children;

            for my $child (@children) {
                next unless $child;

                # Check if child is IntermediateNode (has rule_label method)
                if ($child->can('rule_label')) {
                    # This is an IntermediateNode - prune its invalid alternatives
                    $self->_prune_intermediate_node_packed_alternatives($child);
                }

                # Recursively process child nodes with visited tracking
                $self->_prune_invalid_intermediate_node_alternatives($child, $visited);
            }
        }
    }

    # Prune invalid PackedNode alternatives from a specific IntermediateNode
    method _prune_intermediate_node_packed_alternatives($intermediate_node) {
        my @packed = $intermediate_node->packed_nodes;
        return unless @packed > 1;  # Nothing to prune if only one alternative

        # Check each PackedNode to see if it represents valid precedence
        my @valid_indices;
        for my $i (0..$#packed) {
            my $packed_node = $packed[$i];

            # Determine if this alternative is valid by extracting its operator
            # and checking precedence rules
            my $is_valid = $self->_is_intermediate_packed_node_valid($packed_node, $intermediate_node);

            if ($is_valid) {
                push @valid_indices, $i;
            }
        }

        # Prune: keep only valid alternatives
        if (@valid_indices && @valid_indices < @packed) {
            $intermediate_node->prune_packed_nodes(sub {
                my ($node) = @_;
                # Check if this node is in our valid list by reference address
                my $node_addr = refaddr($node);
                for my $i (@valid_indices) {
                    return 1 if refaddr($packed[$i]) == $node_addr;
                }
                return 0;
            });
        }
    }

    # Extract operator from IntermediateNode PackedNode by examining partition boundary in source
    # The partition boundary tells us where the operator split occurs
    method _extract_operator_from_intermediate_packed_node($packed_node) {
        return undef unless $forest;

        # Get input string from forest
        my $input = $forest->input_string;
        return undef unless defined $input;

        # Get the partition boundary from the first child's end_pos
        my @children = $packed_node->children;
        return undef unless @children;

        my $first_child = $children[0];
        return undef unless $first_child && $first_child->can('end_pos');

        my $boundary = $first_child->end_pos;

        # Search backwards from boundary to find arithmetic operator
        # The grammar is: Expression WS_OPT OPERATOR WS_OPT Expression
        # So the operator should be a few characters before the boundary
        # TODO: Make this more general for other operator types
        for (my $pos = $boundary - 1; $pos >= 0 && $pos >= $boundary - 10; $pos--) {
            my $char = substr($input, $pos, 1);

            # Check if this is an arithmetic operator
            if ($char =~ /[+\-*\/]/) {
                return $char;
            }
        }

        return undef;
    }

    # Check if a PackedNode alternative within an IntermediateNode is valid
    method _is_intermediate_packed_node_valid($packed_node, $intermediate_node) {
        # Check for malformed alternative: first child spans entire parent range
        my @children = $packed_node->children;
        if (@children > 0) {
            my $first_child = $children[0];
            if ($first_child && $first_child->can('end_pos')) {
                my $boundary = $first_child->end_pos;
                # If boundary >= parent's end, there's no room for a valid right child
                return 0 if $boundary >= $intermediate_node->end_pos;
            }
        }

        # Extract operator from this IntermediateNode PackedNode alternative
        my $operator = $self->_extract_operator_from_intermediate_packed_node($packed_node);

        # If we can't find operator, assume valid (not an operator alternative)
        return 1 unless defined($operator);

        # Look up precedence info
        my $op_info = $self->lookup_operator($operator);
        return 1 unless $op_info;  # Unknown operator = assume valid
        my $current_level = $op_info->{level};

        # Check children for precedence violations using forest node registry
        # Get the spans covered by children to find nested operators
        for my $child (@children) {
            next unless $child;
            next unless $child->can('start_pos') && $child->can('end_pos');

            my $child_start = $child->start_pos;
            my $child_end = $child->end_pos;

            # Look for any ArithmeticOp nodes in the forest within this child's span
            # TODO: Generalize to handle ComparisonOp, LogicalOp, etc.
            my $child_op = $self->_find_operator_in_span($child_start, $child_end, 'ArithmeticOp');
            next unless $child_op;

            my $child_op_info = $self->lookup_operator($child_op);
            next unless $child_op_info;
            my $child_level = $child_op_info->{level};

            # Precedence rule: Lower precedence (higher level) cannot be child of higher precedence (lower level)
            # Example: (1+2)*3 is invalid because + (level 6) is child of * (level 5)
            if ($child_level > $current_level) {
                return 0;  # Invalid precedence
            }
        }

        return 1;  # Valid
    }

    # Helper: Find operator nodes in forest within a given span
    method _find_operator_in_span($start, $end, $node_type) {
        return undef unless $forest;

        my @all_nodes = values %{$forest->nodes};

        # Find all nodes of the specified type within the span
        my @matching = grep {
            $_->can('symbol') &&
            $_->symbol eq $node_type &&
            $_->start_pos >= $start &&
            $_->end_pos <= $end &&
            ($_->start_pos != $start || $_->end_pos != $end)  # Exclude self
        } @all_nodes;

        # If we found any, extract the operator from the first one
        for my $node (@matching) {
            my $op = $self->_extract_operator_from_node($node);
            return $op if $op;
        }

        return undef;
    }

    method multiply( $other, $swap = undef ) {
        # Handle undef or wrong type for $other
        return Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index) unless defined $other;
        return Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index) unless ref($other) && $other->can('valid');

        # Boolean AND for sequence: both must succeed
        # If either is invalid, result is invalid
        return Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index) if !$valid || !$other->valid;

        # Precedence validation: check if $other (right operand) has valid precedence
        # relative to $self (left context/current operator)

        # Extract operator info from SPPF if not already set
        # This handles the case where multiply() is called before on_complete()
        my $self_op = $operator;
        my $self_level = $precedence_level;
        my $self_assoc = $associativity;

        if (!defined($self_op) && $sppf_node) {
            $self_op = $self->_extract_operator_from_node($sppf_node);
            if ($self_op) {
                my $op_info = $self->lookup_operator($self_op);
                if ($op_info) {
                    $self_level = $op_info->{level};
                    $self_assoc = $op_info->{assoc};
                }
            }
        }

        my $other_op = $other->operator;
        my $other_level = $other->precedence_level;
        my $other_assoc = $other->associativity;

        if (!defined($other_op) && $other->sppf_node) {
            $other_op = $self->_extract_operator_from_node($other->sppf_node);
            if ($other_op) {
                my $op_info = $self->lookup_operator($other_op);
                if ($op_info) {
                    $other_level = $op_info->{level};
                    $other_assoc = $op_info->{assoc};
                }
            }
        }

        # If either element has no operator info, preserve the one that does
        if (!defined($self_op) && !defined($other_op)) {
            # Neither has operator - return plain valid element
            return Chalk::Semiring::PrecedenceElement->new(valid => 1, forest => $forest, operator_index => $operator_index);
        } elsif (!defined($self_op)) {
            # Other has operator, self doesn't - preserve other's operator
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $other_op,
                precedence_level => $other_level,
                associativity => $other_assoc,
                forest => $forest,
                operator_index => $operator_index
            );
        } elsif (!defined($other_op)) {
            # Self has operator, other doesn't - preserve self's operator
            return Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $self_op,
                precedence_level => $self_level,
                associativity => $self_assoc,
                forest => $forest,
                operator_index => $operator_index
            );
        }

        # Both have operators - validate based on precedence and associativity

        # Rule 1: Higher precedence (lower level) on LEFT with lower precedence (higher level) on RIGHT is INVALID
        # Example: (a + b) * c where + is on left and * should bind tighter - WRONG parse
        if ($self_level < $other_level) {
            # self has higher precedence (lower level), other has lower precedence (higher level)
            # This is invalid sequencing
            return Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index);
        }

        # Rule 2: Lower precedence (higher level) on LEFT with higher precedence (lower level) on RIGHT is VALID
        # Example: (a * b) + c where * is on left and + binds less tightly - CORRECT parse
        if ($self_level > $other_level) {
            # self has lower precedence (higher level), other has higher precedence (lower level)
            # This is valid sequencing
            return Chalk::Semiring::PrecedenceElement->new(valid => 1, forest => $forest, operator_index => $operator_index);
        }

        # Same precedence level - check associativity rules
        # Rule 3: nonassoc operators cannot chain with themselves
        if (defined($self_assoc) && $self_assoc eq 'nonassoc') {
            # nonassoc operators at same level cannot chain
            if ($self_op eq $other_op) {
                return Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index);
            }
        }

        # Rule 4: chained comparisons must maintain directional consistency
        if (defined($self_assoc) && $self_assoc eq 'chained') {
            # Determine direction of operators
            my $self_dir = _operator_direction($self_op);
            my $other_dir = _operator_direction($other_op);

            # If both have directions, they must match
            if (defined($self_dir) && defined($other_dir) && $self_dir ne $other_dir) {
                return Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index);
            }
        }

        # Rule 5: chain/na allows chaining (like chained but context-dependent)
        # For now, treat same as chained - allow chaining
        if (defined($self_assoc) && $self_assoc eq 'chain/na') {
            # Allow chaining
            return Chalk::Semiring::PrecedenceElement->new(valid => 1, forest => $forest, operator_index => $operator_index);
        }

        # Rule 6: left and right associativity (existing behavior)
        # left: disallow equal precedence on right (already handled by "cannot be lower")
        # right: allow equal precedence on right (needs explicit check)
        # Default: valid
        return Chalk::Semiring::PrecedenceElement->new(valid => 1, forest => $forest, operator_index => $operator_index);
    }

    # Helper: Determine comparison operator direction
    sub _operator_direction {
        my ($op) = @_;
        # Use hash lookup to avoid < and > in regex patterns (confuses Chalk parser)
        my %ascending = ('<' => 1, '<=' => 1, 'lt' => 1, 'le' => 1);
        my %descending = ('>' => 1, '>=' => 1, 'gt' => 1, 'ge' => 1);
        return 'asc' if exists $ascending{$op};
        return 'desc' if exists $descending{$op};
        return undef;  # No direction (e.g., ==, !=)
    }

    method equals( $other, $swap = undef ) {
        return 0 unless defined $other;
        return 0 unless ref($other) eq ref($self);
        return $valid == $other->valid;
    }

    method score() {
        return $valid;
    }

    method to_string(@args) {
        my $op_str = defined($operator) ? " op=$operator" : "";
        my $prec_str = defined($precedence_level) ? " prec=$precedence_level" : "";
        return $valid ? "1${op_str}${prec_str}" : "0${op_str}${prec_str}";
    }
}

class Chalk::Semiring::Precedence :isa(Chalk::Semiring) {
    field $precedence_table :param :reader;
    field $shared_context :param :reader = undef;
    field $forest :reader;
    field $mul_id :reader;
    field $add_id :reader;
    field $operator_index :reader;  # Hash: operator -> index in precedence table

    ADJUST {
        # Extract forest from shared_context if provided
        $forest = defined($shared_context) && exists($shared_context->{forest})
            ? $shared_context->{forest}
            : undef;

        # Build operator index for fast lookup
        my %index;
        for my $i (0 .. $precedence_table->@* - 1) {
            my $entry = $precedence_table->[$i];
            for my $op ($entry->{ops}->@*) {
                $index{$op} = {
                    level => $i,
                    assoc => $entry->{assoc}
                };
            }
        }
        $operator_index = \%index;

        # Identity elements: like Boolean semiring
        $mul_id = Chalk::Semiring::PrecedenceElement->new(valid => 1, forest => $forest, operator_index => $operator_index);
        $add_id = Chalk::Semiring::PrecedenceElement->new(valid => 0, forest => $forest, operator_index => $operator_index);
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # Extract operator from rule if it's a binary operation
        # Pattern 1: E -> E OP E (3 elements in RHS, operator at index 1)
        # Pattern 2: E -> E WS_OPT OP WS_OPT E (5 elements in RHS, operator at index 2)

        my $rhs = $rule->rhs;
        my $operator = undef;
        my $prec_level = undef;
        my $assoc = undef;

        # Check for Pattern 1: 3-element binary operation (E OP E)
        if ($rhs->@* == 3) {
            my $candidate = $rhs->[1];  # Middle element

            # Check if this candidate is in our precedence table
            if (defined($candidate) && !ref($candidate)) {
                my $op_info = $self->lookup_operator($candidate);
                if ($op_info) {
                    $operator = $candidate;
                    $prec_level = $op_info->{level};
                    $assoc = $op_info->{assoc};
                }
            }
        }
        # Check for Pattern 2: 5-element with whitespace (E WS_OPT OP WS_OPT E)
        elsif ($rhs->@* == 5) {
            my $candidate = $rhs->[2];  # Operator at index 2

            # Check if this candidate is in our precedence table
            if (defined($candidate) && !ref($candidate)) {
                my $op_info = $self->lookup_operator($candidate);
                if ($op_info) {
                    $operator = $candidate;
                    $prec_level = $op_info->{level};
                    $assoc = $op_info->{assoc};
                }
            }
        }

        return Chalk::Semiring::PrecedenceElement->new(
            valid => 1,
            operator => $operator,
            precedence_level => $prec_level,
            associativity => $assoc,
            forest => $forest,
            operator_index => $operator_index
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

    # Called when a token is scanned - update element with matched operator value
    # $pattern_name is the name from named regex captures (e.g., 'IDENTIFIER')
    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # If the matched value is an operator in our precedence table,
        # create a new element with the operator information
        if (defined($matched_value) && !ref($matched_value)) {
            my $op_info = $self->lookup_operator($matched_value);
            if ($op_info) {
                return Chalk::Semiring::PrecedenceElement->new(
                    valid => 1,
                    operator => $matched_value,
                    precedence_level => $op_info->{level},
                    associativity => $op_info->{assoc},
                    forest => $forest,
                    operator_index => $operator_index
                );
            }
        }

        # Otherwise return element unchanged
        return $element;
    }

    # Called when a rule completes - extract operator and validate precedence
    method on_complete($completed_item, $completed_element, $composite_element = undef) {
        my $rule = $completed_item->rule;
        my $lhs = $rule->lhs;
        my $start = $completed_item->start_pos;
        my $end = $completed_item->end_pos;

        # For ArithmeticOp rules, validate precedence after extraction
        # Other rules just extract operator if present
        my $operator = undef;
        my $prec_level = undef;
        my $assoc = undef;

        # Extract operator from completed element
        if ($completed_element->can('operator') && defined($completed_element->operator)) {
            $operator = $completed_element->operator;
            $prec_level = $completed_element->precedence_level;
            $assoc = $completed_element->associativity;
        }

        # Look up SPPF node from forest if available
        my $sppf_node = undef;
        if ($forest) {
            $sppf_node = $forest->get_node($lhs, $start, $end);
        }

        # Create element with operator information and SPPF node for validation
        my $result_element;
        if (defined($operator)) {
            $result_element = Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                operator => $operator,
                precedence_level => $prec_level,
                associativity => $assoc,
                forest => $forest,
                sppf_node => $sppf_node,
                start_pos => $start,
                end_pos => $end,
                operator_index => $operator_index
            );
        } else {
            $result_element = Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                forest => $forest,
                sppf_node => $sppf_node,
                start_pos => $start,
                end_pos => $end,
                operator_index => $operator_index
            );
        }

        # CRITICAL: Validate precedence structure before returning
        # This catches invalid parses that weren't filtered by add() (when no alternatives existed)
        if ($sppf_node && $result_element->_validate_element_precedence()) {
            # Valid precedence - return element as-is
            return $result_element;
        } elsif ($sppf_node && !$result_element->_validate_element_precedence()) {
            # Invalid precedence - return add_id to signal parse failure
            return $add_id;
        } else {
            # No SPPF node - can't validate, assume valid
            return $result_element;
        }
    }

    # Post-processing: Prune invalid alternatives from SPPF forest after parsing completes
    # This should be called after parse_string() returns, when all alternatives are built
    method prune_invalid_alternatives_from_forest() {
        return unless $forest;

        # Get all ArithmeticOp nodes from the forest
        my @all_nodes = values %{$forest->nodes};
        my @arith_nodes = grep { $_->symbol eq 'ArithmeticOp' } @all_nodes;

        # For each ArithmeticOp node, prune invalid IntermediateNode alternatives
        for my $node (@arith_nodes) {
            # Create a temporary element to access the validation logic
            my $temp_element = Chalk::Semiring::PrecedenceElement->new(
                valid => 1,
                forest => $forest,
                sppf_node => $node,
                start_pos => $node->start_pos,
                end_pos => $node->end_pos,
                operator_index => $operator_index
            );

            # Prune invalid alternatives from this node's IntermediateNode children
            $temp_element->_prune_invalid_intermediate_node_alternatives($node);
        }
    }

    # Lookup operator precedence and associativity
    method lookup_operator($op) {
        return $operator_index->{$op};
    }
}

1;

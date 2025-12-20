# ABOUTME: Tropical semiring for type inference using type lattice operations
# ABOUTME: Implements ⊕=join, ⊗=meet, 𝟘=bottom, 𝟙=top for lattice-based type checking during parsing
# See docs/type-system.md for complete type hierarchy (Int <: Num <: Str) and semantics
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;
use Chalk::Grammar::Chalk::TypeLattice;

class Chalk::Semiring::TypeInferenceElement :isa(Chalk::Element) {
    field $type_obj :param :reader;       # Type object from Chalk::Grammar::Chalk::Type::*
    field $type_env :param :reader = {};  # Variable → Type bindings (hashref)
    field $children :param :reader = [];  # Child elements (parse tree) (arrayref)
    field $token :param :reader = undef;  # Token for terminals
    field $errors :param :reader = [];    # Accumulated error messages (arrayref)
    field $start_pos :param :reader = 0;  # Start position for error reporting
    field $end_pos :param :reader = 0;    # End position for error reporting

    # Tropical semiring addition: join (∨) - "could be either type"
    method add( $other, $swap = undef ) {
        my $other_type = $other->type_obj;
        my $joined = $type_obj->join($other_type);
        # Merge type environments from both alternatives
        # For the same input string, alternative parses should produce
        # consistent bindings, so merging preserves all discovered bindings
        my $combined_env = { $type_env->%*, $other->type_env->%* };
        # Merge errors from both alternatives
        my @merged_errors = ($errors->@*, $other->errors->@*);
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $joined,
            type_env => $combined_env,
            children => $children,
            token => $token,
            errors => \@merged_errors,
            start_pos => $start_pos,
            end_pos => $end_pos
        );
    }

    # Tropical semiring multiplication: meet (∧) - "must satisfy all constraints"
    # Also builds parse tree for on_complete() to use
    method multiply( $other, $swap = undef ) {
        # Merge type environments (right side wins on conflicts)
        my $combined_env = { $type_env->%*, $other->type_env->%* };

        # Append completed element as child to build parse tree
        my @new_children = ($children->@*, $other);

        # Perform type inference via meet (greatest lower bound)
        my $other_type = $other->type_obj;
        my $meet_type = $type_obj->meet($other_type);

        # Merge errors from both operands
        my @new_errors = ($errors->@*, $other->errors->@*);

        # Track type contradiction if meet produces bottom from non-bottom types
        if ($meet_type->is_bottom() && !$type_obj->is_bottom() && !$other_type->is_bottom()) {
            push @new_errors, {
                type => 'type_contradiction',
                message => "Type contradiction: cannot unify '" . $type_obj->name() .
                           "' with '" . $other_type->name() . "'",
                start_pos => $start_pos,
                end_pos => $other->end_pos,
                left_type => $type_obj->name(),
                right_type => $other_type->name()
            };
        }

        # Calculate combined position span
        my $new_start = $start_pos < $other->start_pos ? $start_pos : $other->start_pos;
        my $new_end = $end_pos > $other->end_pos ? $end_pos : $other->end_pos;

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $meet_type,
            type_env => $combined_env,
            children => \@new_children,
            token => $token,  # Preserve token from left element
            errors => \@new_errors,
            start_pos => $new_start,
            end_pos => $new_end
        );
    }

    method equals( $other, $swap = undef ) {
        return 0 unless ref($other) eq ref($self);
        # Two type elements are equal if their types have the same name
        return $type_obj->name() eq $other->type_obj->name();
    }

    method score() {
        # Score could be based on type specificity
        # More specific types (lower in lattice) score higher
        # For now, use a simple scheme: bottom=0, everything else=1
        return $type_obj->is_bottom() ? 0 : 1;
    }

    method to_string(@args) {
        return $type_obj->name();
    }

    # For backward compatibility with SemanticValidation tests
    method valid() {
        # A type is "valid" if it's not bottom (not a type contradiction)
        return !$type_obj->is_bottom();
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

class Chalk::Semiring::TypeInference :isa(Chalk::Semiring) {
    field $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    # Identity elements for tropical semiring
    # 𝟘 = ⊥ (bottom) - identity for join (addition)
    # 𝟙 = ⊤ (top/Any) - identity for meet (multiplication)
    field $add_id :reader = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->bottom_type(),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 0
    );
    field $mul_id :reader = Chalk::Semiring::TypeInferenceElement->new(
        type_obj => $lattice->top_type(),
        type_env => {},
        children => [],
        token => undef,
        errors => [],
        start_pos => 0,
        end_pos => 0
    );

    # Shared context for SPPF integration (optional)
    field $shared_context :param = undef;

    # Semiring methods
    method zero() {
        return $add_id;  # Bottom type (⊥)
    }

    method one() {
        return $mul_id;  # Top type (⊤ / Any)
    }

    method init_element_from_rule($rule, $start_pos = 0, $end_pos = 0, $matched_value = undef) {
        # Start with top type (no constraints yet)
        # Type constraints will be refined through meet operations
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $lattice->top_type(),
            type_env => {},
            children => [],
            token => undef,
            errors => [],
            start_pos => $start_pos,
            end_pos => $end_pos
        );
    }

    method from_symbol($symbol, $start_pos, $end_pos, $sppf_node = undef) {
        # Infer type from IR operation if available
        # For now, return top type (Any) - constraints added via multiply
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $lattice->top_type(),
            type_env => {},
            children => [],
            token => undef,
            errors => [],
            start_pos => $start_pos,
            end_pos => $end_pos
        );
    }

    method from_terminal($symbol, $start_pos, $end_pos) {
        # Terminals don't directly carry type information
        # Return top type - actual type inferred from context
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $lattice->top_type(),
            type_env => {},
            children => [],
            token => undef,
            errors => [],
            start_pos => $start_pos,
            end_pos => $end_pos
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

    method on_scan($item, $element, $pos, $matched_value, $pattern_name = undef) {
        # Extract type information from scanned Token objects
        # Return a new element with the extracted type and token stored
        # The Earley parser will handle multiply() operations automatically

        my $match_len = defined($matched_value) ? length($matched_value) : 0;
        my $end_pos = $pos + $match_len;

        # Check if matched_value is a Token with type information
        if (defined $matched_value && ref($matched_value)) {
            my $type_obj = $element->type_obj;  # Default to current type

            # Token::Int → Int type
            if ($matched_value->isa('Chalk::Grammar::Token::Int')) {
                $type_obj = $lattice->type_from_name('Int');
            }
            # Token::Float → Num type
            elsif ($matched_value->isa('Chalk::Grammar::Token::Float')) {
                $type_obj = $lattice->type_from_name('Num');
            }
            # String literals (SINGLE_QUOTED_STRING, DOUBLE_QUOTED_STRING) → Str type
            elsif ($matched_value->isa('Chalk::Grammar::Token') &&
                   defined($pattern_name) &&
                   ($pattern_name eq 'SINGLE_QUOTED_STRING' || $pattern_name eq 'DOUBLE_QUOTED_STRING')) {
                $type_obj = $lattice->type_from_name('Str');
            }

            # Always store the token for later extraction (e.g., class names)
            return Chalk::Semiring::TypeInferenceElement->new(
                type_obj => $type_obj,
                type_env => $element->type_env,
                children => $element->children,
                token => $matched_value,  # Store token for extraction by infer_type
                errors => $element->errors,
                start_pos => $pos,
                end_pos => $end_pos
            );
        }

        # Non-token value - return element with updated positions
        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj => $element->type_obj,
            type_env => $element->type_env,
            children => $element->children,
            token => $element->token,
            errors => $element->errors,
            start_pos => $pos,
            end_pos => $end_pos
        );
    }

    # Earley completion hook - delegates type inference to grammar rules
    # Called when a rule is fully recognized (completed in Earley sense)
    # This is the safe execution point for rule-specific type inference
    # $completed_element is optional metadata from Composite semiring
    method on_complete($item, $element, $completed_element = undef) {
        my $rule = $item->rule;

        # DEBUG: Log rule completion
        if ($ENV{DEBUG_TYPE_INFERENCE} && defined $rule) {
            my $rule_class = ref($rule);
            my $rule_lhs = $rule->lhs if $rule->can('lhs');
            warn "TypeInference::on_complete() for rule: $rule_class (", ($rule_lhs // 'unknown'), ")\n";
            warn "  Rule can infer_type: ", ($rule->can('infer_type') ? "YES" : "NO"), "\n";
        }

        # Emit any type errors accumulated in the element to diagnostic context
        if ($element->can('errors') && $element->errors->@*) {
            for my $error ($element->errors->@*) {
                $self->emit_diagnostic($error);
            }
        }

        # If rule has custom type inference, delegate to it
        # This enables extensible type inference without modifying TypeInference.pm
        if (defined $rule && $rule->can('infer_type')) {
            return $rule->infer_type($self, $element);
        }

        # Default: preserve element unchanged (no type inference for this rule)
        # Note: Rule-specific type inference (like ArithmeticOp::infer_type) is
        # currently only called when the rule class directly implements infer_type().
        # Dynamic loading of semantic action classes was removed due to Composite
        # semiring coordination issues (#332).
        return $element;
    }

    # Helper method to create type from name (for testing and convenience)
    method type_from_name($name) {
        return $lattice->type_from_name($name);
    }
}


1;

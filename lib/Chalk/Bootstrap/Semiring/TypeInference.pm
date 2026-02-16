# ABOUTME: TypeInference semiring for type-aware disambiguation in Earley parsing.
# ABOUTME: Handles keyword rejection, unary +/- disambiguation, variable type tags, and builtin signature validation.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Semiring::TypeInference {
    # Callback: word => true if keyword, false otherwise
    field $keyword_check :param;
    # Positions where BinaryOp scanned + or - (for unary disambiguation)
    field %binary_op_positions;

    # Builtin signatures: argument types, minimum arity, and return type.
    # arg_types describes the positional type pattern (e.g., first arg
    # must be array, rest form a list). return_type describes the result.
    my %BUILTIN_SIGNATURES = (
        push    => { min_arity => 2, arg_types => ['array', 'list'], return_type => ['list'] },
        unshift => { min_arity => 2, arg_types => ['array', 'list'], return_type => ['list'] },
        pop     => { min_arity => 1, arg_types => ['array'],         return_type => ['scalar'] },
        shift   => { min_arity => 1, arg_types => ['array'],         return_type => ['scalar'] },
        splice  => { min_arity => 1, arg_types => ['array', 'list'], return_type => ['list'] },
    );

    # Set of builtin names with signatures (for quick lookup at scan time)
    my %BUILTIN_WITH_SIGNATURE = map { $_ => true } keys %BUILTIN_SIGNATURES;

    method zero() {
        return { valid => false };
    }

    method one() {
        return { valid => true };
    }

    method is_zero($value) {
        return !$value->{valid};
    }

    method multiply($left, $right) {
        # Propagate zero
        return $self->zero() if $self->is_zero($left);
        return $self->zero() if $self->is_zero($right);

        # Propagate tags from either child
        my $tagged  = $left->{keyword_as_identifier} || $right->{keyword_as_identifier};
        my $unary   = $left->{ambiguous_unary}       || $right->{ambiguous_unary};
        my $is_arr  = $left->{is_array_typed}        || $right->{is_array_typed};
        my $is_hash = $left->{is_hash_typed}         || $right->{is_hash_typed};
        my $is_scl  = $left->{is_scalar_typed}       || $right->{is_scalar_typed};
        my $builtin = $left->{call_symbol}     || $right->{call_symbol};
        my $arity   = $left->{list_arity}            || $right->{list_arity};

        return {
            valid => true,
            ($tagged  ? (keyword_as_identifier => true)     : ()),
            ($unary   ? (ambiguous_unary       => true)     : ()),
            ($is_arr  ? (is_array_typed        => true)     : ()),
            ($is_hash ? (is_hash_typed         => true)     : ()),
            ($is_scl  ? (is_scalar_typed       => true)     : ()),
            ($builtin ? (call_symbol     => $builtin) : ()),
            ($arity   ? (list_arity            => $arity)   : ()),
        };
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if $self->is_zero($left);
        return $left if $self->is_zero($right);

        # Prefer non-ambiguous-unary (binary) over ambiguous-unary
        my $left_unary  = $left->{ambiguous_unary};
        my $right_unary = $right->{ambiguous_unary};
        if ($left_unary && !$right_unary) {
            return $right;
        }
        if ($right_unary && !$left_unary) {
            return $left;
        }

        return $left;
    }

    # Signal to Composite which alternative to select for ALL components.
    # Returns 'left', 'right', or undef (no preference).
    method selects_alternative($left, $right) {
        return undef if $self->is_zero($left);
        return undef if $self->is_zero($right);

        my $left_unary  = $left->{ambiguous_unary};
        my $right_unary = $right->{ambiguous_unary};

        # Prefer non-ambiguous-unary (binary) over ambiguous-unary
        if ($left_unary && !$right_unary) {
            return 'right';
        }
        if ($right_unary && !$left_unary) {
            return 'left';
        }

        return undef;
    }

    method on_scan($item, $alt_idx, $pos, $matched_text) {
        my $existing = $item->{value};

        # Propagate zero
        return $self->zero() if $self->is_zero($existing);

        my $rule_name = $item->{rule}->name();

        # Reject empty regex // and m// — these are the defined-or operator, not a regex
        if ($rule_name eq 'RegexLiteral'
            && $matched_text =~ m{^(?:m)?//[msixpodualngcer]*$})
        {
            return $self->zero();
        }

        # In QualifiedIdentifier context, tag bare builtins with their name
        # so CallExpression can look up the full signature for validation.
        if ($rule_name eq 'QualifiedIdentifier'
            && $matched_text !~ /::/
            && exists $BUILTIN_WITH_SIGNATURE{$matched_text})
        {
            return $self->multiply($existing, {
                valid       => true,
                call_symbol => $matched_text,
            });
        }

        # In QualifiedIdentifier context, reject bare keywords (no :: separator)
        if ($rule_name eq 'QualifiedIdentifier'
            && $matched_text !~ /::/
            && $keyword_check->($matched_text))
        {
            return $self->multiply($existing, {
                valid                => true,
                keyword_as_identifier => true,
            });
        }

        # Tag variable scans with their type
        if ($rule_name eq 'ScalarVariable') {
            return $self->multiply($existing, {
                valid          => true,
                is_scalar_typed => true,
            });
        }
        if ($rule_name eq 'ArrayVariable') {
            return $self->multiply($existing, {
                valid         => true,
                is_array_typed => true,
            });
        }
        if ($rule_name eq 'HashVariable') {
            return $self->multiply($existing, {
                valid        => true,
                is_hash_typed => true,
            });
        }

        # Track BinaryOp scans of +/- for cross-item disambiguation.
        # BinaryOp items scan before UnaryExpression predictions at the
        # same position because BinaryOp advances an existing item while
        # UnaryExpression is freshly predicted from the right-hand Expression.
        if ($rule_name eq 'BinaryOp' && $matched_text =~ /^[+-]$/) {
            $binary_op_positions{$pos} = true;
        }

        # Tag UnaryExpression +/- only when BinaryOp also scanned at
        # the same position — the binary interpretation should win.
        # Standalone unary (e.g., `my $b = -$a`) has no BinaryOp at
        # that position and is left untagged.
        if ($rule_name eq 'UnaryExpression'
            && $matched_text =~ /^[+-]$/
            && $binary_op_positions{$pos})
        {
            return $self->multiply($existing, {
                valid           => true,
                ambiguous_unary => true,
            });
        }

        # Non-QualifiedIdentifier or non-keyword: transparent
        return $self->multiply($existing, $self->one());
    }

    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return $self->zero() if $self->is_zero($value);

        my $rule_name = $item->{rule}->name();

        # Reject keyword-as-identifier at expression-level rules where a
        # keyword should not be treated as a bare identifier.
        # Atom (last alt = bare QualifiedIdentifier) and CallExpression
        # (QualifiedIdentifier as function name) are the contexts where
        # keyword misuse occurs. Other rules that contain QualifiedIdentifier
        # (Attribute, MethodCall, SubroutineDefinition, MethodDefinition)
        # legitimately use keywords as identifiers (e.g., :isa(...), ->isa(...), sub eq {}).
        if ($rule_name eq 'Atom' && $value->{keyword_as_identifier}) {
            return $self->zero();
        }

        # ExpressionList: track list arity (number of items in the list)
        # alt 0 = single Expression (arity 1)
        # alt 1 = ExpressionList , Expression (arity = child + 1)
        # alt 2 = ExpressionList => Expression (arity = child + 1)
        # alt 3 = trailing comma (arity preserved)
        if ($rule_name eq 'ExpressionList') {
            my $arity;
            if ($alt_idx == 0) {
                $arity = 1;
            } elsif ($alt_idx == 1 || $alt_idx == 2) {
                $arity = ($value->{list_arity} // 1) + 1;
            } else {
                $arity = $value->{list_arity};
            }
            return {
                valid => true,
                ($value->{is_array_typed}  ? (is_array_typed  => true) : ()),
                ($value->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                ($value->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
                ($value->{call_symbol} ? (call_symbol => $value->{call_symbol}) : ()),
                ($arity ? (list_arity => $arity) : ()),
            };
        }

        # CallExpression: validate builtin signatures, then check keyword rejection
        if ($rule_name eq 'CallExpression') {
            if ($value->{keyword_as_identifier}) {
                return $self->zero();
            }
            # Builtin signature validation: check arg types and min arity
            if ($value->{call_symbol}) {
                my $builtin_name = $value->{call_symbol};
                my $sig = $BUILTIN_SIGNATURES{$builtin_name};
                if ($sig) {
                    # Validate first arg type from signature
                    my $first_type = $sig->{arg_types}[0];
                    if ($first_type eq 'array' && !$value->{is_array_typed}) {
                        return $self->zero();
                    }
                    # Validate min arity
                    my $arity = $value->{list_arity} // 1;
                    if ($arity < $sig->{min_arity}) {
                        return $self->zero();
                    }
                }
                # Validation passed: clear builtin tag, preserve type tags
                return {
                    valid => true,
                    ($value->{is_array_typed}  ? (is_array_typed  => true) : ()),
                    ($value->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                    ($value->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
                };
            }
            # Non-builtin CallExpression: preserve type tags
            return {
                valid => true,
                ($value->{is_array_typed}  ? (is_array_typed  => true) : ()),
                ($value->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                ($value->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
            };
        }

        # UnaryExpression completion with ambiguous_unary tag → reject.
        # The binary interpretation (BinaryExpression) at the same position
        # is the correct parse; zero-propagation prevents this unary path
        # from poisoning parent items.
        if ($rule_name eq 'UnaryExpression' && $value->{ambiguous_unary}) {
            return $self->zero();
        }

        # PostfixDeref: tag with the type of the dereference result.
        # alt 0 = ->@* (array), alt 1 = ->%* (hash),
        # alt 2 = ->$* (scalar), alt 3 = ->$#* (scalar count)
        if ($rule_name eq 'PostfixDeref') {
            if ($alt_idx == 0) {
                return { valid => true, is_array_typed => true };
            } elsif ($alt_idx == 1) {
                return { valid => true, is_hash_typed => true };
            } else {
                return { valid => true, is_scalar_typed => true };
            }
        }

        # Boundary rules: clear keyword_as_identifier, ambiguous_unary, and
        # call_symbol tags. Type tags (is_array_typed, etc.) are
        # PRESERVED through boundaries because a parenthesized array is
        # still array-typed (e.g., ($ops->@*) is still array).
        # Attribute and MethodCall allow keywords as identifiers (e.g., :isa).
        # Subscript clears tags because hash subscript keys can be keywords
        # (e.g., $h{x} where `x` is the repeat operator keyword).
        if ($rule_name eq 'ParenExpr'
            || $rule_name eq 'ArrayConstructor'
            || $rule_name eq 'HashConstructor'
            || $rule_name eq 'Block'
            || $rule_name eq 'Signature'
            || $rule_name eq 'Attribute'
            || $rule_name eq 'Subscript')
        {
            return {
                valid => true,
                ($value->{is_array_typed}  ? (is_array_typed  => true) : ()),
                ($value->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                ($value->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
            };
        }

        # Preserve all tags through intermediate rules
        my $tagged  = $value->{keyword_as_identifier};
        my $unary   = $value->{ambiguous_unary};
        my $is_arr  = $value->{is_array_typed};
        my $is_hash = $value->{is_hash_typed};
        my $is_scl  = $value->{is_scalar_typed};
        my $builtin = $value->{call_symbol};
        return {
            valid => true,
            ($tagged  ? (keyword_as_identifier => true)     : ()),
            ($unary   ? (ambiguous_unary       => true)     : ()),
            ($is_arr  ? (is_array_typed        => true)     : ()),
            ($is_hash ? (is_hash_typed         => true)     : ()),
            ($is_scl  ? (is_scalar_typed       => true)     : ()),
            ($builtin ? (call_symbol     => $builtin) : ()),
        };
    }
}

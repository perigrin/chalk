# ABOUTME: TypeInference semiring for type-aware disambiguation in Earley parsing.
# ABOUTME: Handles keyword rejection, unary +/- disambiguation, variable type tags, and builtin signature validation.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;

class Chalk::Bootstrap::Semiring::TypeInference {
    # Callback: word => true if keyword, false otherwise
    field $keyword_check :param;
    # Callback: name => signature hash or undef (from TypeLibrary)
    field $builtin_lookup :param;
    # Callback: (value, required_type) => true if value's tags satisfy required type
    field $type_check :param;
    # Positions where BinaryOp scanned + or - (for unary disambiguation)
    field %binary_op_positions;

    # Extract tag hash from a TypeInference value (Context with tag hash focus).
    # For intermediate multiply nodes (undef focus), collects tags from leaves.
    my sub _tags($val) {
        return undef unless defined $val;
        my $focus = $val->extract();
        return $focus if defined $focus;
        # Intermediate multiply node with undef focus: collect from leaves
        my %merged;
        for my $leaf ($val->leaves()) {
            my $f = $leaf->extract();
            next unless defined $f;
            for my $k (keys %$f) {
                $merged{$k} = $f->{$k} if $f->{$k};
            }
        }
        return \%merged;
    }

    # Create a leaf Context with the given tag hash as focus.
    my sub _ctx($tags) {
        return Chalk::Bootstrap::Context->new(
            focus    => $tags,
            children => [],
            position => 0,
            rule     => undef,
        );
    }

    method zero() {
        return undef;
    }

    method one() {
        return _ctx({ valid => true });
    }

    method is_zero($value) {
        return !defined $value;
    }

    method multiply($left, $right) {
        # Propagate zero
        return undef if !defined $left;
        return undef if !defined $right;

        # Build Context tree preserving children
        return Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [$left, $right],
            position => $right->position(),
            rule     => undef,
        );
    }

    method add($left, $right) {
        # Return first non-zero alternative
        return $right if !defined $left;
        return $left if !defined $right;

        # Prefer non-ambiguous-unary (binary) over ambiguous-unary
        my $left_tags  = _tags($left);
        my $right_tags = _tags($right);
        my $left_unary  = $left_tags->{ambiguous_unary};
        my $right_unary = $right_tags->{ambiguous_unary};
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
        return undef if !defined $left;
        return undef if !defined $right;

        my $left_tags  = _tags($left);
        my $right_tags = _tags($right);
        my $left_unary  = $left_tags->{ambiguous_unary};
        my $right_unary = $right_tags->{ambiguous_unary};

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
        return undef if !defined $existing;

        my $rule_name = $item->{rule}->name();

        # Reject empty regex // and m// — these are the defined-or operator, not a regex
        if ($rule_name eq 'RegexLiteral'
            && $matched_text =~ m{^(?:m)?//[msixpodualngcer]*$})
        {
            return undef;
        }

        # Non-empty RegexLiteral → type => 'Regex'
        if ($rule_name eq 'RegexLiteral') {
            return $self->multiply($existing,
                _ctx({ valid => true, type => 'Regex' }));
        }

        # In QualifiedIdentifier context, tag bare builtins with their name
        # so CallExpression can look up the full signature for validation.
        if ($rule_name eq 'QualifiedIdentifier'
            && $matched_text !~ /::/
            && $builtin_lookup->($matched_text))
        {
            return $self->multiply($existing,
                _ctx({ valid => true, call_symbol => $matched_text }));
        }

        # In QualifiedIdentifier context, reject bare keywords (no :: separator)
        if ($rule_name eq 'QualifiedIdentifier'
            && $matched_text !~ /::/
            && $keyword_check->($matched_text))
        {
            return $self->multiply($existing,
                _ctx({ valid => true, keyword_as_identifier => true }));
        }

        # Tag variable scans with their type (both legacy is_*_typed and new type tag)
        if ($rule_name eq 'ScalarVariable') {
            return $self->multiply($existing,
                _ctx({ valid => true, is_scalar_typed => true, type => 'Scalar' }));
        }
        if ($rule_name eq 'ArrayVariable') {
            return $self->multiply($existing,
                _ctx({ valid => true, is_array_typed => true, type => 'Array' }));
        }
        if ($rule_name eq 'HashVariable') {
            return $self->multiply($existing,
                _ctx({ valid => true, is_hash_typed => true, type => 'Hash' }));
        }

        # NumericLiteral: distinguish Int vs Num based on pattern
        if ($rule_name eq 'NumericLiteral') {
            # Hex (0x), binary (0b), octal (0[0-7]), or plain integer → Int
            # Float (has .) or scientific (has e/E but not hex 0x) → Num
            my $num_type;
            if ($matched_text =~ /[.]/
                || ($matched_text =~ /[eE]/ && $matched_text !~ /^0[xX]/))
            {
                $num_type = 'Num';
            } else {
                $num_type = 'Int';
            }
            return $self->multiply($existing,
                _ctx({ valid => true, type => $num_type }));
        }

        # StringLiteral → type => 'Str'
        if ($rule_name eq 'StringLiteral') {
            return $self->multiply($existing,
                _ctx({ valid => true, type => 'Str' }));
        }

        # Literal: undef/true/false
        if ($rule_name eq 'Literal') {
            my $lit_type;
            if ($matched_text eq 'undef') {
                $lit_type = 'Undef';
            } elsif ($matched_text eq 'true' || $matched_text eq 'false') {
                $lit_type = 'Bool';
            }
            if (defined $lit_type) {
                return $self->multiply($existing,
                    _ctx({ valid => true, type => $lit_type }));
            }
        }

        # Atom: __SUB__ → type => 'CodeRef'
        if ($rule_name eq 'Atom' && $matched_text eq '__SUB__') {
            return $self->multiply($existing,
                _ctx({ valid => true, type => 'CodeRef' }));
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
            return $self->multiply($existing,
                _ctx({ valid => true, ambiguous_unary => true }));
        }

        # Non-QualifiedIdentifier or non-keyword: transparent
        return $self->multiply($existing, $self->one());
    }

    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return undef if !defined $value;

        my $tags = _tags($value);
        my $rule_name = $item->{rule}->name();

        # Reject keyword-as-identifier at expression-level rules where a
        # keyword should not be treated as a bare identifier.
        # Atom (last alt = bare QualifiedIdentifier) and CallExpression
        # (QualifiedIdentifier as function name) are the contexts where
        # keyword misuse occurs. Other rules that contain QualifiedIdentifier
        # (Attribute, MethodCall, SubroutineDefinition, MethodDefinition)
        # legitimately use keywords as identifiers (e.g., :isa(...), ->isa(...), sub eq {}).
        if ($rule_name eq 'Atom' && $tags->{keyword_as_identifier}) {
            return undef;
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
                $arity = ($tags->{list_arity} // 1) + 1;
            } else {
                $arity = $tags->{list_arity};
            }
            return Chalk::Bootstrap::Context->new(
                focus    => {
                    valid => true,
                    ($tags->{is_array_typed}  ? (is_array_typed  => true) : ()),
                    ($tags->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                    ($tags->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
                    ($tags->{call_symbol} ? (call_symbol => $tags->{call_symbol}) : ()),
                    ($arity ? (list_arity => $arity) : ()),
                },
                children => $value->children(),
                position => $value->position(),
                rule     => $rule_name,
            );
        }

        # CallExpression: validate builtin signatures, then check keyword rejection
        if ($rule_name eq 'CallExpression') {
            if ($tags->{keyword_as_identifier}) {
                return undef;
            }
            # Builtin signature validation: check arg types and min arity
            if ($tags->{call_symbol}) {
                my $builtin_name = $tags->{call_symbol};
                my $sig = $builtin_lookup->($builtin_name);
                if ($sig) {
                    # Validate first arg type from signature
                    my $first_type = $sig->{arg_types}[0];
                    if (!$type_check->($tags, $first_type)) {
                        return undef;
                    }
                    # Validate min arity
                    my $arity = $tags->{list_arity} // 1;
                    if ($arity < $sig->{min_arity}) {
                        return undef;
                    }
                }
                # Validation passed: clear builtin tag, preserve type tags
                return Chalk::Bootstrap::Context->new(
                    focus    => {
                        valid => true,
                        ($tags->{is_array_typed}  ? (is_array_typed  => true) : ()),
                        ($tags->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                        ($tags->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
                    },
                    children => $value->children(),
                    position => $value->position(),
                    rule     => $rule_name,
                );
            }
            # Non-builtin CallExpression: preserve type tags
            return Chalk::Bootstrap::Context->new(
                focus    => {
                    valid => true,
                    ($tags->{is_array_typed}  ? (is_array_typed  => true) : ()),
                    ($tags->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                    ($tags->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
                },
                children => $value->children(),
                position => $value->position(),
                rule     => $rule_name,
            );
        }

        # UnaryExpression completion with ambiguous_unary tag → reject.
        # The binary interpretation (BinaryExpression) at the same position
        # is the correct parse; zero-propagation prevents this unary path
        # from poisoning parent items.
        if ($rule_name eq 'UnaryExpression' && $tags->{ambiguous_unary}) {
            return undef;
        }

        # PostfixDeref: tag with the type of the dereference result.
        # alt 0 = ->@* (array), alt 1 = ->%* (hash),
        # alt 2 = ->$* (scalar), alt 3 = ->$#* (scalar count)
        if ($rule_name eq 'PostfixDeref') {
            my $type_tag;
            if ($alt_idx == 0) {
                $type_tag = { valid => true, is_array_typed => true };
            } elsif ($alt_idx == 1) {
                $type_tag = { valid => true, is_hash_typed => true };
            } else {
                $type_tag = { valid => true, is_scalar_typed => true };
            }
            return Chalk::Bootstrap::Context->new(
                focus    => $type_tag,
                children => $value->children(),
                position => $value->position(),
                rule     => $rule_name,
            );
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
            return Chalk::Bootstrap::Context->new(
                focus    => {
                    valid => true,
                    ($tags->{is_array_typed}  ? (is_array_typed  => true) : ()),
                    ($tags->{is_hash_typed}   ? (is_hash_typed   => true) : ()),
                    ($tags->{is_scalar_typed} ? (is_scalar_typed => true) : ()),
                },
                children => $value->children(),
                position => $value->position(),
                rule     => $rule_name,
            );
        }

        # Preserve all tags through intermediate rules
        return Chalk::Bootstrap::Context->new(
            focus    => {
                valid => true,
                ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true)     : ()),
                ($tags->{ambiguous_unary}       ? (ambiguous_unary       => true)     : ()),
                ($tags->{is_array_typed}        ? (is_array_typed        => true)     : ()),
                ($tags->{is_hash_typed}         ? (is_hash_typed         => true)     : ()),
                ($tags->{is_scalar_typed}       ? (is_scalar_typed       => true)     : ()),
                ($tags->{call_symbol}           ? (call_symbol => $tags->{call_symbol}) : ()),
            },
            children => $value->children(),
            position => $value->position(),
            rule     => $rule_name,
        );
    }
}

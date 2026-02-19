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
    # Positions where BinaryOp scanned + or - (for unary disambiguation)
    field %binary_op_positions;

    # Hash-cons cache: maps stringified key to Context object.
    # Ensures identical parse derivations share the same refaddr.
    my %_ctx_cache;

    # Singleton for one(): a Context with { valid => true } focus and no children.
    my $_one_singleton;

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

    # Serialize a tag hash to a stable string key for hash-consing.
    # Handles arrayref values (e.g. item_types) by joining with semicolons.
    my sub _tag_key($tags) {
        return join(",", map {
            my $v = $tags->{$_};
            "$_=" . (ref($v) eq 'ARRAY' ? join(';', map { $_ // '' } @$v) : ($v // ''))
        } sort keys %$tags);
    }

    # Create a leaf Context with the given tag hash as focus.
    # Hash-consed: same tag content → same object.
    my sub _ctx($tags) {
        my $key = "scan:" . _tag_key($tags);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $tags,
            children => [],
            position => 0,
            rule     => undef,
        ));
    }

    # Create an on_complete result Context, hash-consed by focus content and
    # children refaddrs. All on_complete branches must use this helper to
    # ensure identical completions produce the same object (same refaddr).
    my sub _complete_ctx($focus, $children, $position, $rule) {
        my $focus_key = _tag_key($focus);
        my $children_key = join(":", map { refaddr($_) } @$children);
        my $key = "complete:$rule:$focus_key:$children_key";
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $focus,
            children => $children,
            position => $position,
            rule     => $rule,
        ));
    }

    # Walk right spine of multiply tree to find the rightmost type tag.
    # In a multiply tree (left * right), the rightmost child typically
    # holds the most recent expression's type.
    # Uses coderef for recursive calls within class scope.
    my $_get_rightmost_type;
    $_get_rightmost_type = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{type}) {
            return $focus->{type};
        }
        # Walk children right-to-left
        my @children = $ctx->children()->@*;
        for my $child (reverse @children) {
            my $t = $_get_rightmost_type->($child);
            return $t if defined $t;
        }
        return undef;
    };

    # Search the multiply tree for a child with item_types in focus.
    # Returns the item_types arrayref or undef.
    my $_get_prev_item_types;
    $_get_prev_item_types = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus && exists $focus->{item_types}) {
            return $focus->{item_types};
        }
        for my $child ($ctx->children()->@*) {
            my $found = $_get_prev_item_types->($child);
            return $found if defined $found;
        }
        return undef;
    };

    # Search the multiply tree leaves for one with call_symbol in its focus.
    # Returns the call_symbol string or undef. Used by CallExpression
    # on_complete to extract the function name directly from the tree
    # instead of relying on propagated tags.
    # Follows leaf-finding semantics: stops at focused nodes (on_complete
    # results) and only recurses through unfocused multiply nodes.
    my $_get_call_symbol;
    $_get_call_symbol = sub($ctx) {
        return undef unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            # Focused node (leaf): check for call_symbol and stop
            return $focus->{call_symbol};
        }
        # Unfocused multiply node: recurse into children
        for my $child ($ctx->children()->@*) {
            my $found = $_get_call_symbol->($child);
            return $found if defined $found;
        }
        return undef;
    };

    method zero() {
        return undef;
    }

    method one() {
        return ($_one_singleton //= _ctx({ valid => true }));
    }

    method is_zero($value) {
        return !defined $value;
    }

    method multiply($left, $right) {
        # Propagate zero
        return undef if !defined $left;
        return undef if !defined $right;

        # Hash-cons by children refaddrs: same inputs → same output object
        my $key = "mul:" . refaddr($left) . ":" . refaddr($right);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [$left, $right],
            position => $right->position(),
            rule     => undef,
        ));
    }

    method add($left, $right) {
        # Return arrayref of survivors (FilterComposite convention).
        # [$winner] means this semiring prefers one alternative.
        # [$merged] where merged != left and merged != right means no preference
        # (Composite detects "result equals neither input" and continues to
        # the next semiring for tie-breaking).
        return [$right] if !defined $left;
        return [$left]  if !defined $right;

        # Identity collapse: same refaddr → single survivor (no preference needed)
        return [$left] if refaddr($left) == refaddr($right);

        # Prefer non-ambiguous-unary (binary) over ambiguous-unary
        my $left_tags  = _tags($left);
        my $right_tags = _tags($right);
        my $left_unary  = $left_tags->{ambiguous_unary};
        my $right_unary = $right_tags->{ambiguous_unary};
        if ($left_unary && !$right_unary) {
            return [$right];
        }
        if ($right_unary && !$left_unary) {
            return [$left];
        }

        # No preference: return a merged Context (not equal to either input).
        # Composite sees "result equals neither" and defers to the next semiring.
        return [$self->multiply($left, $right)];
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

        # Tag variable scans with their type
        if ($rule_name eq 'ScalarVariable') {
            return $self->multiply($existing,
                _ctx({ valid => true, type => 'Scalar' }));
        }
        if ($rule_name eq 'ArrayVariable') {
            return $self->multiply($existing,
                _ctx({ valid => true, type => 'Array' }));
        }
        if ($rule_name eq 'HashVariable') {
            return $self->multiply($existing,
                _ctx({ valid => true, type => 'Hash' }));
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

        # BinaryOp: capture operator text for later consumption at
        # BinaryExpression on_complete, and track +/- positions for
        # cross-item disambiguation.
        if ($rule_name eq 'BinaryOp') {
            if ($matched_text =~ /^[+-]$/) {
                $binary_op_positions{$pos} = true;
            }
            return $self->multiply($existing,
                _ctx({ valid => true, op_text => $matched_text }));
        }

        # UnaryExpression operator scan: capture op_text and handle
        # ambiguous +/- disambiguation.
        if ($rule_name eq 'UnaryExpression'
            && $matched_text =~ /^(?:[!~\\]|not|[+-])$/)
        {
            my %tags = (valid => true, op_text => $matched_text);
            # Tag ambiguous +/- only when BinaryOp also scanned at
            # the same position — the binary interpretation should win.
            if ($matched_text =~ /^[+-]$/ && $binary_op_positions{$pos}) {
                $tags{ambiguous_unary} = true;
            }
            return $self->multiply($existing, _ctx(\%tags));
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

        # ExpressionList: track list arity and per-item types
        # alt 0 = single Expression (arity 1)
        # alt 1 = ExpressionList , Expression (arity = child + 1)
        # alt 2 = ExpressionList => Expression (arity = child + 1)
        # alt 3 = trailing comma (arity preserved)
        if ($rule_name eq 'ExpressionList') {
            my ($arity, $item_types);
            if ($alt_idx == 0) {
                $arity = 1;
                # Single expression: its type is the only item
                my $type = $tags->{type};
                $item_types = [$type];
            } elsif ($alt_idx == 1 || $alt_idx == 2) {
                $arity = ($tags->{list_arity} // 1) + 1;
                # Comma/fat-arrow: previous item_types + new item's type
                my $prev = $_get_prev_item_types->($value) // [];
                my $new_type = $_get_rightmost_type->($value);
                $item_types = [$prev->@*, $new_type];
            } else {
                $arity = $tags->{list_arity};
                # Trailing comma: preserve item_types
                $item_types = $tags->{item_types} // $_get_prev_item_types->($value);
            }
            return _complete_ctx(
                {
                    valid => true,
                    ($arity ? (list_arity => $arity) : ()),
                    ($item_types ? (item_types => $item_types) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # CallExpression: validate builtin signatures, then check keyword rejection
        if ($rule_name eq 'CallExpression') {
            if ($tags->{keyword_as_identifier}) {
                return undef;
            }
            my $return_type;
            # Builtin signature validation via per-position item_types.
            # Extract call_symbol from the tree (QualifiedIdentifier leaf)
            # instead of relying on propagated tags.
            my $call_sym = $_get_call_symbol->($value);
            if ($call_sym) {
                my $builtin_name = $call_sym;
                my $item_types = $tags->{item_types};
                my $sig = $builtin_lookup->($builtin_name);
                if ($sig) {
                    if ($item_types) {
                        # Per-position validation using item_types.
                        # For block-first alts (2/3), the Block is arg[0] (Code type)
                        # and ExpressionList's item_types covers remaining args starting
                        # at signature position 1.
                        my $arg_types = $sig->{arg_types};
                        my $sig_offset = ($alt_idx == 2 || $alt_idx == 3) ? 1 : 0;
                        for my $i (0 .. $#$item_types) {
                            my $actual = $item_types->[$i];
                            my $sig_idx = $i + $sig_offset;
                            # Variadic: last arg_type applies to remaining positions
                            my $expected = $arg_types->[$sig_idx] // $arg_types->[-1];
                            if (!Chalk::Grammar::Perl::TypeLibrary::type_satisfies($actual, $expected)) {
                                return undef;
                            }
                        }
                    }
                    # Validate min arity.
                    # For block-first alts (2/3), the Block is an implicit first arg
                    # not counted in ExpressionList's list_arity.
                    my $arity = $tags->{list_arity} // 1;
                    $arity += 1 if ($alt_idx == 2 || $alt_idx == 3);
                    if ($arity < $sig->{min_arity}) {
                        return undef;
                    }
                    # Set return type from signature
                    $return_type = $sig->{return_type};
                    $return_type = undef if defined $return_type && $return_type eq 'Any';
                }
            }
            # Clear builtin tag, set return type
            return _complete_ctx(
                {
                    valid => true,
                    ($return_type ? (type => $return_type) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # UnaryExpression completion with ambiguous_unary tag → reject.
        # The binary interpretation (BinaryExpression) at the same position
        # is the correct parse; zero-propagation prevents this unary path
        # from poisoning parent items.
        if ($rule_name eq 'UnaryExpression' && $tags->{ambiguous_unary}) {
            return undef;
        }

        # BinaryExpression: consume op_text, set result type from TypeLibrary
        if ($rule_name eq 'BinaryExpression') {
            my $op = $tags->{op_text};
            my $result_type;
            if (defined $op) {
                my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op($op);
                if ($sig && $sig->{result} ne 'Any') {
                    $result_type = $sig->{result};
                }
                # result 'Any' → leave type undef (unknown)
            } else {
                # No op_text: preserve child type (intermediate completion)
                $result_type = $tags->{type};
            }
            return _complete_ctx(
                {
                    valid => true,
                    ($result_type ? (type => $result_type) : ()),
                    ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # UnaryExpression: consume op_text, set result type from TypeLibrary
        if ($rule_name eq 'UnaryExpression') {
            my $op = $tags->{op_text};
            my $result_type;
            if (defined $op) {
                my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op($op);
                $result_type = $sig->{result} if $sig;
            }
            return _complete_ctx(
                {
                    valid => true,
                    ($result_type ? (type => $result_type) : ()),
                    ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # PostfixIncDec (++/--): result is Num
        if ($rule_name eq 'PostfixIncDec') {
            return _complete_ctx(
                {
                    valid => true, type => 'Num',
                    ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # Subscript: array/hash subscript → Scalar, deref-call → undef
        # Also acts as boundary rule (clears keyword/unary/call tags)
        if ($rule_name eq 'Subscript') {
            my $sub_type;
            if ($alt_idx <= 1) {
                # alt 0 = [...] (array), alt 1 = {...} (hash) → element is Scalar
                $sub_type = 'Scalar';
            }
            # alt 2+ = ->() deref-call: type unknown (undef)
            return _complete_ctx(
                {
                    valid => true,
                    ($sub_type ? (type => $sub_type) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # TernaryExpression: type unknown (could be either branch)
        if ($rule_name eq 'TernaryExpression') {
            return _complete_ctx(
                {
                    valid => true,
                    ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # AssignmentExpression: type unknown
        if ($rule_name eq 'AssignmentExpression') {
            return _complete_ctx(
                {
                    valid => true,
                    ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # MethodCall: type unknown (return type of method not knowable at parse time)
        if ($rule_name eq 'MethodCall') {
            return _complete_ctx(
                {
                    valid => true,
                    ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # PostfixDeref: tag with the type of the dereference result.
        # alt 0 = ->@* (array), alt 1 = ->%* (hash),
        # alt 2 = ->$* (scalar), alt 3 = ->$#* (scalar count)
        if ($rule_name eq 'PostfixDeref') {
            my $type_tag;
            if ($alt_idx == 0) {
                $type_tag = { valid => true, type => 'Array' };
            } elsif ($alt_idx == 1) {
                $type_tag = { valid => true, type => 'Hash' };
            } else {
                $type_tag = { valid => true, type => 'Scalar' };
            }
            return _complete_ctx(
                $type_tag,
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # AnonymousSub → type => 'Code'
        if ($rule_name eq 'AnonymousSub') {
            return _complete_ctx(
                { valid => true, type => 'Code' },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # QwLiteral → type => 'List'
        if ($rule_name eq 'QwLiteral') {
            return _complete_ctx(
                { valid => true, type => 'List' },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # ArrayConstructor: type => 'ArrayRef', also acts as boundary rule
        if ($rule_name eq 'ArrayConstructor') {
            return _complete_ctx(
                { valid => true, type => 'ArrayRef' },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # HashConstructor: type => 'HashRef', also acts as boundary rule
        if ($rule_name eq 'HashConstructor') {
            return _complete_ctx(
                { valid => true, type => 'HashRef' },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # Boundary rules: clear keyword_as_identifier, ambiguous_unary,
        # call_symbol, and op_text tags. The type tag is PRESERVED through
        # boundaries because a parenthesized array is still array-typed
        # (e.g., ($ops->@*) is still array).
        # Attribute allows keywords as identifiers (e.g., :isa).
        # Subscript is handled separately above (sets type for subscript access).
        if ($rule_name eq 'ParenExpr'
            || $rule_name eq 'Block'
            || $rule_name eq 'Signature'
            || $rule_name eq 'Attribute')
        {
            return _complete_ctx(
                {
                    valid => true,
                    ($tags->{type} ? (type => $tags->{type}) : ()),
                },
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # Preserve all tags through intermediate rules
        return _complete_ctx(
            {
                valid => true,
                ($tags->{keyword_as_identifier} ? (keyword_as_identifier => true)       : ()),
                ($tags->{ambiguous_unary}       ? (ambiguous_unary       => true)       : ()),
                ($tags->{type}                  ? (type       => $tags->{type})         : ()),
                ($tags->{op_text}               ? (op_text    => $tags->{op_text})      : ()),
                ($tags->{call_symbol}           ? (call_symbol => $tags->{call_symbol}) : ()),
                ($tags->{item_types}            ? (item_types  => $tags->{item_types})  : ()),
                ($tags->{list_arity}            ? (list_arity  => $tags->{list_arity})  : ()),
            },
            $value->children(),
            $value->position(),
            $rule_name,
        );
    }
}

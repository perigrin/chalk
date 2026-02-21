# ABOUTME: TypeInference semiring for type-aware disambiguation in Earley parsing.
# ABOUTME: Handles keyword rejection, unary +/- disambiguation, variable type tags, and builtin signature validation.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Context;
use Chalk::Grammar::Perl::KeywordTable;
use Chalk::Bootstrap::Semiring::TypeInferenceActions;

class Chalk::Bootstrap::Semiring::TypeInference {
    # Callback: word => true if keyword, false otherwise
    field $keyword_check :param;
    # Callback: name => signature hash or undef (from TypeLibrary)
    field $builtin_lookup :param;

    # Actions dispatch: methods named after grammar rules for type computation
    my $actions = Chalk::Bootstrap::Semiring::TypeInferenceActions->new();

    # Hash-cons cache: maps stringified key to Context object.
    # Ensures identical parse derivations share the same refaddr.
    my %_ctx_cache;

    # Rules migrated from _complete_ctx to _extend_ctx dispatch.
    # Methods for these rules receive ($ctx) only via extend().
    # Other Actions methods still receive ($value, $tags, $alt_idx) via legacy path.
    my %_migrated_to_extend = map { $_ => true } qw(
        PostfixIncDec AnonymousSub QwLiteral ArrayConstructor HashConstructor
        Atom Expression PostfixExpression
        BinaryExpression UnaryExpression
        ParenExpr Block Signature Attribute
        PostfixDeref Subscript TernaryExpression AssignmentExpression MethodCall
        ExpressionList
    );

    # Subset of migrated rules that need $alt_idx passed to the Actions method.
    my %_needs_alt_idx = map { $_ => true } qw(
        PostfixDeref Subscript ExpressionList
    );

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
        my $key = "complete:$rule:$position:$focus_key:$children_key";
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $focus,
            children => $children,
            position => $position,
            rule     => $rule,
        ));
    }

    # Create an on_complete result Context using comonad extend().
    # Calls $f on the full Context tree, producing a new Context with
    # the result as focus and children preserved. Hash-consed by focus
    # content and children refaddrs to ensure identical derivations share
    # the same refaddr (required by FilterComposite identity comparison).
    my sub _extend_ctx($value, $f, $rule_name) {
        my $extended = $value->extend($f);
        my $focus = $extended->extract();
        my $focus_key = _tag_key($focus);
        my $children_key = join(":", map { refaddr($_) } $extended->children()->@*);
        my $key = "ext:$rule_name:" . $extended->position() . ":$focus_key:$children_key";
        return ($_ctx_cache{$key} //= $extended);
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

        # No preference: return a merged Context (not equal to either input).
        # FilterComposite sees "result equals neither" and defers to the next semiring.
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
        # BinaryExpression on_complete.
        if ($rule_name eq 'BinaryOp') {
            return $self->multiply($existing,
                _ctx({ valid => true, op_text => $matched_text }));
        }

        # UnaryExpression operator scan: capture op_text.
        if ($rule_name eq 'UnaryExpression'
            && $matched_text =~ /^(?:[!~\\]|not|[+-])$/)
        {
            return $self->multiply($existing,
                _ctx({ valid => true, op_text => $matched_text }));
        }

        # Non-QualifiedIdentifier or non-keyword: transparent
        return $self->multiply($existing, $self->one());
    }

    method on_complete($item, $alt_idx, $pos) {
        my $value = $item->{value};
        return undef if !defined $value;

        my $tags = _tags($value);
        my $rule_name = $item->{rule}->name();

        # CallExpression: builtin signature validation via tree-walk.
        # Uses $_get_call_symbol to find the function name in the Context tree,
        # then validates argument types and arity against TypeLibrary signatures.
        # Kept inline (not in Actions) because _extend_ctx changes the
        # identity of intermediate nodes, affecting _tags() flat-merge behavior
        # for ExpressionList item_types. Uses _complete_ctx to preserve
        # identity semantics until _tags() is fully removed.
        if ($rule_name eq 'CallExpression') {
            my $return_type;
            my $call_sym = $_get_call_symbol->($value);
            if ($call_sym) {
                my $sig = $builtin_lookup->($call_sym);
                if ($sig) {
                    my $item_types = $tags->{item_types};
                    if ($item_types) {
                        my $arg_types = $sig->{arg_types};
                        my $sig_offset = ($alt_idx == 2 || $alt_idx == 3) ? 1 : 0;
                        for my $i (0 .. $#$item_types) {
                            my $actual = $item_types->[$i];
                            my $sig_idx = $i + $sig_offset;
                            my $expected = $arg_types->[$sig_idx] // $arg_types->[-1];
                            if (!Chalk::Grammar::Perl::TypeLibrary::type_satisfies($actual, $expected)) {
                                return undef;
                            }
                        }
                    }
                    my $arity = $tags->{list_arity} // 1;
                    $arity += 1 if ($alt_idx == 2 || $alt_idx == 3);
                    if ($arity < $sig->{min_arity}) {
                        return undef;
                    }
                    $return_type = $sig->{return_type};
                    $return_type = undef if defined $return_type && $return_type eq 'Any';
                }
            }
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

        # Dispatch to TypeInferenceActions for rules with registered methods.
        # Migrated methods receive ($ctx) via extend() and are hash-consed
        # by _extend_ctx. Legacy methods still receive ($value, $tags, $alt_idx)
        # and use _complete_ctx.
        my $method = $actions->can($rule_name);
        if ($method) {
            if ($_migrated_to_extend{$rule_name}) {
                # Migrated: use comonad extend() — method receives full Context tree
                # Alt-dependent rules capture $alt_idx via closure
                my $f = $_needs_alt_idx{$rule_name}
                    ? sub($ctx) { $actions->$method($ctx, $alt_idx) }
                    : sub($ctx) { $actions->$method($ctx) };
                my $result = _extend_ctx($value, $f, $rule_name);
                return undef unless defined $result && defined $result->extract();
                return $result;
            }
            # Legacy: method receives ($value, $tags, $alt_idx)
            my $focus = $actions->$method($value, $tags, $alt_idx);
            return undef unless defined $focus;
            return _complete_ctx(
                $focus,
                $value->children(),
                $value->position(),
                $rule_name,
            );
        }

        # Catch-all: rules without Actions methods propagate all relevant tags.
        # _tags() returns the focus of the current node if present, so the
        # catch-all must copy tags upward to keep them visible to _tags()
        # at parent rule boundaries. This is the flat-merge behavior that
        # will be replaced by tree-walking in a future phase.
        return _complete_ctx(
            {
                valid => true,
                ($tags->{type}       ? (type       => $tags->{type})       : ()),
                ($tags->{op_text}    ? (op_text    => $tags->{op_text})    : ()),
                ($tags->{call_symbol} ? (call_symbol => $tags->{call_symbol}) : ()),
                ($tags->{item_types} ? (item_types  => $tags->{item_types}) : ()),
                ($tags->{list_arity} ? (list_arity  => $tags->{list_arity}) : ()),
            },
            $value->children(),
            $value->position(),
            $rule_name,
        );
    }

    # should_scan: gate for scan operation, called after regex match succeeds
    # Returns true to proceed with scan, false to skip it.
    # Rejects keywords as QualifiedIdentifier when a keyword-consuming rule is predicted.
    method should_scan($item, $alt_idx, $pos, $matched_text, $is_predicted) {
        my $rule_name = $item->{rule}->name();

        # Only filter QualifiedIdentifier scans
        return true unless $rule_name eq 'QualifiedIdentifier';

        # Qualified identifiers with :: are never keywords (Foo::class is OK)
        return true if $matched_text =~ /::/;

        # Check if matched text is a keyword
        return true unless $keyword_check->($matched_text);

        # Check if any keyword-consuming rule is predicted at this position
        my $keyword_rules = Chalk::Grammar::Perl::KeywordTable::keyword_rules($matched_text);
        return true unless $keyword_rules;

        for my $kr ($keyword_rules->@*) {
            if ($is_predicted->($kr)) {
                # A rule that consumes this keyword is predicted here.
                # Reject this keyword-as-identifier scan.
                return false;
            }
        }

        # No keyword-consuming rule predicted — admit as identifier
        # (e.g., fat-arrow: class => "Foo" inside an expression list)
        return true;
    }
}

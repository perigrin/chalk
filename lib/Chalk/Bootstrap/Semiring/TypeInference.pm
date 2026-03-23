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

    # Rules that need $alt_idx passed to the Actions method via closure.
    my $_needs_alt_idx = {PostfixDeref => true, Subscript => true, ExpressionList => true};

    # Singleton for one(): a Context with { valid => true } focus and no children.
    my $_one_singleton;

    # Pre-cached scan Contexts for constant tag combinations.
    # Avoids calling _ctx() at runtime by pre-caching common tag combinations
    # during initialization.
    my $_scan_regex;
    my $_scan_scalar;
    my $_scan_array;
    my $_scan_hash;
    my $_scan_str;
    my $_scan_coderef;
    my $_scan_num;
    my $_scan_int;
    my $_scan_undef;
    my $_scan_bool;

    # Serialize arrayref values by joining elements with semicolons.
    # Separate method avoids nested map (XS codegen shares $_ across maps).
    method _join_array($arr) {
        return join(';', map { $_ // '' } $arr->@*);
    }

    # Serialize a tag hash to a stable string key for hash-consing.
    # Handles arrayref values (e.g. item_types) by joining with semicolons.
    method _tag_key($tags) {
        return join(",", map {
            my $v = $tags->{$_};
            "$_=" . (ref($v) eq 'ARRAY' ? $self->_join_array($v) : ($v // ''))
        } sort keys $tags->%*);
    }

    # Create a leaf Context with the given tag hash as focus.
    # Hash-consed: same tag content → same object.
    method _ctx($tags) {
        my $key = "scan:" . $self->_tag_key($tags);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $tags,
            children => [],
            position => 0,
            rule     => undef,
        ));
    }

    # Construct an extended Context with a pre-computed focus (no closure needed).
    # Builds a new Context preserving children/position/rule/annotations from
    # $value but replacing the focus. Hash-consed by focus content and children
    # refaddrs to ensure identical derivations share the same refaddr
    # (required by FilterComposite identity comparison).
    method _extend_ctx_with_focus($value, $focus, $rule_name) {
        return undef unless defined $focus;
        my $extended = Chalk::Bootstrap::Context->new(
            focus       => $focus,
            children    => $value->children(),
            position    => $value->position(),
            rule        => $value->rule(),
            annotations => $value->annotations(),
        );
        my $focus_key = $self->_tag_key($focus);
        my $children_key = join(":", map { refaddr($_) } $extended->children()->@*);
        my $key = "ext:$rule_name:" . $extended->position() . ":$focus_key:$children_key";
        return ($_ctx_cache{$key} //= $extended);
    }

    # Tree-walkers for CallExpression on_complete.
    # Follow leaf-finding semantics: stop at focused nodes (on_complete
    # results) and only recurse through unfocused multiply nodes.

    # Search the multiply tree leaves for one with call_symbol in its focus.
    # Returns the call_symbol string or undef.
    method _get_call_symbol($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            # Focused node (leaf): check for call_symbol and stop
            return $focus->{call_symbol};
        }
        # Unfocused multiply node: recurse into children
        for my $child ($ctx->children()->@*) {
            my $found = $self->_get_call_symbol($child);
            return $found if defined $found;
        }
        return;
    }

    # Search the multiply tree leaves for one with item_types in its focus.
    # Returns the item_types arrayref or undef.
    method _get_item_types($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{item_types};
        }
        for my $child ($ctx->children()->@*) {
            my $found = $self->_get_item_types($child);
            return $found if defined $found;
        }
        return;
    }

    # Search the multiply tree leaves for one with list_arity in its focus.
    # Returns the list_arity integer or undef.
    method _get_list_arity($ctx) {
        return unless defined $ctx;
        my $focus = $ctx->extract();
        if (defined $focus) {
            return $focus->{list_arity};
        }
        for my $child ($ctx->children()->@*) {
            my $found = $self->_get_list_arity($child);
            return $found if defined $found;
        }
        return;
    }

    method zero() {
        return undef;
    }

    method one() {
        return ($_one_singleton //= $self->_ctx({ valid => true }));
    }

    method is_zero($value) {
        return !defined $value;
    }

    # Clear hash-cons cache between parses to prevent unbounded growth.
    # Cache entries from one file are not useful for subsequent files
    # because they reference different Context refaddrs.
    method reset_cache() {
        %_ctx_cache = ();
        $_one_singleton = undef;
        $_scan_regex = undef;
        $_scan_scalar = undef;
        $_scan_array = undef;
        $_scan_hash = undef;
        $_scan_str = undef;
        $_scan_coderef = undef;
        $_scan_num = undef;
        $_scan_int = undef;
        $_scan_undef = undef;
        $_scan_bool = undef;
        Chalk::Bootstrap::Semiring::TypeInferenceActions::reset_method_registry();
    }

    # _init_scan_cache pre-populates cached scan Contexts for common
    # constant-tag combinations (types, variables) on first use.
    method _init_scan_cache() {
        $_scan_regex   //= $self->_scan_ctx_type('Regex');
        $_scan_scalar  //= $self->_scan_ctx_type('Scalar');
        $_scan_array   //= $self->_scan_ctx_type('Array');
        $_scan_hash    //= $self->_scan_ctx_type('Hash');
        $_scan_str     //= $self->_scan_ctx_type('Str');
        $_scan_coderef //= $self->_scan_ctx_type('CodeRef');
        $_scan_num     //= $self->_scan_ctx_type('Num');
        $_scan_int     //= $self->_scan_ctx_type('Int');
        $_scan_undef   //= $self->_scan_ctx_type('Undef');
        $_scan_bool    //= $self->_scan_ctx_type('Bool');
    }

    # Build a scan Context with a dynamic tag hash.
    # Constructs the hash, hash-conses via _tag_key, and creates a Context
    # directly for dynamic scan content (identifiers, operators).
    method _scan_ctx_ident($matched_text) {
        my $tags = { valid => true, ident_text => $matched_text };
        my $key = "scan:" . $self->_tag_key($tags);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $tags,
            children => [],
            position => 0,
            rule     => undef,
        ));
    }

    method _scan_ctx_call_ident($matched_text) {
        my $tags = { valid => true, call_symbol => $matched_text, ident_text => $matched_text };
        my $key = "scan:" . $self->_tag_key($tags);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $tags,
            children => [],
            position => 0,
            rule     => undef,
        ));
    }

    method _scan_ctx_op($matched_text) {
        my $tags = { valid => true, op_text => $matched_text };
        my $key = "scan:" . $self->_tag_key($tags);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $tags,
            children => [],
            position => 0,
            rule     => undef,
        ));
    }

    method _scan_ctx_type($type_str) {
        my $tags = { valid => true, type => $type_str };
        my $key = "scan:" . $self->_tag_key($tags);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => $tags,
            children => [],
            position => 0,
            rule     => undef,
        ));
    }

    # Wrap builtin lookup as a method call so XS codegen can compile it.
    # Calls the package sub directly rather than going through the field
    # coderef, because XS codegen drops arguments for coderef calls
    # ($coderef->($arg) loses $arg in the IR).
    method _lookup_builtin($name) {
        return Chalk::Grammar::Perl::TypeLibrary::get_builtin($name);
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

        # Lazy-init pre-cached scan Contexts on first call
        $self->_init_scan_cache() if !defined $_scan_regex;

        my $rule_name = $item->{rule}->name();

        # RegexLiteral → type => 'Regex' (including empty // which is
        # ambiguous with defined-or; Earley explores both paths and
        # disambiguation happens via CallExpression arg-type validation)
        if ($rule_name eq 'RegexLiteral') {
            return $self->multiply($existing, $_scan_regex);
        }

        # In QualifiedIdentifier context, tag bare builtins with their name
        # so CallExpression can look up the full signature for validation.
        # All QualifiedIdentifier scans also get ident_text for method name extraction.
        if ($rule_name eq 'QualifiedIdentifier') {
            if (!($matched_text =~ /::/) && $self->_lookup_builtin($matched_text)) {
                return $self->multiply($existing,
                    $self->_scan_ctx_call_ident($matched_text));
            }
            return $self->multiply($existing,
                $self->_scan_ctx_ident($matched_text));
        }

        # Tag variable scans with their type
        if ($rule_name eq 'ScalarVariable') {
            return $self->multiply($existing, $_scan_scalar);
        }
        if ($rule_name eq 'ArrayVariable') {
            return $self->multiply($existing, $_scan_array);
        }
        if ($rule_name eq 'HashVariable') {
            return $self->multiply($existing, $_scan_hash);
        }

        # NumericLiteral: distinguish Int vs Num based on pattern
        if ($rule_name eq 'NumericLiteral') {
            # Hex (0x), binary (0b), octal (0[0-7]), or plain integer → Int
            # Float (has .) or scientific (has e/E but not hex 0x) → Num
            if ($matched_text =~ /[.]/
                || ($matched_text =~ /[eE]/ && !($matched_text =~ /^0[xX]/)))
            {
                return $self->multiply($existing, $_scan_num);
            }
            return $self->multiply($existing, $_scan_int);
        }

        # StringLiteral → type => 'Str'
        if ($rule_name eq 'StringLiteral') {
            return $self->multiply($existing, $_scan_str);
        }

        # Literal: undef/true/false
        if ($rule_name eq 'Literal') {
            if ($matched_text eq 'undef') {
                return $self->multiply($existing, $_scan_undef);
            }
            if ($matched_text eq 'true' || $matched_text eq 'false') {
                return $self->multiply($existing, $_scan_bool);
            }
        }

        # Atom: __SUB__ → type => 'CodeRef'
        if ($rule_name eq 'Atom' && $matched_text eq '__SUB__') {
            return $self->multiply($existing, $_scan_coderef);
        }

        # BinaryOp: capture operator text for later consumption at
        # BinaryExpression on_complete.
        if ($rule_name eq 'BinaryOp') {
            return $self->multiply($existing,
                $self->_scan_ctx_op($matched_text));
        }

        # UnaryExpression operator scan: capture op_text.
        if ($rule_name eq 'UnaryExpression'
            && $matched_text =~ /^(?:[!~\\]|not|[+-])$/)
        {
            return $self->multiply($existing,
                $self->_scan_ctx_op($matched_text));
        }

        # Non-QualifiedIdentifier or non-keyword: transparent
        return $self->multiply($existing, $self->one());
    }

    method on_complete($item, $alt_idx, $pos, $on_epoch_commit = undef) {
        my $value = $item->{value};
        return undef if !defined $value;

        my $rule_name = $item->{rule}->name();

        # CallExpression: builtin signature validation.
        # Kept inline (not in TypeInferenceActions) because it needs
        # complex multi-walker logic: $_get_call_symbol for function name,
        # $_get_item_types/$_get_list_arity for argument info, plus
        # builtin_lookup and type_satisfies for per-position validation.
        if ($rule_name eq 'CallExpression') {
            my $return_type;
            my $call_sym = $self->_get_call_symbol($value);
            if ($call_sym) {
                my $sig = $self->_lookup_builtin($call_sym);
                if ($sig) {
                    my $item_types = $self->_get_item_types($value);
                    if ($item_types) {
                        my $arg_types = $sig->{arg_types};
                        my $sig_offset = ($alt_idx == 2 || $alt_idx == 3) ? 1 : 0;
                        for my $i (0 .. $#$item_types) {
                            my $actual = $item_types->[$i];
                            my $sig_idx = $i + $sig_offset;
                            my $expected = $arg_types->[$sig_idx];
                            $expected = $arg_types->[-1] if !defined $expected;
                            if (!Chalk::Grammar::Perl::TypeLibrary::type_satisfies($actual, $expected)) {
                                return undef;
                            }
                        }
                    }
                    my $arity = $self->_get_list_arity($value) // 1;
                    $arity += 1 if ($alt_idx == 2 || $alt_idx == 3);
                    if ($arity < $sig->{min_arity}) {
                        return undef;
                    }
                    # For 'return', propagate the argument's type instead of
                    # the signature's return_type ('Any'). This lets the enclosing
                    # method know what type is actually being returned.
                    if ($call_sym eq 'return') {
                        my $arg_types = $self->_get_item_types($value);
                        $return_type = $arg_types->[0] if $arg_types && $arg_types->@*;
                    } else {
                        $return_type = $sig->{return_type};
                    }
                    $return_type = undef if defined $return_type && $return_type eq 'Any';
                }
            }
            my $new_focus = { valid => true };
            $new_focus->{type} = $return_type if $return_type;
            return $self->_extend_ctx_with_focus($value, $new_focus, $rule_name);
        }

        # Dispatch to TypeInferenceActions for rules with registered methods.
        # Methods receive the Context directly and return a focus hash.
        # Alt-dependent rules receive $alt_idx as an extra parameter.
        if ($actions->can($rule_name)) {
            my $action_focus = $actions->dispatch($rule_name, $value,
                $_needs_alt_idx->{$rule_name} ? $alt_idx : undef);
            return undef unless defined $action_focus;
            return $self->_extend_ctx_with_focus($value, $action_focus, $rule_name);
        }

        # Catch-all: transparent passthrough for rules without Actions methods.
        # No tag propagation needed — tree-walkers in Actions methods find
        # tags in child focuses regardless of how many intermediate rules
        # sit between producer and consumer. The unfocused multiply node
        # preserves its children for tree-walking.
        return $value;
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

        # Check if matched text is a keyword.
        # Calls the package sub directly instead of through the field coderef
        # because XS codegen drops arguments for coderef calls.
        return true unless Chalk::Grammar::Perl::KeywordTable::is_keyword($matched_text);

        # Hard keywords are always rejected as identifiers, regardless of
        # prediction state. Prevents non-deterministic parsing when nullable
        # rules (ElsifChain?) cause prediction order to vary.
        return false if Chalk::Grammar::Perl::KeywordTable::is_hard_keyword($matched_text);

        # Check if any keyword-consuming rule is predicted at this position
        my $keyword_rules = Chalk::Grammar::Perl::KeywordTable::keyword_rules($matched_text);
        return true unless $keyword_rules;

        for my $kr ($keyword_rules->@*) {
            my $predicted = ref($is_predicted) eq 'HASH'
                ? exists $is_predicted->{$kr}
                : $is_predicted->($kr);
            if ($predicted) {
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

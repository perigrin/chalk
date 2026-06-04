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

    # _walk_annotations: Walk the shared Context tree collecting annotations->{type}.
    # Unlike Context->walk(), this method descends into ALL nodes (including focused
    # ones) because SA scan nodes have defined focus (scanned text) but no annotations.
    # The TI type information is in annotations->{type}, not in the focus.
    # Traversal order: left-to-right (reverse=false) or right-to-left (reverse=true).
    # Optional $prune callback: when defined and $prune->($node) returns true,
    # the node's children are NOT enqueued (descent is blocked). The callback still
    # runs on the pruned node itself — this lets walkers find a value set directly
    # on a completed sub-expression result (e.g. the `type` field of a CallExpression
    # or AnonymousSub result) while preventing descent into that result's children.
    # The root node (depth 0) is never pruned to preserve Bug 5's self-prune protection.
    # Returns the first non-undef result from $callback.
    my sub _walk_annotations($ctx, $callback, $reverse = false, $prune = undef) {
        return undef unless defined $ctx;
        # Stack entries are [node, depth] pairs. Root is at depth 0.
        my @stack = ([$ctx, 0]);
        while (@stack) {
            my ($node, $depth) = pop(@stack)->@*;
            # Always check this node's annotations (regardless of focus state)
            my $result = $callback->($node);
            return $result if defined $result;
            # Prune only inner nodes (depth > 0), never the root (depth 0).
            # This preserves Bug 5's self-prune protection (root is never pruned).
            # When prune fires, we stop descending into children but have already
            # called the callback on this node above.
            next if $depth > 0 && defined $prune && $prune->($node);
            # Descend into children (unless pruned above)
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, map { [$_, $depth + 1] } @kids;
        }
        return undef;
    }

    # Tree-walkers for complete events.
    # Walk the shared Context tree, reading type tags from annotations->{type}.
    # Use _walk_annotations (not Context->walk) because SA scan nodes have defined
    # focus (scanned text) but no annotations — Context->walk would stop there.

    # _is_completed_sub_expr: prune callback for all walker callers.
    # Returns true when a node represents a completed sub-expression result
    # (has annotations->{type} with 'valid' but without 'item_types').
    # Such nodes are the output of an inner CallExpression, AnonymousSub,
    # ParenExpr, Block, or other rule completion; their subtrees contain type
    # and call_symbol information that belongs to the inner expression, not to
    # the outer context being queried.
    # Treating these nodes as opaque leaves prevents walker leakage of inner
    # types or call_symbols into outer callers.
    # NOTE: Must stay in sync with the identical predicate in TypeInferenceActions.pm.
    my $is_completed_sub_expr = sub ($n) {
        my $type = $n->annotations()->{type};
        return false unless defined $type && ref($type) eq 'HASH';
        return exists $type->{valid} && !exists $type->{item_types};
    };

    # Search the shared tree nodes for one with call_symbol in annotations->{type}.
    # Returns the call_symbol string or undef.
    # Uses $is_completed_sub_expr prune to stop at inner sub-expression boundaries.
    method _get_call_symbol($ctx) {
        return unless defined $ctx;
        return _walk_annotations($ctx, sub ($n) {
            my $type = $n->annotations()->{type};
            return undef unless defined $type && ref($type) eq 'HASH';
            return $type->{call_symbol};
        }, false, $is_completed_sub_expr);
    }

    # Search the shared tree nodes for one with item_types in annotations->{type}.
    # Returns the item_types arrayref or undef.
    # Uses $is_completed_sub_expr as prune callback to stop at inner call boundaries.
    method _get_item_types($ctx) {
        return unless defined $ctx;
        return _walk_annotations($ctx, sub ($n) {
            my $type = $n->annotations()->{type};
            return undef unless defined $type && ref($type) eq 'HASH';
            return $type->{item_types};
        }, false, $is_completed_sub_expr);
    }

    # Search the shared tree nodes for one with list_arity in annotations->{type}.
    # Returns the list_arity integer or undef.
    # Uses $is_completed_sub_expr as prune callback to stop at inner call boundaries.
    method _get_list_arity($ctx) {
        return unless defined $ctx;
        return _walk_annotations($ctx, sub ($n) {
            my $type = $n->annotations()->{type};
            return undef unless defined $type && ref($type) eq 'HASH';
            return $type->{list_arity};
        }, false, $is_completed_sub_expr);
    }

    # Search the shared tree nodes (rightmost first) for one with type in annotations->{type}.
    # Returns the type string or undef. Used by the catch-all passthrough in _complete_type.
    # Uses $is_completed_sub_expr prune to stop at inner sub-expression boundaries.
    method _get_rightmost_type($ctx) {
        return unless defined $ctx;
        return _walk_annotations($ctx, sub ($n) {
            my $type = $n->annotations()->{type};
            return undef unless defined $type && ref($type) eq 'HASH';
            return $type->{type};
        }, true, $is_completed_sub_expr);  # reverse=true, prune at boundaries
    }

    method zero() {
        return undef;
    }

    method one() {
        return ($_one_singleton //= $self->_ctx({ valid => true }));
    }

    # Pass-through: TypeInference semiring does not carry control state.
    # The lateral-seed channel is handled at the SemanticAction layer.
    method one_with_control($node) { return $self->one() }

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

    # Builtins whose first argument is a hash or array: keys %hash, values %hash, each %hash.
    # When these are the LHS of what looks like a BinaryExpression, the % is a hash
    # sigil, not the modulo operator.
    my %HASH_ARG_BUILTINS = map { $_ => true } qw(keys values each);

    method multiply($left, $right) {
        # Propagate zero
        return undef if !defined $left;
        return undef if !defined $right;

        # Scan event: right Context has annotations->{scan} = true.
        # Apply keyword rejection filtering and type-tag attachment.
        # Returns a tag hash (not a Context) as the new type slot value.
        # Returns undef (zero) when the scan is rejected (e.g., keyword at
        # identifier position, or % after hash-taking builtin).
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{scan}) {
            my $rule_name    = $right->annotations()->{rule_name} // '';
            my $matched_text = $right->focus() // '';
            my $is_predicted = $right->annotations()->{predicted} // {};

            # Keyword rejection: reject keywords as QualifiedIdentifier
            # when a keyword-consuming rule is predicted.
            if ($rule_name eq 'BinaryOp' && $matched_text eq '%') {
                # Reject % as BinaryOp when LHS has call_symbol for hash-taking builtin
                my $type_ann = $left->annotations()->{type};
                if (defined $type_ann && ref($type_ann) eq 'HASH'
                        && exists $type_ann->{call_symbol}
                        && $HASH_ARG_BUILTINS{ $type_ann->{call_symbol} }) {
                    return undef;
                }
                my $call_sym = $self->_get_call_symbol($left);
                if (defined $call_sym && $HASH_ARG_BUILTINS{$call_sym}) {
                    return undef;
                }
            }

            if ($rule_name eq 'QualifiedIdentifier'
                    && !($matched_text =~ /::/)
                    && Chalk::Grammar::Perl::KeywordTable::is_keyword($matched_text)) {
                # Hard keywords are always rejected as identifiers
                if (Chalk::Grammar::Perl::KeywordTable::is_hard_keyword($matched_text)) {
                    return undef;
                }
                # Check if any keyword-consuming rule is predicted here
                my $keyword_rules = Chalk::Grammar::Perl::KeywordTable::keyword_rules($matched_text);
                if ($keyword_rules) {
                    for my $kr ($keyword_rules->@*) {
                        my $predicted = ref($is_predicted) eq 'HASH'
                            ? exists $is_predicted->{$kr}
                            : $is_predicted->($kr);
                        if ($predicted) {
                            return undef;  # Keyword-consuming rule predicted: reject
                        }
                    }
                }
            }

            # Type-tag attachment: return tag hash for this scan.
            # Lazy-init pre-cached scan Contexts on first call.
            $self->_init_scan_cache() if !defined $_scan_regex;
            return $self->_type_tag_for_scan($rule_name, $matched_text);
        }

        # Complete event: right Context has annotations->{complete} = true.
        # Apply type inference for the completed rule.
        if (blessed($right) && $right->can('annotations')
                && $right->annotations()->{complete}) {
            my $rule_name = $right->annotations()->{rule_name};
            my $alt_idx   = $right->annotations()->{alt_idx};
            return $self->_complete_type($left, $rule_name, $alt_idx);
        }

        # Non-scan/non-complete multiply: build a hash-consed Context tree with
        # $left and $right as children. The complete-event handler walks this tree
        # via _walk_annotations to find type annotations in leaf annotations->{type}.
        # FC.is_zero calls TI.is_zero on this result — Context is always non-undef.
        my $key = "mul:" . refaddr($left) . ":" . refaddr($right);
        return ($_ctx_cache{$key} //= Chalk::Bootstrap::Context->new(
            focus    => undef,
            children => [$left, $right],
            position => (blessed($right) && $right->can('position')) ? $right->position() : 0,
            rule     => undef,
        ));
    }

    # _complete_type: apply type inference for a completed rule.
    # Receives the accumulated TI Context and rule metadata from multiply.
    method _complete_type($value, $rule_name, $alt_idx) {
        return undef if !defined $value;

        # CallExpression: builtin signature validation.
        # Kept inline (not in TypeInferenceActions) because it needs
        # complex multi-walker logic: _get_call_symbol for function name,
        # _get_item_types/_get_list_arity for argument info, plus
        # builtin_lookup and type_satisfies for per-position validation.
        # $value is the shared Context; tree-walkers read annotations->{type}.
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
            return $new_focus;
        }

        # Dispatch to TypeInferenceActions for rules with registered methods.
        # Methods receive the shared Context directly and return a focus hash.
        # Tree-walkers in Actions read annotations->{type} from child nodes.
        # Alt-dependent rules receive $alt_idx as an extra parameter.
        if ($actions->can($rule_name)) {
            my $action_focus = $actions->dispatch($rule_name, $value,
                $_needs_alt_idx->{$rule_name} ? $alt_idx : undef);
            return undef unless defined $action_focus;
            return $action_focus;
        }

        # Catch-all: transparent passthrough for rules without Action methods.
        # Propagates the rightmost type from children so type information flows
        # upward through wrapper rules (e.g., Variable, PostfixExpression alt 0).
        # FilterComposite stores the returned hash as annotations->{type}.
        my $child_type = $self->_get_rightmost_type($value);
        my $result_hash = { valid => true };
        $result_hash->{type} = $child_type if defined $child_type;
        return $result_hash;
    }

    # _type_tag_for_scan: return the type tag hash for a scan event.
    # Called from multiply when right Context has annotations->{scan}=true.
    method _type_tag_for_scan($rule_name, $matched_text) {
        # RegexLiteral → type => 'Regex'
        if ($rule_name eq 'RegexLiteral') {
            return $_scan_regex->extract();
        }

        # In QualifiedIdentifier context, tag bare builtins with their name
        if ($rule_name eq 'QualifiedIdentifier') {
            if (!($matched_text =~ /::/) && $self->_lookup_builtin($matched_text)) {
                return $self->_scan_ctx_call_ident($matched_text)->extract();
            }
            return $self->_scan_ctx_ident($matched_text)->extract();
        }

        # Tag variable scans with their type
        if ($rule_name eq 'ScalarVariable') {
            return $_scan_scalar->extract();
        }
        if ($rule_name eq 'ArrayVariable') {
            return $_scan_array->extract();
        }
        if ($rule_name eq 'HashVariable') {
            return $_scan_hash->extract();
        }

        # NumericLiteral: distinguish Int vs Num
        if ($rule_name eq 'NumericLiteral') {
            if ($matched_text =~ /[.]/
                || ($matched_text =~ /[eE]/ && !($matched_text =~ /^0[xX]/)))
            {
                return $_scan_num->extract();
            }
            return $_scan_int->extract();
        }

        # StringLiteral → type => 'Str'
        if ($rule_name eq 'StringLiteral') {
            return $_scan_str->extract();
        }

        # Literal: undef/true/false
        if ($rule_name eq 'Literal') {
            if ($matched_text eq 'undef') {
                return $_scan_undef->extract();
            }
            if ($matched_text eq 'true' || $matched_text eq 'false') {
                return $_scan_bool->extract();
            }
        }

        # Atom: __SUB__ → type => 'CodeRef'
        if ($rule_name eq 'Atom' && $matched_text eq '__SUB__') {
            return $_scan_coderef->extract();
        }

        # BinaryOp: capture operator text
        if ($rule_name eq 'BinaryOp') {
            return $self->_scan_ctx_op($matched_text)->extract();
        }

        # UnaryExpression operator scan: capture op_text
        if ($rule_name eq 'UnaryExpression'
            && $matched_text =~ /^(?:[!~\\]|not|[+-])$/)
        {
            return $self->_scan_ctx_op($matched_text)->extract();
        }

        # Non-matching scan: transparent (no type info)
        return $self->one()->extract();
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

    # slot_name: TypeInference reads/writes the 'type' annotation slot.
    method slot_name() {
        return 'type';
    }
}

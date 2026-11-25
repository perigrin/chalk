# ABOUTME: Type inference action methods dispatched by TypeInference multiply for complete events.
# ABOUTME: Each method receives a Context via extend(), returns a focus hash for the completed rule.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Grammar::Perl::TypeLibrary;
class Chalk::Bootstrap::Semiring::TypeInferenceActions {

    # _walk_ann: Walk the shared Context tree reading annotations->{type}.
    # Unlike Context->walk(), always descends into children regardless of focus state.
    # SA scan nodes have defined focus (text string) but no annotations->{type}.
    # Context->walk() would stop at those nodes; we must descend past them.
    # reverse=true for right-to-left traversal.
    # Optional $prune callback: when defined and $prune->($node) returns true at
    # depth > 0, the callback has already run on that node but its children are
    # not pushed. The root (depth 0) is never pruned — this preserves Bug 5's
    # self-prune protection. Stack entries are [node, depth] pairs.
    my sub _walk_ann($ctx, $callback, $reverse = false, $prune = undef) {
        return undef unless defined $ctx;
        my @stack = ([$ctx, 0]);
        while (@stack) {
            my ($node, $depth) = pop(@stack)->@*;
            # Always run callback first (finds type values on scan leaf nodes).
            my $result = $callback->($node);
            return $result if defined $result;
            # Prune only inner nodes (depth > 0), never the root.
            # When prune fires, stop descending into children but the callback
            # above has already run on this node.
            next if $depth > 0 && defined $prune && $prune->($node);
            my @kids = $node->children()->@*;
            @kids = reverse @kids unless $reverse;
            push @stack, map { [$_, $depth + 1] } @kids;
        }
        return undef;
    }

    # _is_completed_sub_expr: prune predicate for all walker callers.
    # Returns true when a node represents a completed sub-expression result
    # (has annotations->{type} with 'valid' but without 'item_types').
    # Treats inner CallExpression results, AnonymousSub results, ParenExpr
    # results, Block results, and other completed rule outputs as opaque leaves.
    # Prune fires AFTER the callback has run on the node (see _walk_ann semantics).
    # This stops descent into inner sub-expression children without skipping the
    # node's own annotations, preventing type/call_symbol leakage from inner
    # sub-expressions while still reading the boundary node's own type.
    # NOTE: Must stay in sync with the identical predicate in TypeInference.pm.
    #
    # A COMPLETION, not a partial item: the node must carry the rule it
    # completed. The partial items between a rule's symbols (an
    # ExpressionList and its left operand, say) carry a `valid` TI tag too;
    # pruning at them (fc4524ef) hid every argument but the last from the
    # collectors, so `push(@a, 1)` reached the signature check as (Int).
    my $is_completed_sub_expr = sub ($n) {
        return false unless defined $n->rule();
        my $type = $n->annotations()->{type};
        return false unless defined $type && ref($type) eq 'HASH';
        return exists $type->{valid} && !exists $type->{item_types};
    };

    # Helper: Get rightmost type from shared Context tree (for wrapper rules).
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_rightmost_type($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return $ti->{type};
        }, true, $is_completed_sub_expr);  # reverse=true, prune at boundaries
    }

    # Helper: Get leftmost type from shared Context tree (for assignment LHS).
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_leftmost_type($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return $ti->{type};
        }, false, $is_completed_sub_expr);
    }

    # Helper: Get ident_text from shared Context tree (for method/function names).
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_ident_text($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return $ti->{ident_text};
        }, false, $is_completed_sub_expr);
    }

    # Method return type registry: method_name => return_type
    # Populated by MethodDefinition complete event, consumed by MethodCall lookups.
    # Scoped per file parse (reset via reset_method_registry).
    my %_method_returns;

    # Helper: Get op_text from shared Context tree (for operator rules).
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_op_text($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return $ti->{op_text};
        }, false, $is_completed_sub_expr);
    }

    # Wrapper rules: passthrough child's type

    # Helper: Get call_symbol from shared Context tree (for builtin disambiguation).
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_call_symbol($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return $ti->{call_symbol};
        }, false, $is_completed_sub_expr);
    }

    method Atom($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        my $call_sym = _get_call_symbol($ctx);
        return { valid => true,
            ($child_type ? (type => $child_type) : ()),
            ($call_sym   ? (call_symbol => $call_sym) : ()),
        };
    }

    method Expression($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        my $call_sym = _get_call_symbol($ctx);
        return { valid => true,
            ($child_type ? (type => $child_type) : ()),
            ($call_sym   ? (call_symbol => $call_sym) : ()),
        };
    }

    method PostfixExpression($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return { valid => true, ($child_type ? (type => $child_type) : ()) };
    }

    # Rich rules: compute type from operator/signature

    # keys, values and each take a hash; none of them is a term on its own
    # (perl: "Not enough arguments for keys"). After one of them perl
    # expects a term, so a `%` there starts the hash: `sort keys %h` is
    # sort(keys(%h)), never (sort keys) % h nor sort(keys % h).
    my %NEEDS_HASH_ARG = map { $_ => true } qw(keys values each);

    # The rule's own symbols, in order: the named children reached through
    # the unnamed item-prefix nodes that chain them.
    my sub _rule_symbols($ctx) {
        my @out;
        my @todo = $ctx->children()->@*;
        while (@todo) {
            my $c = shift @todo;
            if (defined $c->rule()) { push @out, $c }
            else                    { unshift @todo, $c->children()->@* }
        }
        return @out;
    }

    # The last token a subtree scanned, with the rules that enclose it
    # (outermost first): [text, [rules]]. undef when the subtree ends in
    # something that is not a scanned token.
    my sub _last_token($n, $rules = []) {
        my @kids = $n->children()->@*;
        if (!@kids) {
            my $f = $n->focus();
            return undef if ref $f;
            return defined $f && $f =~ /\S/ ? [$f, $rules] : false;
        }
        my $inner = defined $n->rule() ? [$rules->@*, $n->rule()] : $rules;
        for my $c (reverse @kids) {
            my $r = __SUB__->($c, $inner);
            return $r if !defined $r || $r;
        }
        return false;
    }

    # True when a BinaryExpression's left operand ends in a bare keys,
    # values or each read as a term (Atom > QualifiedIdentifier) -- not a
    # method name, not a hash key in braces (those end in `}`).
    my sub _left_ends_in_bare_hash_op($ctx) {
        my ($left) = grep { $_->rule() eq 'Expression' } _rule_symbols($ctx);
        return false unless defined $left;
        my $tok = _last_token($left);
        return false unless $tok;
        my ($text, $rules) = $tok->@*;
        return $NEEDS_HASH_ARG{$text}
            && $rules->@* >= 2
            && $rules->[-1] eq 'QualifiedIdentifier'
            && $rules->[-2] eq 'Atom';
    }

    method BinaryExpression($ctx) {
        return undef if _left_ends_in_bare_hash_op($ctx);
        my $op = _get_op_text($ctx);
        my $result_type;
        if (defined $op) {
            my $sig = Chalk::Grammar::Perl::TypeLibrary::get_binary_op($op);
            # A List result is a real answer -- `..` builds a list -- so take
            # it. An Unknown result is not: the short-circuit operators return
            # one of their operands, so the signature cannot name the type and
            # leaving it undef lets a later pass narrow it.
            if ($sig && $sig->{result} ne 'Unknown') {
                $result_type = $sig->{result};
            }
        } else {
            # No op_text: preserve child type (intermediate completion)
            $result_type = _get_rightmost_type($ctx);
        }
        return { valid => true, ($result_type ? (type => $result_type) : ()) };
    }

    method UnaryExpression($ctx) {
        my $op = _get_op_text($ctx);
        my $result_type;
        # perlop: "Unary + has no effect whatsoever, even on strings" -- its
        # value is its operand, of the operand's type (`keys +($h // {})->%*`
        # hands keys a Hash).
        if (defined $op && $op eq '+') {
            my $t = _get_rightmost_type($ctx);
            return { valid => true, (defined $t ? (type => $t) : ()) };
        }
        # A number's negation is the same kind of number; anything else's is
        # the table's Scalar (-"abc" is "-abc"). B::SoN's Negate, the same rule.
        if (defined $op && $op eq '-') {
            my $t = _get_rightmost_type($ctx);
            return { valid => true, type => $t } if defined $t && ($t eq 'Int' || $t eq 'Num');
        }
        if (defined $op) {
            my $sig = Chalk::Grammar::Perl::TypeLibrary::get_unary_op($op);
            $result_type = $sig->{result} if $sig;
        }
        return { valid => true, ($result_type ? (type => $result_type) : ()) };
    }

    # Helper: Get list_arity from shared Context tree.
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_list_arity($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return $ti->{list_arity};
        }, false, $is_completed_sub_expr);
    }

    # Helper: Get item_types from shared Context tree.
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_item_types($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return $ti->{item_types};
        }, false, $is_completed_sub_expr);
    }

    # Helper: Search for item_types in previous ExpressionList children.
    # Reads from annotations->{type} since TI migrated to shared Context (#707).
    # Uses _is_completed_sub_expr as prune to stop at inner sub-expression boundaries.
    my sub _get_prev_item_types($ctx) {
        return _walk_ann($ctx, sub ($n) {
            my $ti = $n->annotations()->{type};
            return undef unless defined $ti && ref($ti) eq 'HASH';
            return exists $ti->{item_types} ? $ti->{item_types} : undef;
        }, false, $is_completed_sub_expr);
    }

    # ExpressionList: arity/item_types tracking
    # alt 0 = single Expression (arity 1)
    # alt 1 = ExpressionList , Expression (arity = child + 1)
    # alt 2 = ExpressionList => Expression (arity = child + 1)
    # alt 3 = trailing comma (arity preserved)

    # True when an ExpressionList ends in a bare word that is not read as
    # the FatCommaWord string: an Atom > QualifiedIdentifier, or a keyword's
    # own rule (`undef` a Literal, `sub` an AnonymousSub). A method name
    # (`$o->name =>`) is no word perl quotes there.
    my sub _ends_in_unquoted_word($list) {
        my $tok = _last_token($list);
        return false unless $tok;
        my ($text, $rules) = $tok->@*;
        return false unless $text =~ /\A\s*[a-zA-Z_]\w*\s*\z/;
        return false if $rules->[-1] eq 'FatCommaWord';
        return false if $rules->@* >= 2 && $rules->[-1] eq 'QualifiedIdentifier'
            && $rules->[-2] eq 'MethodCall';
        return true;
    }

    method ExpressionList($ctx, $alt_idx = 0) {
        # Alt 2, `LIST => EXPR`: a word before `=>` is its string (perlop:
        # `=>` "forces a word to its left to be interpreted as a string"),
        # read by FatCommaWord; no other reading of it survives.
        if ($alt_idx == 2) {
            my ($left) = grep { $_->rule() eq 'ExpressionList' } _rule_symbols($ctx);
            return undef if defined $left && _ends_in_unquoted_word($left);
        }
        my ($arity, $item_types);
        if ($alt_idx == 0) {
            $arity = 1;
            my $type = _get_rightmost_type($ctx);
            # type can be undef for non-typed expressions (e.g. function calls)
            $item_types = [$type];
        } elsif ($alt_idx == 1 || $alt_idx == 2) {
            $arity = (_get_list_arity($ctx) // 1) + 1;
            my $prev = _get_prev_item_types($ctx) // [];
            my $new_type = _get_rightmost_type($ctx);
            $item_types = [$prev->@*, $new_type];
        } else {
            $arity = _get_list_arity($ctx);
            $item_types = _get_item_types($ctx) // _get_prev_item_types($ctx);
        }
        return {
            valid => true,
            ($arity ? (list_arity => $arity) : ()),
            ($item_types ? (item_types => $item_types) : ()),
        };
    }

    # CallExpression is handled inline in TypeInference.pm (not dispatched here)
    # because it requires complex multi-walker logic with builtin_lookup and
    # type_satisfies for per-position argument validation.

    # Boundary rules: preserve type, clear call_symbol/op_text

    method ParenExpr($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Block($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Signature($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    method Attribute($ctx) {
        my $child_type = _get_rightmost_type($ctx);
        return {
            valid => true,
            ($child_type ? (type => $child_type) : ()),
        };
    }

    # Subscript: type depends on alt_idx

    # True when the rule's left operand is a bare word read as a term
    # (Atom > QualifiedIdentifier) and nothing more.
    my sub _left_is_bare_word($ctx) {
        my ($left) = grep { $_->rule() eq 'Expression' } _rule_symbols($ctx);
        return false unless defined $left;
        my $tok = _last_token($left);
        return false unless $tok;
        my ($text, $rules) = $tok->@*;
        return $text =~ /\A[a-zA-Z_]\w*(?:::\w+)*\z/
            && $rules->@* >= 2
            && $rules->[-1] eq 'QualifiedIdentifier'
            && $rules->[-2] eq 'Atom';
    }

    # The scanned tokens of a subtree, in order (whitespace and comments
    # left out).
    my sub _tokens($n) {
        my @kids = $n->children()->@*;
        if (!@kids) {
            my $f = $n->focus();
            return () if ref $f || !defined $f;
            return $f =~ /\A(?:\s|#[^\n]*)*\z/ ? () : ($f);
        }
        return map { __SUB__->($_) } @kids;
    }

    # True when a subtree is one bare word and nothing else.
    my sub _is_lone_word($n) {
        my @t = _tokens($n);
        return @t == 1 && $t[0] =~ /\A\s*[a-zA-Z_]\w*\s*\z/;
    }

    method Subscript($ctx, $alt_idx = 0) {
        # Alts 3, 4 and 6 subscript without an arrow (`$a[0]`, `$h{k}`): perl
        # takes `[` or `{` straight after a term as a subscript only after a
        # variable or another subscript -- never after a bare word. `map {`
        # is map and its block, not an element of a hash named map.
        return undef if ($alt_idx == 3 || $alt_idx == 4 || $alt_idx == 6)
            && _left_is_bare_word($ctx);
        # A word alone in a hash subscript's braces is its string (perldata:
        # "a simple identifier within such curlies is forced to be a
        # string"): alts 5 and 6 (BareKey) read it so; alts 1 and 4 may not
        # read it as an expression -- `$h{s}` is no substitution, `$h{time}`
        # no call.
        if ($alt_idx == 1 || $alt_idx == 4) {
            my (undef, $index) = grep { $_->rule() eq 'Expression' } _rule_symbols($ctx);
            return undef if defined $index && _is_lone_word($index);
        }
        my $sub_type;
        if ($alt_idx <= 1 || $alt_idx == 5) {
            # alt 0 = [...] (array), alt 1 = {...} (hash) → element is Scalar
            $sub_type = 'Scalar';
        }
        # alt 2+ = ->() deref-call: type unknown (undef)
        return {
            valid => true,
            ($sub_type ? (type => $sub_type) : ()),
        };
    }

    # PostfixDeref: type depends on alt_idx

    method PostfixDeref($ctx, $alt_idx = 0) {
        my $type_tag;
        if ($alt_idx == 0) {
            $type_tag = 'Array';
        } elsif ($alt_idx == 1) {
            $type_tag = 'Hash';
        } elsif ($alt_idx >= 4) {
            # alts 4-7: ->@[...] ->@{...} ->%[...] ->%{...}, a slice: a list
            $type_tag = 'List';
        } else {
            # alts 2-3: ->$* ->$#*
            $type_tag = 'Scalar';
        }
        return { valid => true, type => $type_tag };
    }

    # Fixed return types

    # CircumfixDeref: alt 0 is @{ EXPR }, an array; alt 1 %{ EXPR }, a hash
    # (the aggregate, not the reference EXPR is).
    method CircumfixDeref($ctx, $alt_idx = 0) {
        return { valid => true, type => $alt_idx == 0 ? 'Array' : 'Hash' };
    }

    method PostfixIncDec($ctx) {
        return { valid => true, type => 'Num' };
    }

    method AnonymousSub($ctx) {
        return { valid => true, type => 'Code' };
    }

    method QwLiteral($ctx) {
        return { valid => true, type => 'List' };
    }

    method ArrayConstructor($ctx) {
        return { valid => true, type => 'ArrayRef' };
    }

    method HashConstructor($ctx) {
        return { valid => true, type => 'HashRef' };
    }

    # Unknown types (no static type information)

    method TernaryExpression($ctx) {
        return { valid => true };
    }

    method AssignmentExpression($ctx) {
        # Derive eval_context from LHS variable sigil type
        my $lhs_type = _get_leftmost_type($ctx);
        my $eval_context;
        if (defined $lhs_type) {
            if ($lhs_type eq 'Scalar') {
                $eval_context = 'Scalar';
            } elsif ($lhs_type eq 'Array' || $lhs_type eq 'Hash' || $lhs_type eq 'List') {
                # (List: a slice, `$r->@[1, 2] = ...`, is a list assignment)
                $eval_context = 'List';
            }
        }
        return {
            valid => true,
            ($eval_context ? (eval_context => $eval_context) : ()),
        };
    }

    method ExpressionStatement($ctx) {
        return { valid => true, eval_context => 'Void' };
    }

    method MethodCall($ctx) {
        return { valid => true };
    }

    # MethodDefinition: extract method name and body return type for registry
    method MethodDefinition($ctx) {
        my $method_name = _get_ident_text($ctx);
        my $body_type = _get_rightmost_type($ctx);

        # Register method return type if both name and type are available
        if (defined $method_name && defined $body_type) {
            $_method_returns{$method_name} = $body_type;
        }

        return {
            valid => true,
            ($method_name ? (method_name => $method_name) : ()),
            ($body_type ? (method_return_type => $body_type) : ()),
        };
    }

    # Dispatch an action method by name, returning the focus hash.
    # Avoids closure capture and dynamic coderef calls that the XS
    # codegen cannot handle. The caller passes the rule name as a
    # string; this method resolves it via can() and calls it.
    method dispatch($rule_name, $ctx, $alt_idx) {
        my $method = $self->can($rule_name);
        return unless $method;
        if (defined $alt_idx) {
            return $self->$method($ctx, $alt_idx);
        }
        return $self->$method($ctx);
    }

    # Registry access methods for method return types
    sub register_method_return($name, $type) {
        $_method_returns{$name} = $type;
    }

    sub lookup_method_return($name) {
        return $_method_returns{$name};
    }

    sub reset_method_registry() {
        %_method_returns = ();
    }
}

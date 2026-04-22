# ABOUTME: Semantic actions for Perl grammar that build Perl IR nodes from parse results.
# ABOUTME: One method per grammar rule, constructing ClassInfo/MethodInfo/SubInfo/etc.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Program;

# Builtin keyword sets used by _fixup_stmts for statement merging
my %LIST_BUILTINS = map { $_ => 1 } qw(push unshift pop shift splice print say warn sort reverse chomp chop);
my %PREFIX_BUILTINS = map { $_ => 1 } qw(scalar defined ref exists delete keys values each length chr ord substr sprintf join split);
my %STMT_BOUNDARY_CLASSES = map { $_ => 1 } qw(ClassDecl MethodDecl FieldDecl SubDecl VarDecl);
my %STMT_BOUNDARY_OPS = map { $_ => 1 } qw(If Loop Return Unwind);
my %STOP_KEYWORDS = map { $_ => 1 } qw(push unshift return die my for if unless while until);

# Operator-to-typed-node translation tables used by _unwrap_stmt_from_expr
my %BINOP_MAP = (
    '+'   => 'Add',        '-'   => 'Subtract',  '*'   => 'Multiply',
    '/'   => 'Divide',     '%'   => 'Modulo',     '**'  => 'Power',
    '.'   => 'Concat',
    '=='  => 'NumEq',      '!='  => 'NumNe',      '<'   => 'NumLt',
    '>'   => 'NumGt',      '<='  => 'NumLe',      '>='  => 'NumGe',
    '<=>' => 'NumCmp',
    'eq'  => 'StrEq',      'ne'  => 'StrNe',      'lt'  => 'StrLt',
    'gt'  => 'StrGt',      'le'  => 'StrLe',      'ge'  => 'StrGe',
    'cmp' => 'StrCmp',
    '&&'  => 'And',        '||'  => 'Or',
    'and' => 'And',        'or'  => 'Or',
    '&'   => 'BitAnd',     '|'   => 'BitOr',      '^'   => 'BitXor',
    '<<'  => 'LeftShift',  '>>'  => 'RightShift',
    '='   => 'Assign',
    'x'   => 'Repeat',
    '=~'  => 'Match',      '!~'  => 'NotMatch',
    '//'  => 'DefinedOr',
    'xor' => 'Xor',
    '..'  => 'Range',      '...' => 'Yada',
    'isa' => 'IsaOp',
);

my %UNOP_MAP = (
    '!'       => 'Not',
    'not'     => 'Not',
    '-'       => 'Negate',
    '~'       => 'Complement',
    'defined' => 'Defined',
    '+'       => 'UnaryPlus',
    '\\'      => 'Ref',
);

class Chalk::Bootstrap::Perl::Actions {
    field $factory;
    field $typed;

    ADJUST {
        $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
        $typed   = Chalk::IR::NodeFactory->new();
    }

    # Helper: collect all leaves with defined IR focuses (Constructor or Constant nodes)
    my sub _collect_ir_leaves($ctx) {
        my @results;
        for my $leaf ($ctx->leaves()) {
            my $focus = $leaf->extract();
            if (defined $focus) {
                push @results, $leaf;
            }
        }
        return @results;
    }

    # Helper: collect focus values from IR leaves
    my sub _collect_ir_values($ctx) {
        return map { $_->extract() } _collect_ir_leaves($ctx);
    }

    # Helper: find first Constant node in leaves
    my sub _find_constant($ctx) {
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::IR::Node::Constant) {
                return $focus;
            }
        }
        return undef;
    }

    # Helper: collect all Constant nodes from leaves
    my sub _collect_constants($ctx) {
        my @results;
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::IR::Node::Constant) {
                push @results, $focus;
            }
        }
        return @results;
    }

    # Helper: make a Constant IR node
    my sub _make_const($factory, $value) {
        return $factory->make('Constant', const_type => 'string', value => $value);
    }

    # Helper: resolve a variable name from scope, creating a Phi if needed.
    # Returns the resolved IR node if the variable is in scope (regular or sentinel),
    # or undef if no scope is active or the variable is not bound.
    # When a sentinel is resolved to a Phi, updates the cfg_state in SemanticAction.
    my sub _resolve_from_scope($ctx, $sa, $var_name, $factory) {
        return undef unless defined $sa;
        my $state = $sa->inherited_cfg_state($ctx);
        return undef unless defined $state && defined $state->{scope};
        my ($value, $new_scope) = $state->{scope}->resolve_sentinel($var_name, $factory);
        return undef unless defined $value;
        if ($new_scope) {
            $sa->update_cfg({ $state->%*, scope => $new_scope });
        }
        return $value;
    }

    # Helper: check if a BuiltinCall node should be unwrapped during push-inward
    my sub _is_unwrappable_builtin($node) {
        return false unless $node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'builtin';
        my $name = $node->inputs()->[0]->value();
        return $PREFIX_BUILTINS{$name} || $LIST_BUILTINS{$name};
    }

    # Helper: push PostfixDerefExpr inward past prefix wrappers.
    # The Earley parser's stale-value merge can misparent prefix constructs
    # (return, scalar, die, list builtins) and method calls inside
    # PostfixDeref's target. Iteratively unwraps wrapper layers, creates
    # the deref at the innermost target, then rewraps in correct order.
    #
    # Handles these misparenting patterns:
    #   PostfixDeref(Return(ctrl, X), @) → Return(ctrl, PostfixDeref(X, @))
    #   PostfixDeref(BuiltinCall(scalar, [X]), @) → BuiltinCall(scalar, [PostfixDeref(X, @)])
    #   PostfixDeref(MethodCall(BuiltinCall(push, [A, B]), m, []), @)
    #     → BuiltinCall(push, [A, PostfixDeref(MethodCall(B, m, []), @)])
    my sub _push_deref_inward($factory, $typed, $target, $sigil_node) {
        # Collect wrappers to rewrap later
        my @wrappers;
        my $current = $target;
        while (defined $current && $current isa Chalk::IR::Node) {
            if ($current isa Chalk::IR::Node::Return) {
                # Save the control token so it can be restored when re-wrapping.
                push @wrappers, ['Return', $current->inputs()->[0]];
                $current = $current->inputs()->[1];  # value is inputs[1]
            } elsif ($current isa Chalk::IR::Node::Unwind) {
                # Save control token so it can be restored when re-wrapping.
                push @wrappers, ['Unwind', $current->inputs()->[0], $current->inputs()->[1]];
                my $args = $current->inputs()->[1];
                $current = $args->[-1];
            } elsif (_is_unwrappable_builtin($current)) {
                push @wrappers, ['BuiltinCall', $current->inputs()->[0], $current->inputs()->[1]];
                my $args = $current->inputs()->[1];
                $current = $args->[-1];
            } elsif ($current isa Chalk::IR::Node::Call && $current->dispatch_kind() eq 'method') {
                # MethodCall wrapping a prefix construct — peel it off
                push @wrappers, ['MethodCallExpr', $current->inputs()->[1], $current->inputs()->[2]];
                $current = $current->inputs()->[0];  # invocant
            } else {
                last;
            }
        }

        # Create deref at the innermost target
        my $result = $typed->make('PostfixDeref',
            sigil        => (ref($sigil_node) ? $sigil_node->value() : $sigil_node),
            inputs       => (ref($sigil_node) ? [$current, $sigil_node] : [$current]),
            compat_class => 'PostfixDerefExpr',
        );

        # Rewrap layers from inside out
        for my $wrapper (reverse @wrappers) {
            if ($wrapper->[0] eq 'Return') {
                # Restore the original control token saved during unwrap.
                $result = $factory->make_cfg('Return',
                    inputs => [$wrapper->[1], $result],
                );
            } elsif ($wrapper->[0] eq 'Unwind') {
                # Restore the control token saved during unwrap.
                my @args = ($wrapper->[2]->@*);
                $args[-1] = $result;
                $result = $factory->make_cfg('Unwind',
                    inputs => [$wrapper->[1], \@args],
                );
            } elsif ($wrapper->[0] eq 'BuiltinCall') {
                my @args = ($wrapper->[2]->@*);
                $args[-1] = $result;
                my $n = $wrapper->[1];
                $result = $typed->make('Call',
                    dispatch_kind => 'builtin',
                    name          => $n->value(),
                    inputs        => [$n, \@args],
                    compat_class  => 'BuiltinCall',
                );
            } elsif ($wrapper->[0] eq 'MethodCallExpr') {
                my $mn = $wrapper->[1];
                $result = $typed->make('Call',
                    dispatch_kind => 'method',
                    name          => $mn->value(),
                    inputs        => [$result, $mn, $wrapper->[2]],
                    compat_class  => 'MethodCallExpr',
                );
            }
        }

        return $result;
    }

    # Helper: push MethodCallExpr inward past prefix wrappers.
    # Same Earley stale-value merge issue as PostfixDeref: a MethodCall
    # can end up with a BuiltinCall or other prefix construct as its
    # invocant when the correct structure should have the prefix
    # wrapping the method call.
    #   MethodCall(BuiltinCall(push, [A, B]), m, [])
    #     → BuiltinCall(push, [A, MethodCall(B, m, [])])
    my sub _push_methodcall_inward($factory, $typed, $invocant, $method_name, $args) {
        my @wrappers;
        my $current = $invocant;
        while (defined $current && $current isa Chalk::IR::Node) {
            if ($current isa Chalk::IR::Node::Return) {
                # Save control token for re-wrapping later.
                push @wrappers, ['Return', $current->inputs()->[0]];
                $current = $current->inputs()->[1];  # value is inputs[1]
            } elsif ($current isa Chalk::IR::Node::Unwind) {
                # Save control token so it can be restored when re-wrapping.
                push @wrappers, ['Unwind', $current->inputs()->[0], $current->inputs()->[1]];
                my $die_args = $current->inputs()->[1];
                $current = $die_args->[-1];
            } elsif (_is_unwrappable_builtin($current)) {
                push @wrappers, ['BuiltinCall', $current->inputs()->[0], $current->inputs()->[1]];
                my $bi_args = $current->inputs()->[1];
                $current = $bi_args->[-1];
            } elsif ($current isa Chalk::IR::Node::PostfixDeref) {
                # PostfixDeref wrapping target — peel off and rewrap outside
                push @wrappers, ['PostfixDerefExpr', $current->inputs()->[1]];
                $current = $current->inputs()->[0];  # target
            } else {
                last;
            }
        }

        # No wrappers found — return plain MethodCallExpr
        unless (@wrappers) {
            return $typed->make('Call',
                dispatch_kind => 'method',
                name          => $method_name->value(),
                inputs        => [$invocant, $method_name, $args],
                compat_class  => 'MethodCallExpr',
            );
        }

        # Create method call at the innermost invocant
        my $result = $typed->make('Call',
            dispatch_kind => 'method',
            name          => $method_name->value(),
            inputs        => [$current, $method_name, $args],
            compat_class  => 'MethodCallExpr',
        );

        # Rewrap layers from inside out
        for my $wrapper (reverse @wrappers) {
            if ($wrapper->[0] eq 'Return') {
                # Restore the original control token saved during unwrap.
                $result = $factory->make_cfg('Return',
                    inputs => [$wrapper->[1], $result],
                );
            } elsif ($wrapper->[0] eq 'Unwind') {
                # Restore the control token saved during unwrap.
                my @die_args = ($wrapper->[2]->@*);
                $die_args[-1] = $result;
                $result = $factory->make_cfg('Unwind',
                    inputs => [$wrapper->[1], \@die_args],
                );
            } elsif ($wrapper->[0] eq 'BuiltinCall') {
                my @bi_args = ($wrapper->[2]->@*);
                $bi_args[-1] = $result;
                my $n = $wrapper->[1];
                $result = $typed->make('Call',
                    dispatch_kind => 'builtin',
                    name          => $n->value(),
                    inputs        => [$n, \@bi_args],
                    compat_class  => 'BuiltinCall',
                );
            } elsif ($wrapper->[0] eq 'PostfixDerefExpr') {
                my $s = $wrapper->[1];
                $result = $typed->make('PostfixDeref',
                    sigil        => (ref($s) ? $s->value() : $s),
                    inputs       => (ref($s) ? [$result, $s] : [$result]),
                    compat_class => 'PostfixDerefExpr',
                );
            }
        }

        return $result;
    }

    # Helpers for unwrapping Return/Unwind trapped inside expression nodes
    # by stale-value merge.  Declared here so they are visible to both
    # _fix_postfix_chain and $_unwrap_stmt_from_expr.
    my sub _stmt_inner($node) {
        if ($node isa Chalk::IR::Node::Return) {
            return ($node->inputs()->[1], $node->inputs()->[0]);  # value, control
        }
        # Unwind CFG node: control is inputs()->[0], exception args is inputs()->[1]
        return ($node->inputs()->[1], $node->inputs()->[0]);
    }

    my sub _is_stmt_node($node) {
        return $node isa Chalk::IR::Node::Return
            || $node isa Chalk::IR::Node::Unwind;
    }

    my sub _rewrap_stmt($factory, $stmt_node, $new_inner) {
        if ($stmt_node isa Chalk::IR::Node::Return) {
            my $ctrl = $stmt_node->inputs()->[0];
            return $factory->make_cfg('Return', inputs => [$ctrl, $new_inner]);
        }
        # Unwind: restore control token and update exception value.
        my $ctrl = $stmt_node->inputs()->[0];
        my $args = ref($new_inner) eq 'ARRAY' ? $new_inner : [$new_inner];
        return $factory->make_cfg('Unwind', inputs => [$ctrl, $args]);
    }

    # Post-process: fix misparented postfix chains in the IR tree.
    # The Earley parser's stale-value merge can produce
    # MethodCallExpr(PostfixDerefExpr(X, S), M, A) when the correct
    # structure is PostfixDerefExpr(MethodCallExpr(X, M, A), S).
    # This walks the tree and swaps any such misparentings.
    sub _fix_postfix_chain {
        my ($factory, $typed, $node) = @_;
        return $node unless defined $node;
        return $node unless $node isa Chalk::IR::Node;

        # Recursively fix inputs first (bottom-up)
        my @new_inputs;
        my $changed = false;
        for my $inp ($node->inputs()->@*) {
            if (ref($inp) eq 'ARRAY') {
                my @fixed;
                for my $elem ($inp->@*) {
                    my $f = _fix_postfix_chain($factory, $typed, $elem);
                    push @fixed, $f;
                    $changed = true if !defined $f || !defined $elem || $f != $elem;
                }
                push @new_inputs, \@fixed;
            } else {
                my $f = _fix_postfix_chain($factory, $typed, $inp);
                push @new_inputs, $f;
                $changed = true if !defined $f || !defined $inp
                    || (ref($f) && ref($inp) && $f != $inp);
            }
        }

        if ($changed) {
            # Rebuild the node with fixed inputs
            if ($node->class() eq 'MethodCallExpr') {
                $node = $typed->make('Call',
                    dispatch_kind => 'method',
                    name          => $new_inputs[1]->value(),
                    inputs        => [$new_inputs[0], $new_inputs[1], $new_inputs[2]],
                    compat_class  => 'MethodCallExpr',
                );
            } elsif ($node->class() eq 'PostfixDerefExpr') {
                my $sigil = $new_inputs[1];
                $node = $typed->make('PostfixDeref',
                    sigil        => (ref($sigil) ? $sigil->value() : $sigil),
                    inputs       => (ref($sigil) ? [$new_inputs[0], $sigil] : [$new_inputs[0]]),
                    compat_class => 'PostfixDerefExpr',
                );
            } elsif ($node->class() eq 'BuiltinCall') {
                $node = $typed->make('Call',
                    dispatch_kind => 'builtin',
                    name          => $new_inputs[0]->value(),
                    inputs        => [$new_inputs[0], $new_inputs[1]],
                    compat_class  => 'BuiltinCall',
                );
            } elsif ($node->class() eq 'SubscriptExpr') {
                $node = $typed->make('Subscript',
                    inputs       => [$new_inputs[0], $new_inputs[1], $new_inputs[2]],
                    compat_class => 'SubscriptExpr',
                );
            }
            # Other classes: leave unchanged (inputs are positional anyway)
        }

        # Fix the actual misparenting:
        # MethodCallExpr(PostfixDerefExpr(X, S), M, A)
        #   → PostfixDerefExpr(MethodCallExpr(X, M, A), S)
        if ($node->class() eq 'MethodCallExpr') {
            my $invocant = $node->inputs()->[0];
            if (defined $invocant
                    && $invocant isa Chalk::IR::Node::PostfixDeref) {
                my $inner_target = $invocant->inputs()->[0];
                my $sigil = $invocant->inputs()->[1];
                my $new_method = $typed->make('Call',
                    dispatch_kind => 'method',
                    name          => $node->inputs()->[1]->value(),
                    inputs        => [$inner_target, $node->inputs()->[1], $node->inputs()->[2]],
                    compat_class  => 'MethodCallExpr',
                );
                return $typed->make('PostfixDeref',
                    sigil        => (ref($sigil) ? $sigil->value() : $sigil),
                    inputs       => (ref($sigil) ? [$new_method, $sigil] : [$new_method]),
                    compat_class => 'PostfixDerefExpr',
                );
            }
        }

        # Fix prefix builtin subscript chain misparenting:
        # SubscriptExpr(BuiltinCall(defined/exists/ref/etc, [$var]), $key, style)
        #   → BuiltinCall(defined/exists/ref/etc, [SubscriptExpr($var, $key, style)])
        # Also handles Return/Unwind wrapper from stale-value merge:
        # SubscriptExpr(Return(ctrl, BuiltinCall(..., [$var])), $key, style)
        #   → Return(ctrl, BuiltinCall(..., [SubscriptExpr($var, $key, style)]))
        if ($node->class() eq 'SubscriptExpr') {
            my $target = $node->inputs()->[0];
            my $builtin_call;
            my $stmt_wrapper;  # Return or Unwind node if wrapped, undef if direct

            if (defined $target
                    && (($target isa Chalk::IR::Node::Call
                            && $target->dispatch_kind() eq 'builtin')
                        || _is_stmt_node($target))) {
                if ($target isa Chalk::IR::Node::Call
                        && $target->dispatch_kind() eq 'builtin') {
                    $builtin_call = $target;
                } elsif (_is_stmt_node($target)) {
                    my ($inner_val) = _stmt_inner($target);
                    if (defined $inner_val
                            && $inner_val isa Chalk::IR::Node::Call
                            && $inner_val->dispatch_kind() eq 'builtin') {
                        $builtin_call = $inner_val;
                        $stmt_wrapper = $target;
                    }
                }
            }

            if (defined $builtin_call) {
                my $bname = $builtin_call->inputs()->[0]->value();
                if ($PREFIX_BUILTINS{$bname}) {
                    my @args = $builtin_call->inputs()->[1]->@*;
                    my $inner_target = $args[-1];
                    $args[-1] = $typed->make('Subscript',
                        inputs       => [$inner_target, $node->inputs()->[1], $node->inputs()->[2]],
                        compat_class => 'SubscriptExpr',
                    );
                    my $new_builtin = $typed->make('Call',
                        dispatch_kind => 'builtin',
                        name          => $builtin_call->inputs()->[0]->value(),
                        inputs        => [$builtin_call->inputs()->[0], \@args],
                        compat_class  => 'BuiltinCall',
                    );
                    if (defined $stmt_wrapper) {
                        return _rewrap_stmt($factory, $stmt_wrapper, $new_builtin);
                    }
                    return $new_builtin;
                }
            }

            # Fix subscript chain wrapping UnaryExpr from stale-value merge:
            # SubscriptExpr(UnaryExpr(op, X), $key, style)
            # → UnaryExpr(op, SubscriptExpr(X, $key, style))
            # The subscript belongs on the operand, not wrapping the negation.
            if (defined $target
                    && $target isa Chalk::IR::Node::UnaryOp) {
                my $operand = $target->inputs()->[1];
                my $new_operand = $typed->make('Subscript',
                    inputs       => [$operand, $node->inputs()->[1], $node->inputs()->[2]],
                    compat_class => 'SubscriptExpr',
                );
                # Re-run fix to push deeper if needed
                $new_operand = _fix_postfix_chain($factory, $typed, $new_operand);
                my $unop_type = ref($target) =~ s/^Chalk::IR::Node:://r;
                return $typed->make($unop_type,
                    inputs       => [$target->inputs()->[0], $new_operand],
                    operand      => $new_operand,
                    compat_class => 'UnaryExpr',
                );
            }

            # Fix subscript chain wrapping BinaryExpr from stale-value merge:
            # SubscriptExpr(BinaryExpr(op, L, R), $key, style)
            # → BinaryExpr(op, L, SubscriptExpr(R, $key, style))
            # Stale-value merge wraps the entire expression in a SubscriptExpr
            # from the assignment target. The subscript belongs on the right
            # operand (the one that lost its subscript during merge).
            # Handles both logical (||, &&) and comparison (<, >, etc.) ops
            # since SubscriptExpr wrapping any BinaryExpr is always corruption.
            if (defined $target
                    && $target isa Chalk::IR::Node::BinOp) {
                my $right = $target->inputs()->[2];
                my $new_right = $typed->make('Subscript',
                    inputs       => [$right, $node->inputs()->[1], $node->inputs()->[2]],
                    compat_class => 'SubscriptExpr',
                );
                # Re-run fix on the new SubscriptExpr to push deeper if needed
                $new_right = _fix_postfix_chain($factory, $typed, $new_right);
                my $binop_type = ref($target) =~ s/^Chalk::IR::Node:://r;
                return $typed->make($binop_type,
                    inputs       => [$target->inputs()->[0], $target->inputs()->[1], $new_right],
                    left         => $target->inputs()->[1],
                    right        => $new_right,
                    compat_class => 'BinaryExpr',
                );
            }
        }

        return $node;
    }

    # Recursively apply _fix_postfix_chain to all nodes in a tree.
    # Unlike _fix_postfix_chain (which only transforms the top node),
    # this walks into BinaryExpr/UnaryExpr/BuiltinCall children so that
    # inner SubscriptExpr corruption gets fixed too.
    my $_fix_postfix_chain_deep;
    $_fix_postfix_chain_deep = sub($f, $t, $node) {
        return $node unless defined $node;
        return $node unless $node isa Chalk::IR::Node;

        # First, apply the top-level fix
        my $fixed = _fix_postfix_chain($f, $t, $node);

        # If the top-level fix changed the node, recurse on the result
        return $_fix_postfix_chain_deep->($f, $t, $fixed)
            if refaddr($fixed) != refaddr($node);

        # Otherwise, recurse into children
        my $class = $node->class();
        if ($class eq 'BinaryExpr') {
            my $orig_left  = $node->inputs()->[1];
            my $orig_right = $node->inputs()->[2];
            my $left  = $_fix_postfix_chain_deep->($f, $t, $orig_left);
            my $right = $_fix_postfix_chain_deep->($f, $t, $orig_right);
            if ((defined $left && defined $orig_left && refaddr($left) != refaddr($orig_left))
                || (defined $right && defined $orig_right && refaddr($right) != refaddr($orig_right))) {
                my $op_str = $node->inputs()->[0]->value();
                my $binop_type = $BINOP_MAP{$op_str} // die "Unknown binary op: $op_str";
                return $t->make($binop_type,
                    inputs       => [$node->inputs()->[0], $left, $right],
                    left         => $left,
                    right        => $right,
                    compat_class => 'BinaryExpr',
                );
            }
        } elsif ($class eq 'UnaryExpr') {
            my $operand = $_fix_postfix_chain_deep->($f, $t, $node->inputs()->[1]);
            if (refaddr($operand) != refaddr($node->inputs()->[1])) {
                my $uop_str = $node->inputs()->[0]->value();
                my $unop_type = $UNOP_MAP{$uop_str} // die "Unknown unary op: $uop_str";
                return $t->make($unop_type,
                    inputs       => [$node->inputs()->[0], $operand],
                    operand      => $operand,
                    compat_class => 'UnaryExpr',
                );
            }
        } elsif ($class eq 'BuiltinCall') {
            my @args = $node->inputs()->[1]->@*;
            my $changed = false;
            for my $i (0 .. $#args) {
                my $fixed_arg = $_fix_postfix_chain_deep->($f, $t, $args[$i]);
                if (refaddr($fixed_arg) != refaddr($args[$i])) {
                    $args[$i] = $fixed_arg;
                    $changed = true;
                }
            }
            if ($changed) {
                return $t->make('Call',
                    dispatch_kind => 'builtin',
                    name          => $node->inputs()->[0]->value(),
                    inputs        => [$node->inputs()->[0], \@args],
                    compat_class  => 'BuiltinCall',
                );
            }
        }

        return $node;
    };

    # (helpers moved before _fix_postfix_chain for lexical visibility)

    my $_unwrap_stmt_from_expr;
    $_unwrap_stmt_from_expr = sub ($factory, $typed, $node) {
        return $node unless $node isa Chalk::IR::Node;
        my $class = $node->class();

        if ($class eq 'BinaryExpr') {
            # Recurse into left child first to handle nested cases like
            # BinaryExpr(|, BinaryExpr(&, Return(ctrl,X), Y), Z)
            my $left = $_unwrap_stmt_from_expr->($factory, $typed, $node->inputs()->[1]);
            if (_is_stmt_node($left)) {
                my ($inner_val) = _stmt_inner($left);
                my $op_str     = $node->inputs()->[0]->value();
                my $binop_type = $BINOP_MAP{$op_str} // die "Unknown binary op: $op_str";
                my $new_expr   = $typed->make($binop_type,
                    inputs       => [$node->inputs()->[0], $inner_val, $node->inputs()->[2]],
                    left         => $inner_val,
                    right        => $node->inputs()->[2],
                    compat_class => 'BinaryExpr',
                );
                return _rewrap_stmt($factory, $left, $new_expr);
            }
            # Left was recursively fixed but isn't a stmt — rebuild if changed
            if (refaddr($left) != refaddr($node->inputs()->[1])) {
                my $op_str     = $node->inputs()->[0]->value();
                my $binop_type = $BINOP_MAP{$op_str} // die "Unknown binary op: $op_str";
                return $typed->make($binop_type,
                    inputs       => [$node->inputs()->[0], $left, $node->inputs()->[2]],
                    left         => $left,
                    right        => $node->inputs()->[2],
                    compat_class => 'BinaryExpr',
                );
            }
        }

        if ($class eq 'SubscriptExpr') {
            my $base = $node->inputs()->[0];
            if (_is_stmt_node($base)) {
                my ($inner_val) = _stmt_inner($base);
                my $new_expr = $typed->make('Subscript',
                    inputs       => [$inner_val, $node->inputs()->[1], $node->inputs()->[2]],
                    compat_class => 'SubscriptExpr',
                );
                return _rewrap_stmt($factory, $base, $new_expr);
            }
        }

        if ($class eq 'PostfixDerefExpr') {
            my $base = $node->inputs()->[0];
            if (_is_stmt_node($base)) {
                my ($inner_val) = _stmt_inner($base);
                my $sigil_param = $node->inputs()->[1];
                my $is_node     = ref($sigil_param) ? 1 : 0;
                my $sigil_str   = $is_node ? $sigil_param->value() : $sigil_param;
                my @inputs      = $is_node ? ($inner_val, $sigil_param) : ($inner_val);
                my $new_expr    = $typed->make('PostfixDeref',
                    sigil        => $sigil_str,
                    inputs       => \@inputs,
                    compat_class => 'PostfixDerefExpr',
                );
                return _rewrap_stmt($factory, $base, $new_expr);
            }
        }

        if ($node isa Chalk::IR::Node::TernaryExpr || $class eq 'TernaryExpr') {
            my $cond = $node->inputs()->[0];
            if (_is_stmt_node($cond)) {
                my ($inner_val) = _stmt_inner($cond);
                my $new_expr = $typed->make('TernaryExpr',
                    inputs       => [$inner_val, $node->inputs()->[1], $node->inputs()->[2]],
                    compat_class => 'TernaryExpr',
                );
                return _rewrap_stmt($factory, $cond, $new_expr);
            }
        }

        if ($class eq 'MethodCallExpr') {
            my $invocant = $node->inputs()->[0];
            if (_is_stmt_node($invocant)) {
                my ($inner_val) = _stmt_inner($invocant);
                my $new_expr = $typed->make('Call',
                    dispatch_kind => 'method',
                    name          => $node->inputs()->[1]->value(),
                    inputs        => [$inner_val, $node->inputs()->[1], $node->inputs()->[2]],
                    compat_class  => 'MethodCallExpr',
                );
                return _rewrap_stmt($factory, $invocant, $new_expr);
            }
        }

        return $node;
    };

    # Post-process statement list to fix grammar ambiguity artifacts.
    # The ambiguous grammar sometimes parses compound statements as
    # separate items. These fixups merge them back together:
    # - `return 'Start'` → Return(ctrl, Constant('Start'))
    # - `die "message"` → Unwind(ctrl, Constant('message'))
    # - `use Foo 'bar'` (split) → UseDecl(Foo, ['bar'])
    my sub _fixup_stmts($factory, $typed, $stmts) {
        my @result;
        my $i = 0;
        while ($i <= $#$stmts) {
            my $item = $stmts->[$i];
            if ($item isa Chalk::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'return'
                    && $i + 1 <= $#$stmts) {
                # Merge return + value into a Return CFG node.
                # No cfg_state is available here (fixup runs post-parse),
                # so a fresh Start node serves as the control token.
                $i++;
                my $value = $stmts->[$i];
                push @result, $factory->make_cfg('Return',
                    inputs => [$factory->make('Start'), $value],
                );
            } elsif ($item isa Chalk::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'return') {
                # Bare return; with no following value — emit Return CFG node.
                push @result, $factory->make_cfg('Return',
                    inputs => [$factory->make('Start'), _make_const($factory, 'undef')],
                );
            } elsif ($item isa Chalk::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'die'
                    && $i + 1 <= $#$stmts) {
                # Merge die + single argument into an Unwind CFG node.
                # No cfg_state is available here (fixup runs post-parse),
                # so a fresh Start node serves as the control token.
                # Consumes only one following node to avoid absorbing
                # unrelated statements in multi-statement bodies.
                # inputs->[1] is an arrayref of exception args.
                $i++;
                push @result, $factory->make_cfg('Unwind',
                    inputs => [$factory->make('Start'), [$stmts->[$i]]],
                );
            } elsif ($item isa Chalk::IR::UseInfo
                    && !scalar($item->args()->@*)
                    && $i + 1 <= $#$stmts
                    && $stmts->[$i + 1] isa Chalk::IR::Node::Constant) {
                # Merge UseInfo(module, []) + bare Constant into
                # UseInfo(module, [Constant]). Grammar ambiguity sometimes
                # splits `use Foo 'bar'` into separate statements.
                my @import_args;
                while ($i + 1 <= $#$stmts
                        && $stmts->[$i + 1] isa Chalk::IR::Node::Constant
                        && !($stmts->[$i + 1]->value() =~ /^[a-zA-Z_]/
                             && $i + 2 <= $#$stmts)) {
                    $i++;
                    push @import_args, $stmts->[$i];
                }
                if (@import_args) {
                    push @result, Chalk::IR::UseInfo->new(
                        name => $item->name(),
                        args => \@import_args,
                    );
                } else {
                    push @result, $item;
                }
            } elsif ($item isa Chalk::IR::Node::BinOp
                    && $item->inputs()->[0]->value() eq '='
                    && $item->inputs()->[1] isa Chalk::IR::Node::VarDecl
                    && !defined $item->inputs()->[1]->inputs()->[1]) {
                # Merge BinaryExpr(=, VarDecl(var, undef), expr) → VarDecl(var, expr)
                my $var_decl = $item->inputs()->[1];
                push @result, $typed->make('VarDecl',
                    inputs      => [$var_decl->inputs()->[0], $item->inputs()->[2]],
                    compat_class => 'VarDecl',
                );
            } elsif ($item isa Chalk::IR::Node::BinOp
                    && $item->inputs()->[1] isa Chalk::IR::Node::Call
                    && $item->inputs()->[1]->dispatch_kind() eq 'builtin'
                    && $LIST_BUILTINS{$item->inputs()->[1]->inputs()->[0]->value()}) {
                # Restructure BinaryExpr(op, BuiltinCall(name, [..., last]), right)
                # into BuiltinCall(name, [..., BinaryExpr(op, last, right)])
                # Fixes grammar ambiguity where `push @arr, EXPR . EXPR` is
                # parsed as BinaryExpr(".", push(@arr, EXPR), EXPR) instead of
                # push(@arr, BinaryExpr(".", EXPR, EXPR))
                my $binop = $item->inputs()->[0];
                my $builtin = $item->inputs()->[1];
                my $right = $item->inputs()->[2];
                my $name = $builtin->inputs()->[0];
                my @args = $builtin->inputs()->[1]->@*;
                my $last_arg = pop @args;
                my $op_str = $binop->value();
                my $binop_type = $BINOP_MAP{$op_str} // die "Unknown binary op: $op_str";
                my $new_last = $typed->make($binop_type,
                    inputs       => [$binop, $last_arg, $right],
                    left         => $last_arg,
                    right        => $right,
                    compat_class => 'BinaryExpr',
                );
                push @args, $new_last;
                push @result, $typed->make('Call',
                    dispatch_kind => 'builtin',
                    name          => $name->value(),
                    inputs        => [$name, \@args],
                    compat_class  => 'BuiltinCall',
                );
            } elsif ($item isa Chalk::IR::Node::VarDecl
                    && !defined $item->inputs()->[1]
                    && $i + 1 <= $#$stmts
                    && $stmts->[$i + 1] isa Chalk::IR::Node) {
                # Merge bare VarDecl(var, undef) + following expression → VarDecl(var, expr)
                # Only merge when the next item is actually an initializer, not a
                # separate statement. Block merge for known statement-starting patterns.
                my $next = $stmts->[$i + 1];
                my $is_boundary = false;
                # Statement-level boundary: metadata structs and Return/Unwind CFG nodes
                $is_boundary = true if $next isa Chalk::IR::Node::Return
                    || $next isa Chalk::IR::Node::Unwind;
                # ClassInfo/FieldInfo/MethodInfo/SubInfo metadata structs are always separate statements
                $is_boundary = true if $next isa Chalk::IR::ClassInfo;
                $is_boundary = true if $next isa Chalk::IR::FieldInfo;
                $is_boundary = true if $next isa Chalk::IR::MethodInfo;
                $is_boundary = true if $next isa Chalk::IR::SubInfo;
                # CFG control flow nodes (both Bootstrap and new Chalk::IR hierarchies)
                $is_boundary = true if ($next isa Chalk::IR::Node
                        || $next isa Chalk::IR::Node)
                    && $STMT_BOUNDARY_OPS{$next->operation() // ''};
                # Bare keyword Constants (push, return, die, for, etc.)
                $is_boundary = true if $next isa Chalk::IR::Node::Constant
                    && defined $next->value()
                    && ($STOP_KEYWORDS{$next->value()}
                        || $LIST_BUILTINS{$next->value()}
                        || $PREFIX_BUILTINS{$next->value()});
                # MethodCallExpr and BuiltinCall are always separate statements
                $is_boundary = true if $next isa Chalk::IR::Node::Call
                    && ($next->dispatch_kind() eq 'method'
                        || $next->dispatch_kind() eq 'builtin');
                if (!$is_boundary) {
                    $i++;
                    push @result, $typed->make('VarDecl',
                        inputs       => [$item->inputs()->[0], $next],
                        compat_class => 'VarDecl',
                    );
                } else {
                    push @result, $item;
                }
            } elsif ($item isa Chalk::IR::Node::Constant
                    && defined $item->value()
                    && $LIST_BUILTINS{$item->value()}
                    && $i + 1 <= $#$stmts) {
                # Merge bare builtin keyword + following args → BuiltinCall
                my $builtin = $item->value();
                my @args;
                while ($i + 1 <= $#$stmts) {
                    my $next = $stmts->[$i + 1];
                    # Stop at statement-level constructs (Return/Unwind CFG nodes)
                    last if $next isa Chalk::IR::Node::Return
                        || $next isa Chalk::IR::Node::Unwind;
                    # ClassInfo/FieldInfo/MethodInfo/SubInfo metadata structs are always separate statements
                    last if $next isa Chalk::IR::ClassInfo;
                    last if $next isa Chalk::IR::FieldInfo;
                    last if $next isa Chalk::IR::MethodInfo;
                    last if $next isa Chalk::IR::SubInfo;
                    # Stop at CFG control flow nodes (both Bootstrap and new Chalk::IR hierarchies)
                    last if ($next isa Chalk::IR::Node
                            || $next isa Chalk::IR::Node)
                        && $STMT_BOUNDARY_OPS{$next->operation() // ''};
                    # Stop at other bare builtins
                    last if $next isa Chalk::IR::Node::Constant
                        && defined $next->value()
                        && $STOP_KEYWORDS{$next->value()};
                    # Nest PREFIX_BUILTIN inside LIST_BUILTIN: sort keys %$h → sort(keys(%$h))
                    if ($next isa Chalk::IR::Node::Constant
                            && defined $next->value()
                            && $PREFIX_BUILTINS{$next->value()}
                            && $i + 2 <= $#$stmts) {
                        my $prefix_name = $next->value();
                        $i += 2;
                        my $prefix_arg = $stmts->[$i];
                        my $prefix_name_node = _make_const($factory, $prefix_name);
                        push @args, $typed->make('Call',
                            dispatch_kind => 'builtin',
                            name          => $prefix_name,
                            inputs        => [$prefix_name_node, [$prefix_arg]],
                            compat_class  => 'BuiltinCall',
                        );
                        next;
                    }
                    $i++;
                    push @args, $next;
                }
                my $builtin_name_node = _make_const($factory, $builtin);
                push @result, $typed->make('Call',
                    dispatch_kind => 'builtin',
                    name          => $builtin,
                    inputs        => [$builtin_name_node, \@args],
                    compat_class  => 'BuiltinCall',
                );
            } elsif ($item isa Chalk::IR::Node::Constant
                    && defined $item->value()
                    && $PREFIX_BUILTINS{$item->value()}
                    && $i + 1 <= $#$stmts) {
                # Merge bare prefix-builtin + following expression → BuiltinCall
                my $builtin = $item->value();
                $i++;
                my $arg = $stmts->[$i];
                my $builtin_name_node = _make_const($factory, $builtin);
                push @result, $typed->make('Call',
                    dispatch_kind => 'builtin',
                    name          => $builtin,
                    inputs        => [$builtin_name_node, [$arg]],
                    compat_class  => 'BuiltinCall',
                );
            } else {
                push @result, $_unwrap_stmt_from_expr->($factory, $typed, $item);
            }
            $i++;
        }
        return \@result;
    }

    # §2 Program ::= _ StatementList? _
    # Collects all statement-level IR nodes into Chalk::IR::Program.
    # Loop-carried Phi nodes are created eagerly in ForeachStatement,
    # WhileStatement, and ExpressionStatement (postfix loops) — not here.
    method Program($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                # StatementList returns arrayref
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::IR::Node
                     || $val isa Chalk::IR::UseInfo
                     || $val isa Chalk::IR::ClassInfo
                     || $val isa Chalk::IR::FieldInfo
                     || $val isa Chalk::IR::MethodInfo
                     || $val isa Chalk::IR::SubInfo) {
                push @stmts, $val;
            }
        }
        # Fix misparented postfix chains from Earley stale-value merge.
        # Only IR nodes (with inputs()) need this — metadata structs skip it.
        @stmts = map {
            ($_ isa Chalk::IR::Node)
                ? _fix_postfix_chain($factory, $typed, $_)
                : $_
        } @stmts;

        # Partition statements into Program metadata categories
        my @use_decls;
        my @classes;
        my @top_level_subs;
        my @other_stmts;

        for my $stmt (@stmts) {
            if ($stmt isa Chalk::IR::UseInfo) {
                push @use_decls, $stmt;
            } elsif ($stmt isa Chalk::IR::ClassInfo) {
                push @classes, $stmt;
            } elsif ($stmt isa Chalk::IR::SubInfo) {
                push @top_level_subs, $stmt;
            } else {
                # Bare computation nodes — present in test snippets and
                # expression-only programs; empty for well-formed .pm files.
                push @other_stmts, $stmt;
            }
        }

        return Chalk::IR::Program->new(
            use_decls      => \@use_decls,
            classes        => \@classes,
            top_level_subs => \@top_level_subs,
            other_stmts    => \@other_stmts,
        );
    }

    # §2 StatementList ::= StatementItem | StatementList _ StatementItem
    # Collects all statement IR nodes into an arrayref
    method StatementList($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                # Nested StatementList result — flatten
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::IR::Node
                     || $val isa Chalk::IR::UseInfo
                     || $val isa Chalk::IR::ClassInfo
                     || $val isa Chalk::IR::FieldInfo
                     || $val isa Chalk::IR::MethodInfo
                     || $val isa Chalk::IR::SubInfo) {
                push @stmts, $val;
            }
        }
        my $fixed = _fixup_stmts($factory, $typed, \@stmts);
        # Fix misparented postfix chains from Earley stale-value merge
        return [ map { _fix_postfix_chain($factory, $typed, $_) } $fixed->@* ];
    }

    # §2 StatementItem — collect all IR values for fixup in StatementList/Block
    method StatementItem($ctx) {
        my @values = _collect_ir_values($ctx);
        my @ir_nodes;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node
                    || $val isa Chalk::IR::UseInfo
                    || $val isa Chalk::IR::ClassInfo
                    || $val isa Chalk::IR::FieldInfo
                    || $val isa Chalk::IR::MethodInfo
                    || $val isa Chalk::IR::SubInfo) {
                push @ir_nodes, $val;
            }
        }
        # Single value — return directly
        return $ir_nodes[0] if @ir_nodes == 1;
        # Multiple values — return as arrayref for StatementList to flatten
        return \@ir_nodes if @ir_nodes > 1;
        return undef;
    }

    # §3 SimpleStatement — transparent pass-through
    # §3 ReturnStatement ::= /return\b/ WS Expression | /return\b/
    method ReturnStatement($ctx) {
        my @values = _collect_ir_values($ctx);
        # First IR value is the return expression (if present).
        # Skip the bare 'return' keyword Constant — take the first non-keyword node.
        my $value;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node
                    && !($val isa Chalk::IR::Node::Constant
                         && defined $val->value()
                         && $val->value() eq 'return')) {
                $value = $val;
                last;
            }
        }
        # Retrieve the current control token from cfg_state for CFG edge.
        # Fall back to a fresh Start node when no cfg_state is available
        # (e.g., in tests or early-parse contexts without scope tracking).
        my $control;
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            $control = $state->{control} if defined $state;
        }
        $control //= $factory->make('Start');
        return $factory->make_cfg('Return',
            inputs => [$control, $value // _make_const($factory, 'undef')],
        );
    }

    method SimpleStatement($ctx) {
        my @values = _collect_ir_values($ctx);
        my @ir_nodes;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node
                    || $val isa Chalk::IR::UseInfo
                    || $val isa Chalk::IR::MethodInfo
                    || $val isa Chalk::IR::SubInfo) {
                push @ir_nodes, $val;
            }
        }
        return $ir_nodes[0] if @ir_nodes == 1;
        return \@ir_nodes if @ir_nodes > 1;
        return undef;
    }

    # §3 CompoundStatement — transparent pass-through
    method CompoundStatement($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::IR::Node;
        }
        return undef;
    }

    # §4 ExpressionStatement — transparent pass-through
    # For postfix modifier alt (Expression WS PostfixModifier), wires the
    # expression into the PostfixModifier's cfg_state body_stmts so codegen
    # emits the body inside the control flow construct.
    method ExpressionStatement($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my @ir_nodes;
        my $postfix_leaf;
        my $body_expr;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule() // '';
            if ($focus isa Chalk::IR::Node) {
                push @ir_nodes, $focus;
                if ($rule eq 'PostfixModifier') {
                    $postfix_leaf = $leaf;
                } elsif (!defined $postfix_leaf) {
                    # Expression before PostfixModifier is the body
                    $body_expr = $focus;
                }
            }
        }

        # Wire body expression into PostfixModifier's cfg_state.
        # The cfg_state is propagated to $ctx via multiply() during Earley processing,
        # so cfg_state($ctx) returns the PostfixModifier's state directly.
        if (defined $postfix_leaf && defined $body_expr) {
            my $postfix_node = $postfix_leaf->extract();
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            if (defined $sa) {
                my $state = $sa->cfg_state($ctx);
                if (defined $state && (defined $state->{loop} || defined $state->{if_node})) {
                    my $updated = { $state->%* };
                    if (defined $updated->{loop}) {
                        $updated->{body_stmts} = [$body_expr];

                        # Collect post-body scope bindings for Phi backedge wiring.
                        # Walk leaves of this context to find any scope updates
                        # that occurred while parsing the body expression.
                        my $loop = $updated->{loop};
                        my %body_final_bindings;
                        for my $leaf (_collect_ir_leaves($ctx)) {
                            my $leaf_state = $sa->cfg_state($leaf);
                            if (defined $leaf_state && defined $leaf_state->{scope}) {
                                for my $name ($leaf_state->{scope}->variable_names()) {
                                    my $binding = $leaf_state->{scope}->lookup($name);
                                    $body_final_bindings{$name} = $binding if defined $binding;
                                }
                            }
                        }

                        # Create Phi nodes for loop-carried variables directly here.
                        # Postfix loops have no iterator variable, so pass undef.
                        if (defined $updated->{scope}) {
                            $updated->{scope} = $updated->{scope}->merge_for_loop(
                                \%body_final_bindings, $loop, $factory, undef,
                            );
                        }
                    } elsif (defined $updated->{if_node}) {
                        # Detect loop jump keywords (next/last) as body:
                        # set loop_jump marker instead of then_stmts so
                        # targets emit 'next if/unless' instead of 'if { next }'.
                        # NOTE: The If CFG node lives in cfg_state metadata
                        # (keyed by the IR node's refaddr), not directly in
                        # body_stmts. _build_cfg_lookup resolves this at codegen
                        # time. Future GCM/DCE passes that walk only the IR tree
                        # (not cfg_state) will need to be extended to see it.
                        if ($body_expr isa Chalk::IR::Node::Constant
                                && defined $body_expr->value()
                                && ($body_expr->value() eq 'next'
                                    || $body_expr->value() eq 'last')) {
                            $updated->{loop_jump} = $body_expr->value();
                        } else {
                            $updated->{then_stmts} = [$body_expr];
                        }
                    }
                    $sa->update_cfg($updated);
                }
            }
            return $postfix_node;
        }

        return $ir_nodes[0] if @ir_nodes == 1;
        return \@ir_nodes if @ir_nodes > 1;
        return undef;
    }

    # §7 UseDeclaration ::= /(?:use|no)\b/ WS ModuleName
    #                      | /(?:use|no)\b/ WS ModuleName WS ImportList
    method UseDeclaration($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $module_name;
        my $import_args;
        my $keyword = 'use';

        # Extract keyword from the scanned text (first word is 'use' or 'no')
        my $text = $ctx->scanned_text();
        if ($text =~ /^\s*no\b/) {
            $keyword = 'no';
        }

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (defined $rule && $rule eq 'ModuleName'
                    && $focus isa Chalk::IR::Node::Constant) {
                $module_name = $focus;
            } elsif (defined $rule && $rule eq 'ImportList'
                    && ref($focus) eq 'ARRAY') {
                $import_args = $focus;
            }
        }

        # If no module name found from ModuleName rule, look for any Constant
        if (!defined $module_name) {
            $module_name = _find_constant($ctx);
        }

        my $name_str = defined $module_name ? $module_name->value() : '';
        return Chalk::IR::UseInfo->new(
            name    => $name_str,
            args    => $import_args // [],
            keyword => $keyword,
        );
    }

    # §7 ModuleName ::= QualifiedIdentifier | Version | QualifiedIdentifier WS Version
    # Returns a Constant with the module name
    method ModuleName($ctx) {
        # Collect all text from scanned terminals
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §7 ImportList ::= ExpressionList
    # Returns arrayref of Constant nodes for import arguments
    method ImportList($ctx) {
        my @values = _collect_ir_values($ctx);
        my @imports;
        for my $val (@values) {
            if (ref($val) eq 'ARRAY') {
                push @imports, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @imports, $val;
            }
        }
        return \@imports;
    }

    # §9 ClassBlock ::= /class\b/ WS QualifiedIdentifier AttributeList? _ Block
    method ClassBlock($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $class_name;
        my $parent;
        my @body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if ($focus isa Chalk::IR::Node::Constant) {
                if (!defined $class_name) {
                    # First Constant is the class name (from QualifiedIdentifier)
                    $class_name = $focus;
                }
            } elsif (ref($focus) eq 'ARRAY') {
                # Body statements from Block or parent info from AttributeList
                if (defined $rule && $rule eq 'AttributeList') {
                    # AttributeList returns arrayref of attribute data
                    # Look for :isa(Parent) → parent name Constant
                    for my $attr ($focus->@*) {
                        if (ref($attr) eq 'HASH') {
                            if (defined $attr->{name} && $attr->{name} eq 'isa'
                                    && defined $attr->{value}) {
                                $parent = $factory->make('Constant',
                                    const_type => 'identifier',
                                    value      => $attr->{value},
                                );
                            }
                        }
                    }
                } elsif (defined $rule && $rule eq 'Block') {
                    # Block returns arrayref of body statements
                    @body = $focus->@*;
                } else {
                    # Fallback: use as body
                    @body = $focus->@*;
                }
            }
        }

        my $name_str   = defined $class_name ? $class_name->value() : '<unknown>';
        my $parent_str = defined $parent     ? $parent->value()     : undef;

        # Partition body items by type for structured access.
        # The body array preserves declaration order for ordered iteration.
        my @fields;
        my @methods;
        my @subs;
        for my $item (@body) {
            if ($item isa Chalk::IR::FieldInfo) {
                push @fields, $item;
            } elsif ($item isa Chalk::IR::MethodInfo) {
                push @methods, $item;
            } elsif ($item isa Chalk::IR::SubInfo) {
                push @subs, $item;
            }
        }

        return Chalk::IR::ClassInfo->new(
            name    => $name_str,
            parent  => $parent_str,
            fields  => \@fields,
            methods => \@methods,
            subs    => \@subs,
            body    => \@body,
        );
    }

    # §9 MethodDefinition ::= /method\b/ WS QualifiedIdentifier AttributeList? _ Signature? _ Block
    method MethodDefinition($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $method_name;
        my @params;
        my @body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if ($focus isa Chalk::IR::Node::Constant
                    && !defined $method_name) {
                $method_name = $focus;
            } elsif (ref($focus) eq 'ARRAY') {
                if (defined $rule && ($rule eq 'Signature'
                        || $rule eq 'SignatureParams')) {
                    @params = $focus->@*;
                } elsif (defined $rule && $rule eq 'Block') {
                    @body = $focus->@*;
                } else {
                    # Ambiguous: if we haven't seen params yet and items look
                    # like param names, treat as params. Otherwise body.
                    if (!@body) {
                        @body = $focus->@*;
                    }
                }
            }
        }

        # TypeInference is the sole authority for method return types.
        # TI's body analysis produces rich types (Int, Str, Bool, etc.)
        # via TypeInferenceActions::MethodDefinition which sets
        # method_return_type in the TI focus hash.
        my $method_name_str = defined $method_name ? $method_name->value() : '<unknown>';
        my $ti_ctx = Chalk::Bootstrap::Semiring::SemanticAction::current_type_context();
        die "MethodDefinition: TI context unavailable for '$method_name_str'"
            unless defined $ti_ctx;
        my $ti_focus = $ti_ctx->extract();
        die "MethodDefinition: TI focus missing for '$method_name_str'"
            unless defined $ti_focus && ref($ti_focus) eq 'HASH';

        my $return_type;
        if (defined $ti_focus->{method_return_type}) {
            $return_type = $ti_focus->{method_return_type};
        } else {
            $return_type = 'Void';
        }

        # Fix stale-value merge artifacts in method body (return/die inside
        # expression wrappers, prefix builtin subscript chains, etc.)
        # Use _deep variant to reach nested expressions (e.g., if-conditions).
        @body = map { $_fix_postfix_chain_deep->($factory, $typed, $_) } @body;
        my $fixed_body = _fixup_stmts($factory, $typed, \@body);

        my $method_name_val = defined $method_name ? $method_name->value() : '<unknown>';
        my @param_strs = map { $_->value() } @params;

        my $graph = $self->_build_method_graph($ctx, $fixed_body);

        return Chalk::IR::MethodInfo->new(
            name        => $method_name_val,
            params      => \@param_strs,
            return_type => $return_type,
            body        => $fixed_body,
            graph       => $graph,
        );
    }

    # Detect stale-merge artifact: `return unless COND` mis-parsed as
    # Return(ctrl, value: ...BuiltinCall("unless",...)).
    # Walks the value tree looking for a BuiltinCall node whose name is
    # a postfix modifier keyword (unless/if/while/until/for/foreach).
    method _is_postfix_modifier_artifact($node, $keywords) {
        my @stack = ($node);
        while (@stack) {
            my $n = pop @stack;
            next unless defined $n;
            next unless $n isa Chalk::IR::Node;
            if ($n isa Chalk::IR::Node::Call && $n->dispatch_kind() eq 'builtin') {
                my $name_node = $n->inputs()->[0];
                if (defined $name_node
                        && $name_node isa Chalk::IR::Node::Constant
                        && $keywords->{$name_node->value()}) {
                    return true;
                }
            }
            for my $input ($n->inputs()->@*) {
                if (ref($input) eq 'ARRAY') {
                    push @stack, $input->@*;
                } else {
                    push @stack, $input;
                }
            }
        }
        return false;
    }

    # §9 SubroutineDefinition — compile sub declarations into SubInfo structs.
    # Grammar: /sub\b/ WS QualifiedIdentifier _ Signature? _ Block
    #        | /(?:my|our|state)\b/ WS /sub\b/ WS QualifiedIdentifier _ Signature? _ Block
    # Produces SubInfo with name, params (plain strings), body, and scope.
    # Also records the scope (bare = package, my/our/state = lexical).
    method SubroutineDefinition($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $sub_name;
        my @params;
        my @body;
        my $scope = 'package';  # default for bare `sub`

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            # Plain string from regex scan (e.g., /(?:my|our|state)\b/ or /sub\b/)
            if (!ref($focus) && defined $focus && !defined $sub_name) {
                if ($focus =~ /^(?:my|our|state)$/) {
                    $scope = $focus;
                    next;
                }
                next if $focus eq 'sub';
            }

            if ($focus isa Chalk::IR::Node::Constant
                    && !defined $sub_name) {
                my $val = $focus->value();
                # Check for lexical scope prefix (my/our/state)
                if ($val =~ /^(?:my|our|state)$/) {
                    $scope = $val;
                    next;
                }
                # Skip the 'sub' keyword itself
                next if $val eq 'sub';
                $sub_name = $focus;
            } elsif (ref($focus) eq 'ARRAY') {
                if (defined $rule && ($rule eq 'Signature'
                        || $rule eq 'SignatureParams')) {
                    @params = $focus->@*;
                } elsif (defined $rule && $rule eq 'Block') {
                    @body = $focus->@*;
                } else {
                    if (!@body) {
                        @body = $focus->@*;
                    }
                }
            }
        }

        # If we couldn't find the sub name, skip this node
        return unless defined $sub_name;

        # Fix stale-value merge artifacts in sub body
        @body = map { $_fix_postfix_chain_deep->($factory, $typed, $_) } @body;
        my $fixed_body = _fixup_stmts($factory, $typed, \@body);

        my $sub_name_val = $sub_name->value();
        my @param_strs = map { $_->value() } @params;

        my $graph = $self->_build_method_graph($ctx, $fixed_body);

        return Chalk::IR::SubInfo->new(
            name   => $sub_name_val,
            params => \@param_strs,
            body   => $fixed_body,
            scope  => $scope,
            graph  => $graph,
        );
    }

    # Build a per-method/sub Graph from Context tree and body statements.
    # Walks the Context subtree to collect cfg_state entries that carry
    # control-flow information (if_node, loop, try_node). Maps each
    # associated IR node's refaddr to the cfg_state hashref.
    # Also collects Return/Unwind nodes from the fixed body as graph exits.
    # Returns a Chalk::IR::Graph with start, returns, and schedule.
    method _build_method_graph($ctx, $fixed_body) {
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();

        # Walk Context subtree to collect cfg_state entries for this scope.
        my %schedule;
        if (defined $sa) {
            my @stack = ($ctx);
            while (@stack) {
                my $c = pop @stack;
                my $state = $sa->cfg_state($c);
                if (defined $state
                        && (defined $state->{if_node}
                            || defined $state->{loop}
                            || defined $state->{try_node})) {
                    my $ir_node = $c->extract();
                    if (defined $ir_node && ref($ir_node)) {
                        $schedule{refaddr($ir_node)} = $state;
                    }
                    # try_node is the Constructor; also register by its refaddr.
                    if (defined $state->{try_node} && ref($state->{try_node})) {
                        $schedule{refaddr($state->{try_node})} = $state;
                    }
                }
                push @stack, reverse $c->children()->@*;
            }
        }

        # Determine graph start node: use inherited control from context,
        # or create a fresh Start node.
        my $start;
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            $start = $state->{control} if defined $state && defined $state->{control};
        }
        $start //= $factory->make('Start');

        # Collect Return and Unwind nodes from the fixed body as graph exits.
        my @returns;
        for my $stmt ($fixed_body->@*) {
            if ($stmt isa Chalk::IR::Node::Return
                    || $stmt isa Chalk::IR::Node::Unwind) {
                push @returns, $stmt;
            }
        }

        # Perl's implicit-return semantics: if no explicit Return/Unwind node
        # was found and the body is non-empty, the last expression in the body
        # is the implicit return value. Wrap it in a Return CFG node so the
        # graph is always properly terminated.
        if (!@returns && $fixed_body->@*) {
            my $last = $fixed_body->[-1];
            if (ref($last) && blessed($last) && $last->isa('Chalk::IR::Node')) {
                my $implicit_return = $factory->make_cfg('Return',
                    inputs => [$start, $last],
                );
                push @returns, $implicit_return;
            }
        }

        # Collect all body statements as BFS seeds so that side-effect nodes
        # (VarDecl, Assign, Call, If) without explicit control inputs are still
        # reachable via graph->nodes().  Filters out undef and non-Node items.
        my @body_stmts = grep {
            defined $_ && ref($_) && blessed($_) && $_->isa('Chalk::IR::Node')
        } $fixed_body->@*;

        # Also seed from statements inside control-flow regions (if/loop/try
        # bodies) stored in the schedule.  These statements are the then_stmts,
        # else_stmts, loop body statements, etc. that are not directly reachable
        # via inputs() from the If/Loop node itself.
        for my $state (values %schedule) {
            for my $key (qw(then_stmts else_stmts statements body_stmts)) {
                next unless defined $state->{$key} && ref($state->{$key}) eq 'ARRAY';
                for my $stmt ($state->{$key}->@*) {
                    next unless defined $stmt && ref($stmt) && blessed($stmt);
                    next unless $stmt->isa('Chalk::IR::Node');
                    push @body_stmts, $stmt;
                }
            }
        }

        return Chalk::IR::Graph->new(
            start      => $start,
            returns    => \@returns,
            schedule   => \%schedule,
            body_stmts => \@body_stmts,
        );
    }

    # §9 AdjustBlock — not in Tier A
    method AdjustBlock($ctx) {
        return undef;
    }

    # §9 TryCatchStatement — try/catch error handling
    # Grammar: /try\b/ _ Block _ /catch\b/ _ /\(/ _ ScalarVariable _ /\)/ _ Block
    # Children: Block (try body), ScalarVariable (catch var), Block (catch body)
    method TryCatchStatement($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $try_body;
        my $catch_var;
        my $catch_body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();

            if (ref($focus) eq 'ARRAY' && !defined $try_body) {
                # First arrayref is try_body (from Block)
                $try_body = $focus;
            } elsif ($focus isa Chalk::IR::Node::Constant && !defined $catch_var) {
                # Constant node is the catch variable name
                $catch_var = $focus->value();
            } elsif (ref($focus) eq 'ARRAY' && defined $try_body) {
                # Second arrayref is catch_body (from Block)
                $catch_body = $focus;
            }
        }

        return undef unless defined $try_body;

        # Apply fixup to bodies
        $try_body = _fixup_stmts($factory, $typed, $try_body);
        $catch_body = _fixup_stmts($factory, $typed, $catch_body // []);
        $catch_var //= '$_';

        # Build cfg_state with try_node key (same pattern as IfStatement)
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my $catch_var_const = $factory->make('Constant',
                    const_type => 'variable',
                    value      => $catch_var,
                );
                my $try_node = $typed->make('TryCatch',
                    inputs       => [$try_body, $catch_var_const, $catch_body],
                    compat_class => 'TryCatchStmt',
                );

                $sa->update_cfg({
                    control     => $state->{control},
                    scope       => $state->{scope},
                    try_node    => $try_node,
                    try_stmts   => $try_body,
                    catch_var   => $catch_var,
                    catch_stmts => $catch_body,
                });
                return $try_node;
            }
        }

        return undef;
    }

    # §10 AttributeList ::= WS Attribute | AttributeList WS Attribute
    # Returns arrayref of attribute hashrefs {name => $str, value => $str_or_undef}
    method AttributeList($ctx) {
        my @attrs;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @attrs, $val->@*;
            } elsif (ref($val) eq 'HASH') {
                push @attrs, $val;
            }
        }
        return \@attrs;
    }

    # §10 Attribute ::= /:/ _ QualifiedIdentifier | /:/ _ QualifiedIdentifier _ /\(/ _ QualifiedIdentifier _ /\)/
    # Returns plain hashref {name => $str, value => $str_or_undef}
    method Attribute($ctx) {
        my @constants = _collect_constants($ctx);
        my $attr_name  = $constants[0];  # QualifiedIdentifier (attribute name)
        my $attr_value = $constants[1];  # QualifiedIdentifier (optional, e.g. parent in :isa(Parent))

        return {
            name  => defined $attr_name  ? $attr_name->value()  : undef,
            value => defined $attr_value ? $attr_value->value() : undef,
        };
    }

    # §11 Signature ::= /\(/ _ /\)/ | /\(/ _ SignatureParams _ /\)/
    # Returns arrayref of param name Constants
    method Signature($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if ref($val) eq 'ARRAY';
        }
        return [];
    }

    # §11 SignatureParams ::= SignatureParam | SignatureParams _ /,/ _ SignatureParam
    method SignatureParams($ctx) {
        my @params;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @params, $val->@*;
            } elsif ($val isa Chalk::IR::Node::Constant) {
                push @params, $val;
            }
        }
        return \@params;
    }

    # §11 SignatureParam — transparent
    method SignatureParam($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::IR::Node::Constant;
        }
        return undef;
    }

    # §11 ScalarSignatureParam ::= ScalarVariable | ScalarVariable _ /=/ _ Expression
    method ScalarSignatureParam($ctx) {
        # Get the variable name from scanned text
        my $text = $ctx->scanned_text();
        # Extract just the variable name (first $word)
        if ($text =~ /(\$\w+)/) {
            return _make_const($factory, $1);
        }
        return undef;
    }

    # §11 SlurpySignatureParam — return variable name
    method SlurpySignatureParam($ctx) {
        my $text = $ctx->scanned_text();
        if ($text =~ /([@%]\w+)/) {
            return _make_const($factory, $1);
        }
        return undef;
    }

    # §12 Expression — transparent pass-through
    method Expression($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::IR::Node;
        }
        return undef;
    }

    # §12 ExpressionList — collect into arrayref
    method ExpressionList($ctx) {
        my @items;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @items, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @items, $val;
            }
        }
        return \@items;
    }

    # §13 Atom — transparent pass-through
    method Atom($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::IR::Node;
        }
        return undef;
    }

    # §16 CallExpression — detect return/die builtins, produce IR nodes
    # CallExpression ::= QualifiedIdentifier _ /\(/ _ ExpressionList? _ /\)/
    #                   | QualifiedIdentifier WS ExpressionList
    #                   | QualifiedIdentifier WS Block WS ExpressionList
    #                   | QualifiedIdentifier WS Block
    method CallExpression($ctx) {
        # Extract function name from scanned text
        my $func_name;
        my @leaves = _collect_ir_leaves($ctx);

        # Find the identifier (first Constant leaf that looks like a name)
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();
            if ($focus isa Chalk::IR::Node::Constant
                    && defined $rule
                    && $rule eq 'QualifiedIdentifier') {
                $func_name = $focus->value();
                last;
            }
        }

        # If no named leaf, try scanning text for identifier
        if (!defined $func_name) {
            my $text = $ctx->scanned_text();
            if ($text =~ /^[\s]*([a-zA-Z_]\w*)/) {
                $func_name = $1;
            }
        }

        # Collect argument values, preserving Block as AnonSubExpr
        my @args;
        my $has_block = false;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();
            # Skip the function name itself
            next if $focus isa Chalk::IR::Node::Constant
                && defined $rule
                && $rule eq 'QualifiedIdentifier'
                && defined $focus->value()
                && $focus->value() eq $func_name;

            # Block argument (map { BLOCK } LIST form): wrap as AnonSubExpr
            if (defined $rule && $rule eq 'Block') {
                my @body = ref($focus) eq 'ARRAY' ? $focus->@* : (defined $focus ? ($focus) : ());
                my $block_node = $typed->make('AnonSub',
                    inputs       => [[], \@body],
                    compat_class => 'AnonSubExpr',
                );
                unshift @args, $block_node;
                $has_block = true;
                next;
            }

            if (ref($focus) eq 'ARRAY') {
                push @args, $focus->@*;
            } elsif ($focus isa Chalk::IR::Node) {
                push @args, $focus;
            }
        }

        if (defined $func_name && $func_name eq 'return') {
            # return EXPR → Return CFG node
            my $value = $args[0]; # single value for Tier A
            my $control;
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            if (defined $sa) {
                my $state = $sa->inherited_cfg_state($ctx);
                $control = $state->{control} if defined $state;
            }
            $control //= $factory->make('Start');
            return $factory->make_cfg('Return',
                inputs => [$control, $value],
            );
        }

        if (defined $func_name && $func_name eq 'die') {
            # die EXPR → Unwind CFG node (exceptional exit)
            my $control;
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            if (defined $sa) {
                my $state = $sa->inherited_cfg_state($ctx);
                $control = $state->{control} if defined $state;
            }
            $control //= $factory->make('Start');
            return $factory->make_cfg('Unwind',
                inputs => [$control, \@args],
            );
        }

        # Generic builtin or function call → BuiltinCall
        if (defined $func_name) {
            my $name_node = _make_const($factory, $func_name);
            return $typed->make('Call',
                dispatch_kind => 'builtin',
                name          => $name_node->value(),
                inputs        => [$name_node, \@args],
                compat_class  => 'BuiltinCall',
            );
        }

        return undef;
    }

    # §19 Literal — transparent pass-through
    method Literal($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::IR::Node;
        }
        # Handle undef/true/false literals by scanned text
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        if ($text eq 'undef' || $text eq 'true' || $text eq 'false') {
            return _make_const($factory, $text);
        }
        return undef;
    }

    # §19 StringLiteral — extract string content
    # For double-quoted strings with $variable interpolation, returns
    # Constructor:InterpolatedString. Otherwise returns a plain Constant.
    method StringLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        # Strip quotes from single-quoted strings (no interpolation)
        if ($text =~ /^'((?:[^'\\]|\\.)*)'$/) {
            my $content = $1;
            $content =~ s/\\'/'/g;
            $content =~ s/\\\\/\\/g;
            return _make_const($factory, $content);
        }
        # Double-quoted strings: check for $variable interpolation
        if ($text =~ /^"((?:[^"\\]|\\.)*)"$/) {
            my $content = $1;
            # Process escape sequences for double-quoted strings
            if ($content =~ /\$[a-zA-Z_\d]/) {
                # Has variable interpolation — build InterpolatedString
                my @parts;
                my $remaining = $content;
                while ($remaining =~ /\G((?:[^\$\\]|\\.)*?)(\$(?:[a-zA-Z_]\w*|\d+))/gc) {
                    my ($literal, $var) = ($1, $2);
                    if (length($literal) > 0) {
                        my $lit = $self->_unescape_double_quote($literal);
                        push @parts, $factory->make('Constant',
                            const_type => 'string', value => $lit);
                    }
                    push @parts, $factory->make('Constant',
                        const_type => 'variable', value => $var);
                }
                # Remaining literal after last variable
                my $tail = substr($remaining, pos($remaining) // 0);
                if (length($tail) > 0) {
                    my $lit = $self->_unescape_double_quote($tail);
                    push @parts, $factory->make('Constant',
                        const_type => 'string', value => $lit);
                }
                return $typed->make('Interpolate',
                    inputs       => [\@parts],
                    compat_class => 'InterpolatedString',
                );
            }
            # No interpolation — plain constant
            $content =~ s/\\\\/\x00BS\x00/g;
            $content =~ s/\\n/\n/g;
            $content =~ s/\\t/\t/g;
            $content =~ s/\\"/"/g;
            $content =~ s/\\\$/\$/g;
            $content =~ s/\\\@/\@/g;
            $content =~ s/\x00BS\x00/\\/g;
            return _make_const($factory, $content);
        }
        return _make_const($factory, $text);
    }

    # Process escape sequences in double-quoted string content
    method _unescape_double_quote($str) {
        $str =~ s/\\\\/\x00BS\x00/g;
        $str =~ s/\\n/\n/g;
        $str =~ s/\\t/\t/g;
        $str =~ s/\\"/"/g;
        $str =~ s/\\\$/\$/g;
        $str =~ s/\\\@/\@/g;
        $str =~ s/\x00BS\x00/\\/g;
        return $str;
    }

    # §19 NumericLiteral — return as Constant
    method NumericLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §19 RegexLiteral — return as Constant with regex type
    method RegexLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return $factory->make('Constant', const_type => 'regex', value => $text);
    }

    # §20 QualifiedIdentifier — return as Constant
    method QualifiedIdentifier($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §20 Version — return as Constant
    method Version($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §20 Block ::= /\{/ _ StatementList? _ /\}/
    # Returns arrayref of body statement IR nodes
    method Block($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @stmts, $val;
            }
        }
        my $fixed = _fixup_stmts($factory, $typed, \@stmts);
        # Fix misparented postfix chains from Earley stale-value merge
        return [ map { _fix_postfix_chain($factory, $typed, $_) } $fixed->@* ];
    }

    # §18 Variable — resolve from scope if available, else Constant
    method Variable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        return _resolve_from_scope($ctx, $sa, $text, $factory)
            // $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 ScalarVariable — resolve from scope if available, else Constant
    method ScalarVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        return _resolve_from_scope($ctx, $sa, $text, $factory)
            // $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 ArrayVariable — resolve from scope if available, else Constant
    method ArrayVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        return _resolve_from_scope($ctx, $sa, $text, $factory)
            // $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 HashVariable — resolve from scope if available, else Constant
    method HashVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        return _resolve_from_scope($ctx, $sa, $text, $factory)
            // $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §13 QwLiteral — return array of Constants
    method QwLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        if ($text =~ /^qw\s*\(([^)]*)\)$/) {
            my @words = split /\s+/, $1;
            @words = grep { $_ ne '' } @words;
            return [map { _make_const($factory, $_) } @words];
        }
        return [];
    }

    # §8 VariableDeclaration ::= /my\b/ WS Variable
    #                          | /my\b/ WS Variable _ /=/ _ Expression
    #                          | /my\b/ WS VariableList _ /=/ _ Expression
    # Returns Constructor:VarDecl with variable name and optional initializer
    # §8 VariableDeclaration ::= /(?:my|our|state|local|field)\b/ WS Variable AttributeList?
    # For 'field' declarator: returns Constructor:FieldDecl with attributes.
    # For other declarators: returns Constructor:VarDecl.
    # Default values are handled by AssignmentExpression wrapping the declaration.
    method VariableDeclaration($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $is_field = false;
        my $var_name;
        my @attributes;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();

            # Declarator keyword is a raw string from the terminal scan
            if (!ref($focus) && defined $focus && $focus eq 'field') {
                $is_field = true;
                next;
            }

            if ($focus isa Chalk::IR::Node::Constant
                    && defined $focus->value()
                    && $focus->value() =~ /^[\$\@\%]/) {
                # Variable name (starts with sigil)
                $var_name //= $focus;
            } elsif (ref($focus) eq 'ARRAY') {
                # AttributeList returns arrayref of attribute hashrefs
                for my $attr ($focus->@*) {
                    if (ref($attr) eq 'HASH') {
                        push @attributes, $attr;
                    }
                }
            }
        }

        return undef unless defined $var_name;

        if ($is_field) {
            return Chalk::IR::FieldInfo->new(
                name       => $var_name->value(),
                attributes => \@attributes,
            );
        }

        my $var_decl = $typed->make('VarDecl',
            inputs       => [$var_name, undef],
            compat_class => 'VarDecl',
        );

        # Update CFG scope with the new variable binding
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my $new_scope = $state->{scope}->define($var_name->value(), $var_decl);
                $sa->update_cfg({
                    control => $state->{control},
                    scope   => $new_scope,
                });
            }
        }

        return $var_decl;
    }

    # §13 ParenExpr — transparent
    method ParenExpr($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::IR::Node;
            return $val if ref($val) eq 'ARRAY';
        }
        return undef;
    }

    # §13 ArrayConstructor ::= /\[/ _ ExpressionList? _ /\]/
    # Returns Constructor:ArrayRefExpr
    method ArrayConstructor($ctx) {
        my @values = _collect_ir_values($ctx);
        my @elements;
        for my $val (@values) {
            if (ref($val) eq 'ARRAY') {
                push @elements, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @elements, $val;
            }
        }
        return $typed->make('ArrayRef',
            inputs       => [\@elements],
            compat_class => 'ArrayRefExpr',
        );
    }

    # §13 HashConstructor ::= /\{/ _ ExpressionList? _ /\}/
    # Returns Constructor:HashRefExpr
    method HashConstructor($ctx) {
        my @values = _collect_ir_values($ctx);
        my @pairs;
        for my $val (@values) {
            if (ref($val) eq 'ARRAY') {
                push @pairs, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @pairs, $val;
            }
        }
        return $typed->make('HashRef',
            inputs       => [\@pairs],
            compat_class => 'HashRefExpr',
        );
    }

    # §13 AnonymousSub ::= /sub\b/ _ Signature? _ Block
    # Returns Constructor:AnonSubExpr
    method AnonymousSub($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my @params;
        my $body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (ref($focus) eq 'ARRAY') {
                if (defined $rule && ($rule eq 'Signature' || $rule eq 'SignatureParams')) {
                    @params = $focus->@*;
                } elsif (!defined $body) {
                    $body = $focus;
                }
            }
        }

        $body = _fixup_stmts($factory, $typed, $body // []);

        return $typed->make('AnonSub',
            inputs       => [\@params, $body],
            compat_class => 'AnonSubExpr',
        );
    }

    # §14 UnaryExpression ::= /[!\\-]/ _ Expression
    #                       | /not\b/ WS Expression
    # Returns Constructor:UnaryExpr with op and operand
    method UnaryExpression($ctx) {
        my $text = $ctx->scanned_text();
        my $op;
        if ($text =~ /^\s*(!)/) {
            $op = $1;
        } elsif ($text =~ /^\s*(-)/) {
            $op = $1;
        } elsif ($text =~ /^\s*(not)\b/) {
            $op = $1;
        } elsif ($text =~ /^\s*(\\)/) {
            $op = $1;
        }

        my @values = _collect_ir_values($ctx);
        my $operand;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node) {
                $operand = $val;
                last;
            }
        }

        return undef unless defined $op && defined $operand;

        my $op_node  = _make_const($factory, $op);
        my $op_str   = $op_node->value();
        my $unop_type = $UNOP_MAP{$op_str} // die "Unknown unary op: $op_str";
        return $typed->make($unop_type,
            inputs       => [$op_node, $operand],
            operand      => $operand,
            compat_class => 'UnaryExpr',
        );
    }

    # §15 BinaryExpression ::= Expression _ BinaryOp _ Expression
    # For =~ with regex, produces RegexMatch or RegexSubst.
    # Otherwise produces BinaryExpr.
    method BinaryExpression($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $left;
        my $op;
        my $right;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (!defined $left && $focus isa Chalk::IR::Node) {
                $left = $focus;
            } elsif (defined $left && !defined $op
                    && $focus isa Chalk::IR::Node::Constant) {
                # BinaryOp returns a Constant with the operator
                $op = $focus;
            } elsif (defined $op && $focus isa Chalk::IR::Node) {
                $right //= $focus;
            }
        }

        return undef unless defined $left && defined $op;

        my $op_val = $op->value();

        # Handle =~ with regex
        if ($op_val eq '=~' && defined $right
                && $right isa Chalk::IR::Node::Constant
                && defined $right->value()) {
            my $pat = $right->value();
            if ($pat =~ m{^s/}) {
                # s/pat/repl/flags
                if ($pat =~ m{^s/((?:[^/\\]|\\.)*)/((?:[^/\\]|\\.)*)/([\w]*)$}) {
                    my $flags_node = _make_const($factory, $3);
                    my $flags_str  = (defined $flags_node ? $flags_node->value() : '') // '';
                    return $typed->make('RegexSubst',
                        flags        => $flags_str,
                        inputs       => [$left, _make_const($factory, $1), _make_const($factory, $2), $flags_node],
                        compat_class => 'RegexSubst',
                    );
                }
            } else {
                # /pattern/flags or m/pattern/flags
                my $flags_node = _make_const($factory, '');
                my $flags_str  = (defined $flags_node ? $flags_node->value() : '') // '';
                return $typed->make('RegexMatch',
                    flags        => $flags_str,
                    inputs       => [$left, $right, $flags_node],
                    compat_class => 'RegexMatch',
                );
            }
        }

        my $op_str    = $op->value();
        my $binop_type = $BINOP_MAP{$op_str} // die "Unknown binary op: $op_str";
        return $typed->make($binop_type,
            inputs       => [$op, $left, $right],
            left         => $left,
            right        => $right,
            compat_class => 'BinaryExpr',
        );
    }

    # §15 BinaryOp — returns the operator as a Constant
    method BinaryOp($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §16 PostfixExpression ::= Atom PostfixOp*
    # Chains invocant into MethodCall, Subscript, PostfixDeref
    method PostfixExpression($ctx) {
        my @values = _collect_ir_values($ctx);

        # Collect the base expression and any postfix operations
        my $base;
        my @postfix_ops;

        for my $val (@values) {
            next unless $val isa Chalk::IR::Node;
            if (!defined $base) {
                $base = $val;
            } else {
                push @postfix_ops, $val;
            }
        }

        return undef unless defined $base;

        # Chain postfix operations by setting invocant/target
        my $result = $base;
        for my $op (@postfix_ops) {
            if ($op isa Chalk::IR::Node::Call && $op->dispatch_kind() eq 'method') {
                # Set invocant to current result, pushing inward
                # past any prefix wrappers from stale-value merge
                $result = _push_methodcall_inward(
                    $factory, $typed, $result, $op->inputs()->[1], $op->inputs()->[2],
                );
            } elsif ($op isa Chalk::IR::Node::Subscript) {
                # Push subscript inside exists/delete BuiltinCall so the
                # argument includes the full subscript chain:
                #   SubscriptExpr(BuiltinCall(exists, [$chart]), $pos)
                #   → BuiltinCall(exists, [SubscriptExpr($chart, $pos)])
                if ($result isa Chalk::IR::Node::Call
                        && $result->dispatch_kind() eq 'builtin') {
                    my $bname = $result->inputs()->[0]->value();
                    if ($bname eq 'exists' || $bname eq 'delete') {
                        my @args = $result->inputs()->[1]->@*;
                        my $inner_target = $args[-1];
                        $args[-1] = $typed->make('Subscript',
                            inputs       => [$inner_target, $op->inputs()->[1], $op->inputs()->[2]],
                            compat_class => 'SubscriptExpr',
                        );
                        $result = $typed->make('Call',
                            dispatch_kind => 'builtin',
                            name          => $result->inputs()->[0]->value(),
                            inputs        => [$result->inputs()->[0], \@args],
                            compat_class  => 'BuiltinCall',
                        );
                        next;
                    }
                }
                $result = $typed->make('Subscript',
                    inputs       => [$result, $op->inputs()->[1], $op->inputs()->[2]],
                    compat_class => 'SubscriptExpr',
                );
            } elsif ($op isa Chalk::IR::Node::PostfixDeref) {
                my $s = $op->inputs()->[1];
                $result = $typed->make('PostfixDeref',
                    sigil        => (ref($s) ? $s->value() : $s),
                    inputs       => (ref($s) ? [$result, $s] : [$result]),
                    compat_class => 'PostfixDerefExpr',
                );
            }
        }

        return $result;
    }

    # §16 MethodCall ::= Expression _ /->/ _ QualifiedIdentifier _ /\(/ _ ExpressionList? _ /\)/
    #                  | Expression _ /->/ _ QualifiedIdentifier
    #                  | Expression _ /->/ _ ScalarVariable _ /\(/ _ ExpressionList? _ /\)/
    #                  | Expression _ /->/ _ ScalarVariable
    # Returns Constructor:MethodCallExpr with invocant from child Expression
    method MethodCall($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $invocant;
        my $method_name;
        my @args;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (!defined $method_name
                    && $focus isa Chalk::IR::Node::Constant
                    && defined $rule
                    && $rule eq 'QualifiedIdentifier') {
                $method_name = $focus;
            } elsif (!defined $method_name
                    && $focus isa Chalk::IR::Node) {
                # Leaves before QualifiedIdentifier are the invocant expression
                $invocant = $focus;
            } elsif (defined $method_name) {
                if (ref($focus) eq 'ARRAY') {
                    push @args, $focus->@*;
                } elsif ($focus isa Chalk::IR::Node) {
                    push @args, $focus;
                }
            }
        }

        return undef unless defined $method_name;

        # Push MethodCall inward past prefix wrappers when the Earley
        # stale-value merge misparents a BuiltinCall as the invocant
        return _push_methodcall_inward($factory, $typed, $invocant, $method_name, \@args);
    }

    # §16 Subscript ::= Expression _ /->/ _ /\[/ _ Expression _ /\]/
    #                 | Expression _ /->/ _ /\{/ _ Expression _ /\}/
    #                 | Expression _ /->/ _ /\(/ _ ExpressionList? _ /\)/
    #                 | Expression _ /\[/ _ Expression _ /\]/
    #                 | Expression _ /\{/ _ Expression _ /\}/
    # Returns Constructor:SubscriptExpr with target from first child Expression
    method Subscript($ctx) {
        my $text = $ctx->scanned_text();
        # Determine style by the LAST bracket type in the scanned text.
        # For chained subscripts like $chart->[$pos]{$core_id}, the Subscript
        # action processes the outermost subscript (the last bracket pair).
        # Paren subscripts like $f->($arg) are coderef calls (style "call").
        my $style = ($text =~ /\]$/) ? 'array'
                  : ($text =~ /\)$/) ? 'call'
                  :                    'hash';

        my @values = _collect_ir_values($ctx);
        my $target;
        my $index;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node) {
                if (!defined $target) {
                    $target = $val;
                } elsif (!defined $index) {
                    $index = $val;
                    last;
                }
            } elsif (ref($val) eq 'ARRAY' && $style eq 'call' && !defined $index) {
                # ExpressionList returns arrayref — capture as call arguments
                $index = $val;
                last;
            }
        }

        return $typed->make('Subscript',
            inputs       => [$target, $index, _make_const($factory, $style)],
            compat_class => 'SubscriptExpr',
        );
    }

    # §16 PostfixDeref ::= Expression _ /->/ _ /@\*/
    #                     | Expression _ /->/ _ /%\*/
    #                     | Expression _ /->/ _ /\$\*/
    #                     | Expression _ /->/ _ /\$#\*/
    # Returns Constructor:PostfixDerefExpr with target from child Expression
    method PostfixDeref($ctx) {
        my $text = $ctx->scanned_text();
        my $sigil;
        if ($text =~ /\@\*/) {
            $sigil = '@';
        } elsif ($text =~ /%\*/) {
            $sigil = '%';
        } elsif ($text =~ /\$#\*/) {
            $sigil = '$#';
        } elsif ($text =~ /\$\*/) {
            $sigil = '$';
        }

        # Extract base Expression from children
        my $target;
        for my $val (_collect_ir_values($ctx)) {
            if ($val isa Chalk::IR::Node) {
                $target = $val;
                last;
            }
        }

        my $sigil_node = _make_const($factory, $sigil // '@');

        # When the Earley parser produces a stale-value merge, prefix
        # constructs (return, scalar, etc.) can end up as the target of
        # PostfixDeref instead of wrapping it. Recursively push the deref
        # inward past prefix wrappers until it reaches the actual target:
        #   PostfixDeref(Return(ctrl, X), @)
        #     → Return(ctrl, PostfixDeref(X, @))
        #   PostfixDeref(BuiltinCall(scalar, [X]), @)
        #     → BuiltinCall(scalar, [PostfixDeref(X, @)])
        #   PostfixDeref(Return(ctrl, BuiltinCall(scalar, [X])), @)
        #     → Return(ctrl, BuiltinCall(scalar, [PostfixDeref(X, @)]))
        return _push_deref_inward($factory, $typed, $target, $sigil_node);
    }

    # §16 PostfixIncDec ::= Expression _ /\+\+/ | Expression _ /--/
    # Emit as CompoundAssign(+=, target, 1) or CompoundAssign(-=, target, 1).
    method PostfixIncDec($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $target;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (defined $focus && $focus isa Chalk::IR::Node) {
                $target //= $focus;
            }
        }
        return undef unless defined $target;
        my $scanned = $ctx->scanned_text() // '';
        my $op_str = ($scanned =~ /--/) ? '-=' : '+=';
        my $op_node  = $factory->make('Constant', value => $op_str,  const_type => 'string');
        my $one_node = $factory->make('Constant', value => '1',      const_type => 'number');
        return $typed->make('CompoundAssign',
            op           => $op_node,
            inputs       => [$op_node, $target, $one_node],
            compat_class => 'CompoundAssign',
        );
    }

    # §17 TernaryExpression ::= Expression _ /\?/ _ Expression _ /:/ _ Expression
    # Returns Constructor:TernaryExpr
    method TernaryExpression($ctx) {
        my @values = _collect_ir_values($ctx);
        my @ir_nodes;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node) {
                push @ir_nodes, $val;
            }
        }

        # Should have exactly 3 IR nodes: condition, true_expr, false_expr
        return undef unless @ir_nodes >= 3;

        return $typed->make('TernaryExpr',
            inputs       => [$ir_nodes[0], $ir_nodes[1], $ir_nodes[2]],
            compat_class => 'TernaryExpr',
        );
    }

    # §17 AssignmentExpression ::= Expression _ AssignOp _ Expression
    # Simple '=' returns undef (handled by VariableDeclaration).
    # Compound assignment (.=, //=, etc.) returns CompoundAssign.
    method AssignmentExpression($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $target;
        my $op;
        my $value;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();

            if (!defined $target
                    && ($focus isa Chalk::IR::Node
                        || $focus isa Chalk::IR::FieldInfo)) {
                $target = $focus;
            } elsif (defined $target && !defined $op
                    && $focus isa Chalk::IR::Node::Constant) {
                $op = $focus;
            } elsif (defined $op && $focus isa Chalk::IR::Node) {
                $value //= $focus;
            } elsif (defined $op && ref($focus) eq 'ARRAY') {
                # ParenExpr/ExpressionList returns an arrayref for (k => v, ...)
                $value //= $focus;
            }
        }

        return undef unless defined $target && defined $op;

        # Helper: update scope when assigning to a variable.
        # Called with the variable name (string with sigil) and the resulting IR node.
        my $update_scope = sub ($var_name, $ir_node) {
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            return unless defined $sa;
            my $state = $sa->inherited_cfg_state($ctx);
            return unless defined $state;
            my $new_scope = $state->{scope}->define($var_name, $ir_node);
            $sa->update_cfg({ $state->%*, scope => $new_scope });
        };

        my $op_val = $op->value();
        if ($op_val eq '=') {
            # FieldInfo target: set its default_value and return a new FieldInfo
            if ($target isa Chalk::IR::FieldInfo) {
                return Chalk::IR::FieldInfo->new(
                    name          => $target->name(),
                    attributes    => $target->attributes(),
                    default_value => $value,
                );
            }
            # VarDecl target: set its initializer and return it
            if ($target isa Chalk::IR::Node::VarDecl) {
                # If value is an arrayref (from ParenExpr/ExpressionList),
                # wrap it in a HashRef node so it can be stored as a node input.
                # The emitter will render it as (k, v, ...) for hash variable init.
                my $init_value = $value;
                if (ref($value) eq 'ARRAY') {
                    $init_value = $typed->make('HashRef',
                        inputs       => [$value],
                        compat_class => 'HashRefExpr',
                    );
                }
                my $result = $typed->make('VarDecl',
                    inputs       => [$target->inputs()->[0], $init_value],
                    compat_class => 'VarDecl',
                );
                my $var_name_node = $target->inputs()->[0];
                if ($var_name_node isa Chalk::IR::Node::Constant
                        && defined $var_name_node->value()
                        && $var_name_node->value() =~ /^[\$\@\%]/) {
                    $update_scope->($var_name_node->value(), $result);
                }
                return $result;
            }
            # Plain variable assignment ($var = expr) — emit as BinaryExpr (Assign).
            # VarDecl is only for my/our/state declarations (handled above).
            my $assign_op_str = $op->value();
            my $assign_binop_type = $BINOP_MAP{$assign_op_str} // die "Unknown binary op: $assign_op_str";
            my $assign_result = $typed->make($assign_binop_type,
                inputs       => [$op, $target, $value],
                left         => $target,
                right        => $value,
                compat_class => 'BinaryExpr',
            );
            # SSA: track reassignment in scope (new value per assignment)
            if ($target isa Chalk::IR::Node::Constant
                    && defined $target->value()
                    && $target->value() =~ /^[\$\@\%]/) {
                $update_scope->($target->value(), $assign_result);
            }
            return $assign_result;
        }

        # Compound assignment (.=, //=, +=, etc.)
        my $compound_result = $typed->make('CompoundAssign',
            op           => $op,
            inputs       => [$op, $target, $value],
            compat_class => 'CompoundAssign',
        );
        if ($target isa Chalk::IR::Node::Constant
                && defined $target->value()
                && $target->value() =~ /^[\$\@\%]/) {
            $update_scope->($target->value(), $compound_result);
        }
        return $compound_result;
    }

    # §17 AssignOp — returns operator as Constant
    method AssignOp($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §4 PostfixModifier ::= /(?:if|unless|while|until|for|foreach)\b/ _ Expression
    # Returns CFG If or Loop node for control flow dispatch.
    method PostfixModifier($ctx) {
        my $text = $ctx->scanned_text();
        my $keyword;
        if ($text =~ /^\s*(if|unless|while|until|for(?:each)?)\b/) {
            $keyword = $1;
        }

        my @values = _collect_ir_values($ctx);
        my $condition;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node) {
                $condition = $val;
                last;
            }
        }

        # Fix stale-value merge corruption in condition:
        # _fix_postfix_chain_deep recursively pushes SubscriptExpr wrappers
        # into the correct positions (BuiltinCall args, BinaryExpr right
        # operands, UnaryExpr operands). Since If nodes are not Constructors,
        # _fix_postfix_chain won't reach the condition from _fixup_stmts.
        if (defined $condition) {
            $condition = $_fix_postfix_chain_deep->($factory, $typed, $condition);
        }

        return undef unless defined $keyword;

        # Build CFG nodes for loop-type modifiers (for/foreach/while/until)
        if ($keyword =~ /^(?:for|foreach|while|until)$/) {
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            if (defined $sa) {
                my $state = $sa->inherited_cfg_state($ctx);
                if (defined $state) {
                    my $loop_cond = $condition // $factory->make('Constant',
                        const_type => 'string', value => '__loop_bound__');
                    # For 'until', negate the condition (until X = while !X)
                    if ($keyword eq 'until') {
                        my $not_op = _make_const($factory, '!');
                        my $not_type = $UNOP_MAP{'!'} // die "Unknown unary op: !";
                        $loop_cond = $typed->make($not_type,
                            inputs       => [$not_op, $loop_cond],
                            operand      => $loop_cond,
                            compat_class => 'UnaryExpr',
                        );
                    }
                    my $loop = $factory->make('Loop',
                        entry_ctrl    => $state->{control},
                        backedge_ctrl => undef,
                    );
                    my $if_node = $factory->make('If',
                        control   => $loop,
                        condition => $loop_cond,
                    );
                    my $body_proj = $factory->make('Proj', source => $if_node, index => 0);
                    my $exit_proj = $factory->make('Proj', source => $if_node, index => 1);
                    my $region = $factory->make('Region',
                        controls => [$exit_proj],
                    );
                    $sa->update_cfg({
                        control    => $region,
                        scope      => $state->{scope},
                        loop       => $loop,
                        loop_if    => $if_node,
                        body_proj  => $body_proj,
                        exit_proj  => $exit_proj,
                        body_stmts => [],
                    });
                    return $loop;
                }
            }
        } elsif ($keyword =~ /^(?:if|unless)$/) {
            # Postfix if/unless: builds If/Proj/Region like IfStatement
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            if (defined $sa) {
                my $state = $sa->inherited_cfg_state($ctx);
                if (defined $state) {
                    # For 'unless', negate the condition (unless X = if !X)
                    my $cond = $condition;
                    if ($keyword eq 'unless') {
                        my $not_op2 = _make_const($factory, '!');
                        my $not_type2 = $UNOP_MAP{'!'} // die "Unknown unary op: !";
                        $cond = $typed->make($not_type2,
                            inputs       => [$not_op2, $condition],
                            operand      => $condition,
                            compat_class => 'UnaryExpr',
                        );
                    }
                    my $if_node = $factory->make('If',
                        control   => $state->{control},
                        condition => $cond,
                    );
                    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
                    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
                    my $region = $factory->make('Region',
                        controls => [$true_proj, $false_proj],
                    );
                    $sa->update_cfg({
                        control    => $region,
                        scope      => $state->{scope},
                        then_stmts => [],
                        else_stmts => undef,
                        if_node    => $if_node,
                        true_proj  => $true_proj,
                        false_proj => $false_proj,
                    });
                    return $if_node;
                }
            }
        }

        return undef;
    }

    # §5 IfStatement ::= /(?:if|unless)\b/ _ ParenExpr _ Block
    #                   | /(?:if|unless)\b/ _ ParenExpr _ Block _ ElsifChain
    #                   | /(?:if|unless)\b/ _ ParenExpr _ Block _ /else\b/ _ Block
    method IfStatement($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $condition;
        my $then_body;
        my $else_body;
        my $keyword;

        # Extract keyword from scanned text
        my $text = $ctx->scanned_text();
        if ($text =~ /^\s*(if|unless)\b/) {
            $keyword = $1;
        }

        my $cond_leaf;
        my $then_leaf;
        my $else_leaf;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (!defined $condition && $focus isa Chalk::IR::Node) {
                # First IR node is the condition (from ParenExpr)
                # Skip CFG If nodes from ElsifChain
                if ($focus isa Chalk::IR::Node::If) {
                    $else_body = [$focus];
                    next;
                }
                $condition = $focus;
                $cond_leaf = $leaf;  # remember condition leaf for pre-branch scope
            } elsif (ref($focus) eq 'ARRAY' && !defined $then_body) {
                # First array is then_body (from Block); remember leaf for scope extraction
                $then_body = $focus;
                $then_leaf = $leaf;
            } elsif (ref($focus) eq 'ARRAY' && defined $then_body) {
                # Second array is else_body (from else Block); remember leaf for scope extraction
                $else_body = $focus;
                $else_leaf = $leaf;
            } elsif ($focus isa Chalk::IR::Node::If) {
                # ElsifChain returns a CFG If node — wrap as else_body
                $else_body = [$focus];
            }
        }

        return undef unless defined $condition;

        # Apply fixup to bodies
        $then_body = _fixup_stmts($factory, $typed, $then_body // []);
        $else_body = defined $else_body ? _fixup_stmts($factory, $typed, $else_body) : undef;

        # For 'unless', wrap condition in UnaryExpr with '!'
        if (defined $keyword && $keyword eq 'unless') {
            my $not_op3 = _make_const($factory, '!');
            my $not_type3 = $UNOP_MAP{'!'} // die "Unknown unary op: !";
            $condition = $typed->make($not_type3,
                inputs       => [$not_op3, $condition],
                operand      => $condition,
                compat_class => 'UnaryExpr',
            );
        }

        # Build CFG nodes: If/Proj/Region for control flow
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my $if_node = $factory->make('If',
                    control   => $state->{control},
                    condition => $condition,
                );
                my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
                my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
                my $region = $factory->make('Region',
                    controls => [$true_proj, $false_proj],
                );

                # Extract per-branch final scopes from the leaf Contexts that
                # provided then_body and else_body.  cfg_state on those leaves
                # records the scope as it stood at the end of each branch.
                #
                # The pre-branch scope comes from the condition leaf's cfg_state,
                # not from state->{scope}: by the time the complete event runs, multiply()
                # has already merged the then-block's scope into the inherited state,
                # so state->{scope} is contaminated with branch assignments.
                my $pre_scope;
                if (defined $cond_leaf) {
                    my $cs = $sa->cfg_state($cond_leaf);
                    $pre_scope = $cs->{scope} if defined $cs && defined $cs->{scope};
                }
                $pre_scope //= $state->{scope};

                my $then_scope  = $pre_scope;
                my $else_scope  = $pre_scope;
                if (defined $then_leaf) {
                    my $ts = $sa->cfg_state($then_leaf);
                    $then_scope = $ts->{scope} if defined $ts && defined $ts->{scope};
                }
                if (defined $else_leaf) {
                    my $es = $sa->cfg_state($else_leaf);
                    $else_scope = $es->{scope} if defined $es && defined $es->{scope};
                }

                # Merge branch scopes with eager Phi creation for variables
                # that differ between branches.
                my $merged_scope = $pre_scope->merge_with_phis(
                    $then_scope, $else_scope, $region, $factory,
                );

                $sa->update_cfg({
                    control    => $region,
                    scope      => $merged_scope,
                    then_stmts => $then_body,
                    else_stmts => $else_body,
                    if_node    => $if_node,
                    true_proj  => $true_proj,
                    false_proj => $false_proj,
                });
                return $if_node;
            }
        }

        return undef;
    }

    # §5 ElsifChain ::= /elsif\b/ _ ParenExpr _ Block
    #                  | /elsif\b/ _ ParenExpr _ Block _ ElsifChain
    #                  | /elsif\b/ _ ParenExpr _ Block _ /else\b/ _ Block
    # Returns a CFG If node (elsif is just a nested if)
    method ElsifChain($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $condition;
        my $then_body;
        my $else_body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();

            if (!defined $condition && $focus isa Chalk::IR::Node) {
                # Skip CFG If nodes from nested ElsifChain
                if ($focus isa Chalk::IR::Node::If) {
                    $else_body = [$focus];
                    next;
                }
                $condition = $focus;
            } elsif (ref($focus) eq 'ARRAY' && !defined $then_body) {
                $then_body = $focus;
            } elsif (ref($focus) eq 'ARRAY' && defined $then_body) {
                $else_body = $focus;
            } elsif ($focus isa Chalk::IR::Node::If) {
                # Nested ElsifChain returns a CFG If node
                $else_body = [$focus];
            }
        }

        return undef unless defined $condition;

        $then_body = _fixup_stmts($factory, $typed, $then_body // []);
        $else_body = defined $else_body ? _fixup_stmts($factory, $typed, $else_body) : undef;

        # Build CFG nodes for the elsif branch
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my $if_node = $factory->make('If',
                    control   => $state->{control},
                    condition => $condition,
                );
                my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
                my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
                my $region = $factory->make('Region',
                    controls => [$true_proj, $false_proj],
                );
                $sa->update_cfg({
                    control    => $region,
                    scope      => $state->{scope},
                    then_stmts => $then_body,
                    else_stmts => $else_body,
                    if_node    => $if_node,
                    true_proj  => $true_proj,
                    false_proj => $false_proj,
                });
                return $if_node;
            }
        }

        return undef;
    }

    # §6 WhileStatement ::= /(?:while|until)\b/ _ ParenExpr _ Block
    # Returns CFG Loop node for control flow dispatch
    method WhileStatement($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $keyword;
        my $condition;
        my $body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule() // '';

            # The keyword is a plain string leaf (from regex scan), not a Constant node
            if (!defined $keyword && defined $focus && !ref($focus)
                    && $focus =~ /^(?:while|until)$/) {
                $keyword = $focus;
            } elsif (defined $keyword && !defined $condition) {
                # First IR node after keyword is the condition (from ParenExpr/Expression)
                if ($focus isa Chalk::IR::Node) {
                    $condition = $focus;
                } elsif (ref($focus) eq 'ARRAY' && $focus->@*) {
                    # ParenExpr may produce an array; take first element as condition
                    $condition = $focus->[0];
                }
            } elsif (defined $condition && !defined $body && ref($focus) eq 'ARRAY') {
                # Block body
                $body = $focus;
            }
        }

        return undef unless defined $keyword && defined $condition;

        $body = _fixup_stmts($factory, $typed, $body // []);

        # Build CFG nodes: Loop/If/Proj/Region for control flow
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my $pre_loop_scope = $state->{scope};

                my $loop = $factory->make('Loop',
                    entry_ctrl    => $state->{control},
                    backedge_ctrl => undef,
                );
                my $if_node = $factory->make('If',
                    control   => $loop,
                    condition => $condition,
                );
                my $body_proj = $factory->make('Proj', source => $if_node, index => 0);
                my $exit_proj = $factory->make('Proj', source => $if_node, index => 1);

                # Collect post-body scope bindings for Phi backedge wiring.
                my %body_final_bindings;
                for my $leaf (_collect_ir_leaves($ctx)) {
                    my $leaf_state = $sa->cfg_state($leaf);
                    if (defined $leaf_state && defined $leaf_state->{scope}) {
                        for my $name ($leaf_state->{scope}->variable_names()) {
                            my $binding = $leaf_state->{scope}->lookup($name);
                            $body_final_bindings{$name} = $binding if defined $binding;
                        }
                    }
                }

                # Create Phi nodes for loop-carried variables directly here.
                # While loops have no iterator variable, so pass undef.
                my $post_loop_scope = defined $pre_loop_scope
                    ? $pre_loop_scope->merge_for_loop(
                        \%body_final_bindings, $loop, $factory, undef,
                      )
                    : $pre_loop_scope;

                my $region = $factory->make('Region',
                    controls => [$exit_proj],
                );
                $sa->update_cfg({
                    control    => $region,
                    scope      => $post_loop_scope,
                    body_stmts => $body,
                    loop       => $loop,
                    loop_if    => $if_node,
                    body_proj  => $body_proj,
                    exit_proj  => $exit_proj,
                });
                return $loop;
            }
        }

        return undef;
    }

    # §6 ForStatement — not needed for Tier C (C-style for loops)
    method ForStatement($ctx) {
        return undef;
    }

    # §6 ForeachStatement ::= /for(?:each)?\b/ _ IteratorVariable _ ParenExpr _ Block
    # Returns CFG Loop node for control flow dispatch
    method ForeachStatement($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $iterator;
        my $list;
        my $body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule() // '';

            if ($focus isa Chalk::IR::Node::Constant
                    && defined $focus->value()
                    && $focus->value() =~ /^[\$\@\%]/
                    && !defined $iterator) {
                $iterator = $focus;
            } elsif (ref($focus) eq 'ARRAY' && defined $iterator && !defined $list) {
                # First array after iterator is the list (from ParenExpr)
                $list = $focus;
            } elsif (ref($focus) eq 'ARRAY' && defined $list) {
                # Second array is the body (from Block)
                $body //= $focus;
            } elsif ($focus isa Chalk::IR::Node && !defined $list
                    && defined $iterator) {
                $list = $focus;
            }
        }

        return undef unless defined $iterator;

        # Fix postfix deref chains in the list expression (e.g.,
        # $tree->ops()->@* parsed as $tree->@*->ops() due to Earley merge)
        if (defined $list && $list isa Chalk::IR::Node) {
            $list = _fix_postfix_chain($factory, $typed, $list);
        }

        $body = _fixup_stmts($factory, $typed, $body // []);

        # Build CFG nodes: Loop/If/Proj/Region for control flow
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state) {
                my $pre_loop_scope = $state->{scope};

                my $loop_cond = $factory->make('Constant',
                    const_type => 'string', value => '__loop_bound__');
                my $loop = $factory->make('Loop',
                    entry_ctrl    => $state->{control},
                    backedge_ctrl => undef,
                );
                my $if_node = $factory->make('If',
                    control   => $loop,
                    condition => $loop_cond,
                );
                my $body_proj = $factory->make('Proj', source => $if_node, index => 0);
                my $exit_proj = $factory->make('Proj', source => $if_node, index => 1);

                # Collect post-body scope bindings for Phi backedge wiring.
                # If a variable was assigned inside the loop body (e.g., $sum = $sum + $x),
                # the body leaf cfg_state will have a scope binding that differs from the
                # pre-loop value. These become the backedge values in the Phi nodes.
                my %body_final_bindings;
                for my $leaf (_collect_ir_leaves($ctx)) {
                    my $leaf_state = $sa->cfg_state($leaf);
                    if (defined $leaf_state && defined $leaf_state->{scope}) {
                        for my $name ($leaf_state->{scope}->variable_names()) {
                            my $binding = $leaf_state->{scope}->lookup($name);
                            $body_final_bindings{$name} = $binding if defined $binding;
                        }
                    }
                }

                # Create Phi nodes for loop-carried variables directly here.
                # The iterator variable is defined by the loop itself and excluded.
                my $iterator_name = defined $iterator ? $iterator->value() : undef;
                my $post_loop_scope = defined $pre_loop_scope
                    ? $pre_loop_scope->merge_for_loop(
                        \%body_final_bindings, $loop, $factory, $iterator_name,
                      )
                    : $pre_loop_scope;

                my $region = $factory->make('Region',
                    controls => [$exit_proj],
                );
                $sa->update_cfg({
                    control    => $region,
                    scope      => $post_loop_scope,
                    body_stmts => $body,
                    loop       => $loop,
                    loop_if    => $if_node,
                    body_proj  => $body_proj,
                    exit_proj  => $exit_proj,
                    iterator   => $iterator,
                    list       => $list,
                });
                return $loop;
            }
        }

        return undef;
    }

    # §6 IteratorVariable ::= /my\b/ WS ScalarVariable | ScalarVariable
    # Returns variable name as Constant
    method IteratorVariable($ctx) {
        my $text = $ctx->scanned_text();
        if ($text =~ /(\$\w+)/) {
            return _make_const($factory, $1);
        }
        return undef;
    }

    # §8 VariableList — not in Tier A
    method VariableList($ctx) {
        return undef;
    }

}

1;

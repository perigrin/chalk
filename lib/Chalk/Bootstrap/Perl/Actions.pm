# ABOUTME: Semantic actions for Perl grammar that build Perl IR nodes from parse results.
# ABOUTME: One method per grammar rule, constructing Constructor:Program/UseDecl/ClassDecl/etc.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Builtin keyword sets used by _fixup_stmts for statement merging
my %LIST_BUILTINS = map { $_ => 1 } qw(push unshift pop shift splice print say warn sort reverse chomp chop);
my %PREFIX_BUILTINS = map { $_ => 1 } qw(scalar defined ref exists delete keys values each length chr ord substr sprintf join split);
my %STMT_BOUNDARY_CLASSES = map { $_ => 1 } qw(ClassDecl MethodDecl FieldDecl ReturnStmt DieCall SubDecl VarDecl);
my %STMT_BOUNDARY_OPS = map { $_ => 1 } qw(If Loop);
my %STOP_KEYWORDS = map { $_ => 1 } qw(push unshift return die my for if unless while until);

class Chalk::Bootstrap::Perl::Actions {
    field $factory;

    # Side table: maps refaddr(loop_ir_node) => hashref of variable names read in loop body.
    # Populated by ForeachStatement and ExpressionStatement (postfix loops);
    # consumed by Program for Phi insertion.
    # Instance-scoped so it is GC'd with the Actions object between parses.
    field %_loop_body_var_refs;

    ADJUST {
        $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
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

    # Helper: find first IR leaf whose focus is a Constructor with given class
    my sub _find_constructor($ctx, $class) {
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constructor
                    && $focus->class() eq $class) {
                return $focus;
            }
        }
        return undef;
    }

    # Helper: collect all IR values that are Constructors with given class
    my sub _collect_constructors($ctx, $class) {
        my @results;
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constructor
                    && $focus->class() eq $class) {
                push @results, $focus;
            }
        }
        return @results;
    }

    # Helper: find first Constant node in leaves
    my sub _find_constant($ctx) {
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::Bootstrap::IR::Node::Constant) {
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
            if ($focus isa Chalk::Bootstrap::IR::Node::Constant) {
                push @results, $focus;
            }
        }
        return @results;
    }

    # Helper: recursively collect all variable names referenced in a body stmts array.
    # Walks the IR tree to find Constant nodes with const_type='variable'.
    # Returns a hashref of variable name => 1 for each variable found.
    my $collect_body_var_refs;
    $collect_body_var_refs = sub ($stmts_or_node) {
        my %found;
        my %visited;
        my @queue;

        # Accept either an arrayref of statements or a single node
        if (ref $stmts_or_node eq 'ARRAY') {
            @queue = $stmts_or_node->@*;
        } elsif (defined $stmts_or_node) {
            @queue = ($stmts_or_node);
        }

        while (@queue) {
            my $node = shift @queue;
            next unless defined $node;
            next unless ref $node;
            next if $visited{refaddr($node)}++;

            if ($node isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $node->value()
                    && $node->const_type() eq 'variable') {
                $found{$node->value()} = 1;
            }

            # Recurse into inputs
            if ($node->can('inputs') && defined $node->inputs()) {
                for my $input ($node->inputs()->@*) {
                    next unless defined $input;
                    if (ref $input eq 'ARRAY') {
                        push @queue, $input->@*;
                    } else {
                        push @queue, $input;
                    }
                }
            }
        }

        return \%found;
    };

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
        return false unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
        return false unless $node->class() eq 'BuiltinCall';
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
    #   PostfixDeref(ReturnStmt(X), @) → ReturnStmt(PostfixDeref(X, @))
    #   PostfixDeref(BuiltinCall(scalar, [X]), @) → BuiltinCall(scalar, [PostfixDeref(X, @)])
    #   PostfixDeref(MethodCall(BuiltinCall(push, [A, B]), m, []), @)
    #     → BuiltinCall(push, [A, PostfixDeref(MethodCall(B, m, []), @)])
    my sub _push_deref_inward($factory, $target, $sigil_node) {
        # Collect wrappers to rewrap later
        my @wrappers;
        my $current = $target;
        while (defined $current && $current isa Chalk::Bootstrap::IR::Node::Constructor) {
            if ($current->class() eq 'ReturnStmt') {
                push @wrappers, ['ReturnStmt'];
                $current = $current->inputs()->[0];
            } elsif ($current->class() eq 'DieCall') {
                push @wrappers, ['DieCall', $current->inputs()->[0]];
                my $args = $current->inputs()->[0];
                $current = $args->[-1];
            } elsif (_is_unwrappable_builtin($current)) {
                push @wrappers, ['BuiltinCall', $current->inputs()->[0], $current->inputs()->[1]];
                my $args = $current->inputs()->[1];
                $current = $args->[-1];
            } elsif ($current->class() eq 'MethodCallExpr') {
                # MethodCall wrapping a prefix construct — peel it off
                push @wrappers, ['MethodCallExpr', $current->inputs()->[1], $current->inputs()->[2]];
                $current = $current->inputs()->[0];  # invocant
            } else {
                last;
            }
        }

        # Create deref at the innermost target
        my $result = $factory->make('Constructor',
            'class'  => 'PostfixDerefExpr',
            target => $current,
            sigil  => $sigil_node,
        );

        # Rewrap layers from inside out
        for my $wrapper (reverse @wrappers) {
            if ($wrapper->[0] eq 'ReturnStmt') {
                $result = $factory->make('Constructor',
                    'class' => 'ReturnStmt',
                    value   => $result,
                );
            } elsif ($wrapper->[0] eq 'DieCall') {
                my @args = ($wrapper->[1]->@*);
                $args[-1] = $result;
                $result = $factory->make('Constructor',
                    'class' => 'DieCall',
                    args    => \@args,
                );
            } elsif ($wrapper->[0] eq 'BuiltinCall') {
                my @args = ($wrapper->[2]->@*);
                $args[-1] = $result;
                $result = $factory->make('Constructor',
                    'class' => 'BuiltinCall',
                    name    => $wrapper->[1],
                    args    => \@args,
                );
            } elsif ($wrapper->[0] eq 'MethodCallExpr') {
                $result = $factory->make('Constructor',
                    'class'       => 'MethodCallExpr',
                    invocant    => $result,
                    method_name => $wrapper->[1],
                    args        => $wrapper->[2],
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
    my sub _push_methodcall_inward($factory, $invocant, $method_name, $args) {
        my @wrappers;
        my $current = $invocant;
        while (defined $current && $current isa Chalk::Bootstrap::IR::Node::Constructor) {
            if ($current->class() eq 'ReturnStmt') {
                push @wrappers, ['ReturnStmt'];
                $current = $current->inputs()->[0];
            } elsif ($current->class() eq 'DieCall') {
                push @wrappers, ['DieCall', $current->inputs()->[0]];
                my $die_args = $current->inputs()->[0];
                $current = $die_args->[-1];
            } elsif (_is_unwrappable_builtin($current)) {
                push @wrappers, ['BuiltinCall', $current->inputs()->[0], $current->inputs()->[1]];
                my $bi_args = $current->inputs()->[1];
                $current = $bi_args->[-1];
            } elsif ($current->class() eq 'PostfixDerefExpr') {
                # PostfixDeref wrapping target — peel off and rewrap outside
                push @wrappers, ['PostfixDerefExpr', $current->inputs()->[1]];
                $current = $current->inputs()->[0];  # target
            } else {
                last;
            }
        }

        # No wrappers found — return plain MethodCallExpr
        unless (@wrappers) {
            return $factory->make('Constructor',
                'class'       => 'MethodCallExpr',
                invocant    => $invocant,
                method_name => $method_name,
                args        => $args,
            );
        }

        # Create method call at the innermost invocant
        my $result = $factory->make('Constructor',
            'class'       => 'MethodCallExpr',
            invocant    => $current,
            method_name => $method_name,
            args        => $args,
        );

        # Rewrap layers from inside out
        for my $wrapper (reverse @wrappers) {
            if ($wrapper->[0] eq 'ReturnStmt') {
                $result = $factory->make('Constructor',
                    'class' => 'ReturnStmt',
                    value   => $result,
                );
            } elsif ($wrapper->[0] eq 'DieCall') {
                my @die_args = ($wrapper->[1]->@*);
                $die_args[-1] = $result;
                $result = $factory->make('Constructor',
                    'class' => 'DieCall',
                    args    => \@die_args,
                );
            } elsif ($wrapper->[0] eq 'BuiltinCall') {
                my @bi_args = ($wrapper->[2]->@*);
                $bi_args[-1] = $result;
                $result = $factory->make('Constructor',
                    'class' => 'BuiltinCall',
                    name    => $wrapper->[1],
                    args    => \@bi_args,
                );
            } elsif ($wrapper->[0] eq 'PostfixDerefExpr') {
                $result = $factory->make('Constructor',
                    'class'  => 'PostfixDerefExpr',
                    target => $result,
                    sigil  => $wrapper->[1],
                );
            }
        }

        return $result;
    }

    # Post-process: fix misparented postfix chains in the IR tree.
    # The Earley parser's stale-value merge can produce
    # MethodCallExpr(PostfixDerefExpr(X, S), M, A) when the correct
    # structure is PostfixDerefExpr(MethodCallExpr(X, M, A), S).
    # This walks the tree and swaps any such misparentings.
    sub _fix_postfix_chain {
        my ($factory, $node) = @_;
        return $node unless defined $node;
        return $node unless $node isa Chalk::Bootstrap::IR::Node::Constructor;

        # Recursively fix inputs first (bottom-up)
        my @new_inputs;
        my $changed = false;
        for my $inp ($node->inputs()->@*) {
            if (ref($inp) eq 'ARRAY') {
                my @fixed;
                for my $elem ($inp->@*) {
                    my $f = _fix_postfix_chain($factory, $elem);
                    push @fixed, $f;
                    $changed = true if !defined $f || !defined $elem || $f != $elem;
                }
                push @new_inputs, \@fixed;
            } else {
                my $f = _fix_postfix_chain($factory, $inp);
                push @new_inputs, $f;
                $changed = true if !defined $f || !defined $inp
                    || (ref($f) && ref($inp) && $f != $inp);
            }
        }

        if ($changed) {
            # Rebuild the node with fixed inputs
            if ($node->class() eq 'MethodCallExpr') {
                $node = $factory->make('Constructor',
                    'class'       => 'MethodCallExpr',
                    invocant    => $new_inputs[0],
                    method_name => $new_inputs[1],
                    args        => $new_inputs[2],
                );
            } elsif ($node->class() eq 'PostfixDerefExpr') {
                $node = $factory->make('Constructor',
                    'class'  => 'PostfixDerefExpr',
                    target => $new_inputs[0],
                    sigil  => $new_inputs[1],
                );
            } elsif ($node->class() eq 'BuiltinCall') {
                $node = $factory->make('Constructor',
                    'class' => 'BuiltinCall',
                    name    => $new_inputs[0],
                    args    => $new_inputs[1],
                );
            } elsif ($node->class() eq 'SubscriptExpr') {
                $node = $factory->make('Constructor',
                    'class'  => 'SubscriptExpr',
                    target => $new_inputs[0],
                    index  => $new_inputs[1],
                    style  => $new_inputs[2],
                );
            } elsif ($node->class() eq 'ReturnStmt') {
                $node = $factory->make('Constructor',
                    'class' => 'ReturnStmt',
                    value   => $new_inputs[0],
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
                    && $invocant isa Chalk::Bootstrap::IR::Node::Constructor
                    && $invocant->class() eq 'PostfixDerefExpr') {
                my $inner_target = $invocant->inputs()->[0];
                my $sigil = $invocant->inputs()->[1];
                my $new_method = $factory->make('Constructor',
                    'class'       => 'MethodCallExpr',
                    invocant    => $inner_target,
                    method_name => $node->inputs()->[1],
                    args        => $node->inputs()->[2],
                );
                return $factory->make('Constructor',
                    'class'  => 'PostfixDerefExpr',
                    target => $new_method,
                    sigil  => $sigil,
                );
            }
        }

        # Fix prefix builtin subscript chain misparenting:
        # SubscriptExpr(BuiltinCall(defined/exists/ref/etc, [$var]), $key, style)
        #   → BuiltinCall(defined/exists/ref/etc, [SubscriptExpr($var, $key, style)])
        # Also handles ReturnStmt wrapper from stale-value merge:
        # SubscriptExpr(ReturnStmt(BuiltinCall(..., [$var])), $key, style)
        #   → ReturnStmt(BuiltinCall(..., [SubscriptExpr($var, $key, style)]))
        if ($node->class() eq 'SubscriptExpr') {
            my $target = $node->inputs()->[0];
            my $builtin_call;
            my $wrapper_class;  # 'ReturnStmt' if wrapped, undef if direct

            if (defined $target && $target isa Chalk::Bootstrap::IR::Node::Constructor) {
                if ($target->class() eq 'BuiltinCall') {
                    $builtin_call = $target;
                } elsif ($target->class() eq 'ReturnStmt'
                        || $target->class() eq 'DieCall') {
                    my $inner = $target->inputs()->[0];
                    if (defined $inner
                            && $inner isa Chalk::Bootstrap::IR::Node::Constructor
                            && $inner->class() eq 'BuiltinCall') {
                        $builtin_call = $inner;
                        $wrapper_class = $target->class();
                    }
                }
            }

            if (defined $builtin_call) {
                my $bname = $builtin_call->inputs()->[0]->value();
                if ($PREFIX_BUILTINS{$bname}) {
                    my @args = $builtin_call->inputs()->[1]->@*;
                    my $inner_target = $args[-1];
                    $args[-1] = $factory->make('Constructor',
                        'class'  => 'SubscriptExpr',
                        target => $inner_target,
                        index  => $node->inputs()->[1],
                        style  => $node->inputs()->[2],
                    );
                    my $new_builtin = $factory->make('Constructor',
                        'class' => 'BuiltinCall',
                        name    => $builtin_call->inputs()->[0],
                        args    => \@args,
                    );
                    if (defined $wrapper_class) {
                        return $factory->make('Constructor',
                            'class' => $wrapper_class,
                            value   => $new_builtin,
                        );
                    }
                    return $new_builtin;
                }
            }

            # Fix subscript chain wrapping UnaryExpr from stale-value merge:
            # SubscriptExpr(UnaryExpr(op, X), $key, style)
            # → UnaryExpr(op, SubscriptExpr(X, $key, style))
            # The subscript belongs on the operand, not wrapping the negation.
            if (defined $target && $target isa Chalk::Bootstrap::IR::Node::Constructor
                    && $target->class() eq 'UnaryExpr') {
                my $operand = $target->inputs()->[1];
                my $new_operand = $factory->make('Constructor',
                    'class'  => 'SubscriptExpr',
                    target => $operand,
                    index  => $node->inputs()->[1],
                    style  => $node->inputs()->[2],
                );
                # Re-run fix to push deeper if needed
                $new_operand = _fix_postfix_chain($factory, $new_operand);
                return $factory->make('Constructor',
                    'class'    => 'UnaryExpr',
                    op       => $target->inputs()->[0],
                    operand  => $new_operand,
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
            if (defined $target && $target isa Chalk::Bootstrap::IR::Node::Constructor
                    && $target->class() eq 'BinaryExpr') {
                my $right = $target->inputs()->[2];
                my $new_right = $factory->make('Constructor',
                    'class'  => 'SubscriptExpr',
                    target => $right,
                    index  => $node->inputs()->[1],
                    style  => $node->inputs()->[2],
                );
                # Re-run fix on the new SubscriptExpr to push deeper if needed
                $new_right = _fix_postfix_chain($factory, $new_right);
                return $factory->make('Constructor',
                    'class'    => 'BinaryExpr',
                    op       => $target->inputs()->[0],
                    left     => $target->inputs()->[1],
                    right    => $new_right,
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
    $_fix_postfix_chain_deep = sub($f, $node) {
        return $node unless defined $node;
        return $node unless $node isa Chalk::Bootstrap::IR::Node::Constructor;

        # First, apply the top-level fix
        my $fixed = _fix_postfix_chain($f, $node);

        # If the top-level fix changed the node, recurse on the result
        return $_fix_postfix_chain_deep->($f, $fixed)
            if refaddr($fixed) != refaddr($node);

        # Otherwise, recurse into children
        my $class = $node->class();
        if ($class eq 'BinaryExpr') {
            my $left  = $_fix_postfix_chain_deep->($f, $node->inputs()->[1]);
            my $right = $_fix_postfix_chain_deep->($f, $node->inputs()->[2]);
            if (refaddr($left) != refaddr($node->inputs()->[1])
                || refaddr($right) != refaddr($node->inputs()->[2])) {
                return $f->make('Constructor',
                    'class' => 'BinaryExpr',
                    op    => $node->inputs()->[0],
                    left  => $left,
                    right => $right,
                );
            }
        } elsif ($class eq 'UnaryExpr') {
            my $operand = $_fix_postfix_chain_deep->($f, $node->inputs()->[1]);
            if (refaddr($operand) != refaddr($node->inputs()->[1])) {
                return $f->make('Constructor',
                    'class'   => 'UnaryExpr',
                    op      => $node->inputs()->[0],
                    operand => $operand,
                );
            }
        } elsif ($class eq 'BuiltinCall') {
            my @args = $node->inputs()->[1]->@*;
            my $changed = false;
            for my $i (0 .. $#args) {
                my $fixed_arg = $_fix_postfix_chain_deep->($f, $args[$i]);
                if (refaddr($fixed_arg) != refaddr($args[$i])) {
                    $args[$i] = $fixed_arg;
                    $changed = true;
                }
            }
            if ($changed) {
                return $f->make('Constructor',
                    'class' => 'BuiltinCall',
                    name  => $node->inputs()->[0],
                    args  => \@args,
                );
            }
        }

        return $node;
    };

    # Post-process statement list to fix grammar ambiguity artifacts.
    # The ambiguous grammar sometimes parses compound statements as
    # separate items. These fixups merge them back together:
    # - `return 'Start'` → ReturnStmt(Constant('Start'))
    # - `die "message"` → DieCall([Constant('message')])
    # - `use Foo 'bar'` (split) → UseDecl(Foo, ['bar'])
    my sub _fixup_stmts($factory, $stmts) {
        my @result;
        my $i = 0;
        while ($i <= $#$stmts) {
            my $item = $stmts->[$i];
            if ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'return'
                    && $i + 1 <= $#$stmts) {
                # Merge return + value into ReturnStmt
                $i++;
                my $value = $stmts->[$i];
                push @result, $factory->make('Constructor',
                    'class' => 'ReturnStmt',
                    value => $value,
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'return') {
                # Bare return; with no following value — emit ReturnStmt(undef)
                push @result, $factory->make('Constructor',
                    'class' => 'ReturnStmt',
                    value => _make_const($factory, 'undef'),
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'die'
                    && $i + 1 <= $#$stmts) {
                # Merge die + single argument into DieCall.
                # Consumes only one following node to avoid absorbing
                # unrelated statements in multi-statement bodies.
                $i++;
                push @result, $factory->make('Constructor',
                    'class' => 'DieCall',
                    args  => [$stmts->[$i]],
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'UseDecl'
                    && !defined $item->inputs()->[1]
                    && $i + 1 <= $#$stmts
                    && $stmts->[$i + 1] isa Chalk::Bootstrap::IR::Node::Constant) {
                # Merge UseDecl(module, undef) + bare Constant into
                # UseDecl(module, [Constant]). Grammar ambiguity sometimes
                # splits `use Foo 'bar'` into separate statements.
                my @import_args;
                while ($i + 1 <= $#$stmts
                        && $stmts->[$i + 1] isa Chalk::Bootstrap::IR::Node::Constant
                        && !($stmts->[$i + 1]->value() =~ /^[a-zA-Z_]/
                             && $i + 2 <= $#$stmts)) {
                    $i++;
                    push @import_args, $stmts->[$i];
                }
                if (@import_args) {
                    push @result, $factory->make('Constructor',
                        'class'       => 'UseDecl',
                        module_name => $item->inputs()->[0],
                        import_args => \@import_args,
                    );
                } else {
                    push @result, $item;
                }
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'BinaryExpr'
                    && $item->inputs()->[0]->value() eq '='
                    && $item->inputs()->[1] isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->inputs()->[1]->class() eq 'VarDecl'
                    && !defined $item->inputs()->[1]->inputs()->[1]) {
                # Merge BinaryExpr(=, VarDecl(var, undef), expr) → VarDecl(var, expr)
                my $var_decl = $item->inputs()->[1];
                push @result, $factory->make('Constructor',
                    'class'       => 'VarDecl',
                    variable    => $var_decl->inputs()->[0],
                    initializer => $item->inputs()->[2],
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'BinaryExpr'
                    && $item->inputs()->[1] isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->inputs()->[1]->class() eq 'BuiltinCall'
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
                my $new_last = $factory->make('Constructor',
                    'class' => 'BinaryExpr',
                    op      => $binop,
                    left    => $last_arg,
                    right   => $right,
                );
                push @args, $new_last;
                push @result, $factory->make('Constructor',
                    'class' => 'BuiltinCall',
                    name    => $name,
                    args    => \@args,
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'VarDecl'
                    && !defined $item->inputs()->[1]
                    && $i + 1 <= $#$stmts
                    && $stmts->[$i + 1] isa Chalk::Bootstrap::IR::Node) {
                # Merge bare VarDecl(var, undef) + following expression → VarDecl(var, expr)
                my $next = $stmts->[$i + 1];
                if (!(($next isa Chalk::Bootstrap::IR::Node::Constructor
                        && $STMT_BOUNDARY_CLASSES{$next->class()})
                    || ($next isa Chalk::Bootstrap::IR::Node
                        && $STMT_BOUNDARY_OPS{$next->operation() // ''}))) {
                    $i++;
                    push @result, $factory->make('Constructor',
                        'class'       => 'VarDecl',
                        variable    => $item->inputs()->[0],
                        initializer => $next,
                    );
                } else {
                    push @result, $item;
                }
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $LIST_BUILTINS{$item->value()}
                    && $i + 1 <= $#$stmts) {
                # Merge bare builtin keyword + following args → BuiltinCall
                my $builtin = $item->value();
                my @args;
                while ($i + 1 <= $#$stmts) {
                    my $next = $stmts->[$i + 1];
                    # Stop at statement-level constructs
                    last if $next isa Chalk::Bootstrap::IR::Node::Constructor
                        && $STMT_BOUNDARY_CLASSES{$next->class()};
                    # Stop at CFG control flow nodes
                    last if $next isa Chalk::Bootstrap::IR::Node
                        && $STMT_BOUNDARY_OPS{$next->operation() // ''};
                    # Stop at other bare builtins
                    last if $next isa Chalk::Bootstrap::IR::Node::Constant
                        && defined $next->value()
                        && $STOP_KEYWORDS{$next->value()};
                    # Nest PREFIX_BUILTIN inside LIST_BUILTIN: sort keys %$h → sort(keys(%$h))
                    if ($next isa Chalk::Bootstrap::IR::Node::Constant
                            && defined $next->value()
                            && $PREFIX_BUILTINS{$next->value()}
                            && $i + 2 <= $#$stmts) {
                        my $prefix_name = $next->value();
                        $i += 2;
                        my $prefix_arg = $stmts->[$i];
                        push @args, $factory->make('Constructor',
                            'class' => 'BuiltinCall',
                            name  => _make_const($factory, $prefix_name),
                            args  => [$prefix_arg],
                        );
                        next;
                    }
                    $i++;
                    push @args, $next;
                }
                push @result, $factory->make('Constructor',
                    'class' => 'BuiltinCall',
                    name  => _make_const($factory, $builtin),
                    args  => \@args,
                );
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $PREFIX_BUILTINS{$item->value()}
                    && $i + 1 <= $#$stmts) {
                # Merge bare prefix-builtin + following expression → BuiltinCall
                my $builtin = $item->value();
                $i++;
                my $arg = $stmts->[$i];
                push @result, $factory->make('Constructor',
                    'class' => 'BuiltinCall',
                    name  => _make_const($factory, $builtin),
                    args  => [$arg],
                );
            } else {
                push @result, $item;
            }
            $i++;
        }
        return \@result;
    }

    # §2 Program ::= _ StatementList? _
    # Collects all statement-level IR nodes into Constructor:Program.
    # Also performs Phi insertion for loop-carried variables: ForeachStatement
    # fires with a narrow scope and cannot see variables defined in sibling
    # statements. Program has the full merged scope and creates Phis here.
    method Program($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                # StatementList returns arrayref
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @stmts, $val;
            }
        }
        # Fix misparented postfix chains from Earley stale-value merge
        @stmts = map { _fix_postfix_chain($factory, $_) } @stmts;

        # Phi insertion for loop-carried variables.
        # Walk statements in order, tracking scope. When a Loop statement is
        # encountered, check if any variables in its body_var_refs were defined
        # before the loop. For those variables, create Phi nodes and update scope.
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $state = $sa->inherited_cfg_state($ctx);
            if (defined $state && defined $state->{scope}) {
                my $running_scope = $state->{scope};
                my $scope_changed = false;

                for my $stmt (@stmts) {
                    next unless defined $stmt;
                    next unless $stmt->operation() eq 'Loop';

                    my $loop_key = refaddr($stmt);
                    my $loop_info = $_loop_body_var_refs{$loop_key};
                    next unless defined $loop_info;

                    my $phi_vars            = $loop_info->{phi_vars};
                    my $body_final_bindings = $loop_info->{body_final_bindings};

                    for my $name (sort keys %$phi_vars) {
                        my $pre_value = $running_scope->lookup($name);
                        next unless defined $pre_value;

                        # Create Phi: pre_value at loop entry, backedge TBD
                        my $phi = $factory->make('Phi',
                            region => $stmt,
                            values => [$pre_value, undef],
                        );

                        # Wire backedge: if the variable was assigned in the body,
                        # use the post-body value; otherwise use the Phi itself
                        # (degenerate loop-carried dep for read-only variables).
                        my $backedge_val = $phi;
                        my $body_binding = $body_final_bindings->{$name};
                        if (defined $body_binding
                                && refaddr($body_binding) != refaddr($pre_value)) {
                            $backedge_val = $body_binding;
                        }
                        $phi->set_backedge($backedge_val);

                        $running_scope = $running_scope->define($name, $phi);
                        $scope_changed = true;
                    }

                    # Clean up side table entry (consumed, prevents refaddr reuse bugs)
                    delete $_loop_body_var_refs{$loop_key};
                }

                if ($scope_changed) {
                    $sa->update_cfg({
                        $state->%*,
                        scope => $running_scope,
                    });
                }
            }
        }

        return $factory->make('Constructor',
            'class'      => 'Program',
            statements => \@stmts,
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
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @stmts, $val;
            }
        }
        my $fixed = _fixup_stmts($factory, \@stmts);
        # Fix misparented postfix chains from Earley stale-value merge
        return [ map { _fix_postfix_chain($factory, $_) } $fixed->@* ];
    }

    # §2 StatementItem — collect all IR values for fixup in StatementList/Block
    method StatementItem($ctx) {
        my @values = _collect_ir_values($ctx);
        my @ir_nodes;
        for my $val (@values) {
            if ($val isa Chalk::Bootstrap::IR::Node) {
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
    method SimpleStatement($ctx) {
        my @values = _collect_ir_values($ctx);
        my @ir_nodes;
        for my $val (@values) {
            if ($val isa Chalk::Bootstrap::IR::Node) {
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
            return $val if $val isa Chalk::Bootstrap::IR::Node;
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
            if ($focus isa Chalk::Bootstrap::IR::Node) {
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

                        # Collect variable refs from the body expression so Program
                        # can create Phi nodes for loop-carried dependencies.
                        # Mirrors the same pattern as ForeachStatement.
                        my $loop      = $updated->{loop};
                        my $body_refs = $collect_body_var_refs->($body_expr);

                        # Collect post-body scope bindings for backedge wiring.
                        # Walk leaves of this context to find any scope updates
                        # that occurred while parsing the body expression.
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

                        $_loop_body_var_refs{refaddr($loop)} = {
                            phi_vars            => $body_refs,
                            body_final_bindings => \%body_final_bindings,
                        };
                    } elsif (defined $updated->{if_node}) {
                        # Detect loop jump keywords (next/last) as body:
                        # set loop_jump marker instead of then_stmts so
                        # targets emit 'next if/unless' instead of 'if { next }'.
                        # NOTE: The If CFG node lives in cfg_state metadata
                        # (keyed by the IR node's refaddr), not directly in
                        # body_stmts. _build_cfg_lookup resolves this at codegen
                        # time. Future GCM/DCE passes that walk only the IR tree
                        # (not cfg_state) will need to be extended to see it.
                        if ($body_expr isa Chalk::Bootstrap::IR::Node::Constant
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

    # §7 UseDeclaration ::= /use\b/ WS ModuleName
    #                      | /use\b/ WS ModuleName WS ImportList
    method UseDeclaration($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $module_name;
        my $import_args;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (defined $rule && $rule eq 'ModuleName'
                    && $focus isa Chalk::Bootstrap::IR::Node::Constant) {
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

        return $factory->make('Constructor',
            'class'       => 'UseDecl',
            module_name => $module_name,
            import_args => $import_args,
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
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
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

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant) {
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
                        if ($attr isa Chalk::Bootstrap::IR::Node::Constructor
                                && $attr->class() eq '_Attribute') {
                            my $attr_name = $attr->inputs()->[0];
                            if (defined $attr_name
                                    && $attr_name->value() eq 'isa') {
                                $parent = $attr->inputs()->[1];
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

        return $factory->make('Constructor',
            'class'  => 'ClassDecl',
            name   => $class_name,
            parent => $parent,
            body   => \@body,
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

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
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

        return $factory->make('Constructor',
            'class'       => 'MethodDecl',
            name          => $method_name,
            params        => \@params,
            body          => \@body,
            return_type   => $factory->make('Constant',
                                const_type => 'string', value => $return_type),
        );
    }

    # Detect stale-merge artifact: `return unless COND` mis-parsed as
    # ReturnStmt(value: ...BuiltinCall("unless",...)).
    # Walks the value tree looking for a BuiltinCall node whose name is
    # a postfix modifier keyword (unless/if/while/until/for/foreach).
    method _is_postfix_modifier_artifact($node, $keywords) {
        my @stack = ($node);
        while (@stack) {
            my $n = pop @stack;
            next unless defined $n;
            next unless $n isa Chalk::Bootstrap::IR::Node;
            if ($n isa Chalk::Bootstrap::IR::Node::Constructor
                    && $n->class() eq 'BuiltinCall') {
                my $name_node = $n->inputs()->[0];
                if (defined $name_node
                        && $name_node isa Chalk::Bootstrap::IR::Node::Constant
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

    # §9 SubroutineDefinition — compile sub declarations into SubDecl IR nodes.
    # Grammar: /sub\b/ WS QualifiedIdentifier _ Signature? _ Block
    #        | /(?:my|our|state)\b/ WS /sub\b/ WS QualifiedIdentifier _ Signature? _ Block
    # Produces SubDecl with same structure as MethodDecl: name, params, body.
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

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
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

        return $factory->make('Constructor',
            'class'  => 'SubDecl',
            name     => $sub_name,
            params   => \@params,
            body     => \@body,
            scope    => $factory->make('Constant',
                            const_type => 'string', value => $scope),
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
            } elsif ($focus isa Chalk::Bootstrap::IR::Node::Constant && !defined $catch_var) {
                # Constant node is the catch variable name
                $catch_var = $focus->value();
            } elsif (ref($focus) eq 'ARRAY' && defined $try_body) {
                # Second arrayref is catch_body (from Block)
                $catch_body = $focus;
            }
        }

        return undef unless defined $try_body;

        # Apply fixup to bodies
        $try_body = _fixup_stmts($factory, $try_body);
        $catch_body = _fixup_stmts($factory, $catch_body // []);
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
                my $try_node = $factory->make('Constructor',
                    'class'     => 'TryCatchStmt',
                    try_body    => $try_body,
                    catch_var   => $catch_var_const,
                    catch_body  => $catch_body,
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
    # Returns arrayref of _Attribute Constructor nodes
    method AttributeList($ctx) {
        my @attrs;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @attrs, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node::Constructor
                    && $val->class() eq '_Attribute') {
                push @attrs, $val;
            }
        }
        return \@attrs;
    }

    # §10 Attribute ::= /:/ _ QualifiedIdentifier | /:/ _ QualifiedIdentifier _ /\(/ _ QualifiedIdentifier _ /\)/
    # Returns _Attribute Constructor with name and optional value
    method Attribute($ctx) {
        my @constants = _collect_constants($ctx);
        my $attr_name = $constants[0];  # QualifiedIdentifier (attribute name)
        my $attr_value = $constants[1]; # QualifiedIdentifier (optional, e.g. parent in :isa(Parent))

        return $factory->make('Constructor',
            'class'  => '_Attribute',
            name   => $attr_name,
            parent => $attr_value, # reuse parent slot for attribute value
            body   => undef,       # unused
        );
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
            } elsif ($val isa Chalk::Bootstrap::IR::Node::Constant) {
                push @params, $val;
            }
        }
        return \@params;
    }

    # §11 SignatureParam — transparent
    method SignatureParam($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node::Constant;
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
            return $val if $val isa Chalk::Bootstrap::IR::Node;
        }
        return undef;
    }

    # §12 ExpressionList — collect into arrayref
    method ExpressionList($ctx) {
        my @items;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @items, $val->@*;
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @items, $val;
            }
        }
        return \@items;
    }

    # §13 Atom — transparent pass-through
    method Atom($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
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
            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
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

        # Collect argument values
        my @args;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();
            # Skip the function name itself
            next if $focus isa Chalk::Bootstrap::IR::Node::Constant
                && defined $rule
                && $rule eq 'QualifiedIdentifier'
                && defined $focus->value()
                && $focus->value() eq $func_name;

            if (ref($focus) eq 'ARRAY') {
                push @args, $focus->@*;
            } elsif ($focus isa Chalk::Bootstrap::IR::Node) {
                push @args, $focus;
            }
        }

        if (defined $func_name && $func_name eq 'return') {
            # return EXPR → ReturnStmt
            my $value = $args[0]; # single value for Tier A
            return $factory->make('Constructor',
                'class' => 'ReturnStmt',
                value => $value,
            );
        }

        if (defined $func_name && $func_name eq 'die') {
            # die EXPR → DieCall
            return $factory->make('Constructor',
                'class' => 'DieCall',
                args  => \@args,
            );
        }

        # Generic builtin or function call → BuiltinCall
        if (defined $func_name) {
            return $factory->make('Constructor',
                'class' => 'BuiltinCall',
                name  => _make_const($factory, $func_name),
                args  => \@args,
            );
        }

        return undef;
    }

    # §19 Literal — transparent pass-through
    method Literal($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            return $val if $val isa Chalk::Bootstrap::IR::Node;
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
                return $factory->make('Constructor',
                    'class' => 'InterpolatedString',
                    parts => \@parts,
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

    # §19 RegexLiteral — return as Constant
    method RegexLiteral($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
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
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @stmts, $val;
            }
        }
        my $fixed = _fixup_stmts($factory, \@stmts);
        # Fix misparented postfix chains from Earley stale-value merge
        return [ map { _fix_postfix_chain($factory, $_) } $fixed->@* ];
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

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $focus->value()
                    && $focus->value() =~ /^[\$\@\%]/) {
                # Variable name (starts with sigil)
                $var_name //= $focus;
            } elsif (ref($focus) eq 'ARRAY') {
                # AttributeList returns arrayref of _Attribute Constructors
                for my $attr ($focus->@*) {
                    if ($attr isa Chalk::Bootstrap::IR::Node::Constructor
                            && $attr->class() eq '_Attribute') {
                        push @attributes, $attr;
                    }
                }
            }
        }

        return undef unless defined $var_name;

        if ($is_field) {
            return $factory->make('Constructor',
                'class'         => 'FieldDecl',
                name          => $var_name,
                attributes    => \@attributes,
                default_value => undef,
            );
        }

        my $var_decl = $factory->make('Constructor',
            'class'       => 'VarDecl',
            variable    => $var_name,
            initializer => undef,
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
            return $val if $val isa Chalk::Bootstrap::IR::Node;
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
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @elements, $val;
            }
        }
        return $factory->make('Constructor',
            'class'    => 'ArrayRefExpr',
            elements => \@elements,
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
            } elsif ($val isa Chalk::Bootstrap::IR::Node) {
                push @pairs, $val;
            }
        }
        return $factory->make('Constructor',
            'class' => 'HashRefExpr',
            pairs => \@pairs,
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

        $body = _fixup_stmts($factory, $body // []);

        return $factory->make('Constructor',
            'class'  => 'AnonSubExpr',
            params => \@params,
            body   => $body,
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
        }

        my @values = _collect_ir_values($ctx);
        my $operand;
        for my $val (@values) {
            if ($val isa Chalk::Bootstrap::IR::Node) {
                $operand = $val;
                last;
            }
        }

        return undef unless defined $op && defined $operand;

        return $factory->make('Constructor',
            'class'   => 'UnaryExpr',
            op      => _make_const($factory, $op),
            operand => $operand,
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

            if (!defined $left && $focus isa Chalk::Bootstrap::IR::Node) {
                $left = $focus;
            } elsif (defined $left && !defined $op
                    && $focus isa Chalk::Bootstrap::IR::Node::Constant) {
                # BinaryOp returns a Constant with the operator
                $op = $focus;
            } elsif (defined $op && $focus isa Chalk::Bootstrap::IR::Node) {
                $right //= $focus;
            }
        }

        return undef unless defined $left && defined $op;

        my $op_val = $op->value();

        # Handle =~ with regex
        if ($op_val eq '=~' && defined $right
                && $right isa Chalk::Bootstrap::IR::Node::Constant
                && defined $right->value()) {
            my $pat = $right->value();
            if ($pat =~ m{^s/}) {
                # s/pat/repl/flags
                if ($pat =~ m{^s/((?:[^/\\]|\\.)*)/((?:[^/\\]|\\.)*)/([\w]*)$}) {
                    return $factory->make('Constructor',
                        'class'       => 'RegexSubst',
                        target      => $left,
                        pattern     => _make_const($factory, $1),
                        replacement => _make_const($factory, $2),
                        flags       => _make_const($factory, $3),
                    );
                }
            } else {
                # /pattern/flags or m/pattern/flags
                return $factory->make('Constructor',
                    'class'   => 'RegexMatch',
                    target  => $left,
                    pattern => $right,
                    flags   => _make_const($factory, ''),
                );
            }
        }

        return $factory->make('Constructor',
            'class' => 'BinaryExpr',
            op    => $op,
            left  => $left,
            right => $right,
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
            next unless $val isa Chalk::Bootstrap::IR::Node;
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
            if ($op isa Chalk::Bootstrap::IR::Node::Constructor) {
                if ($op->class() eq 'MethodCallExpr') {
                    # Set invocant to current result, pushing inward
                    # past any prefix wrappers from stale-value merge
                    $result = _push_methodcall_inward(
                        $factory, $result, $op->inputs()->[1], $op->inputs()->[2],
                    );
                } elsif ($op->class() eq 'SubscriptExpr') {
                    # Push subscript inside exists/delete BuiltinCall so the
                    # argument includes the full subscript chain:
                    #   SubscriptExpr(BuiltinCall(exists, [$chart]), $pos)
                    #   → BuiltinCall(exists, [SubscriptExpr($chart, $pos)])
                    if ($result isa Chalk::Bootstrap::IR::Node::Constructor
                            && $result->class() eq 'BuiltinCall') {
                        my $bname = $result->inputs()->[0]->value();
                        if ($bname eq 'exists' || $bname eq 'delete') {
                            my @args = $result->inputs()->[1]->@*;
                            my $inner_target = $args[-1];
                            $args[-1] = $factory->make('Constructor',
                                'class'  => 'SubscriptExpr',
                                target => $inner_target,
                                index  => $op->inputs()->[1],
                                style  => $op->inputs()->[2],
                            );
                            $result = $factory->make('Constructor',
                                'class' => 'BuiltinCall',
                                name    => $result->inputs()->[0],
                                args    => \@args,
                            );
                            next;
                        }
                    }
                    $result = $factory->make('Constructor',
                        'class'  => 'SubscriptExpr',
                        target => $result,
                        index  => $op->inputs()->[1],
                        style  => $op->inputs()->[2],
                    );
                } elsif ($op->class() eq 'PostfixDerefExpr') {
                    $result = $factory->make('Constructor',
                        'class'  => 'PostfixDerefExpr',
                        target => $result,
                        sigil  => $op->inputs()->[1],
                    );
                } else {
                    # Unknown postfix — return as-is
                    $result = $op;
                }
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
                    && $focus isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $rule
                    && $rule eq 'QualifiedIdentifier') {
                $method_name = $focus;
            } elsif (!defined $method_name
                    && $focus isa Chalk::Bootstrap::IR::Node) {
                # Leaves before QualifiedIdentifier are the invocant expression
                $invocant = $focus;
            } elsif (defined $method_name) {
                if (ref($focus) eq 'ARRAY') {
                    push @args, $focus->@*;
                } elsif ($focus isa Chalk::Bootstrap::IR::Node) {
                    push @args, $focus;
                }
            }
        }

        return undef unless defined $method_name;

        # Push MethodCall inward past prefix wrappers when the Earley
        # stale-value merge misparents a BuiltinCall as the invocant
        return _push_methodcall_inward($factory, $invocant, $method_name, \@args);
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
            if ($val isa Chalk::Bootstrap::IR::Node) {
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

        return $factory->make('Constructor',
            'class'  => 'SubscriptExpr',
            target => $target,
            index  => $index,
            style  => _make_const($factory, $style),
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
            if ($val isa Chalk::Bootstrap::IR::Node) {
                $target = $val;
                last;
            }
        }

        my $sigil_node = _make_const($factory, $sigil // '@');

        # When the Earley parser produces a stale-value merge, prefix
        # constructs (return, scalar, etc.) can end up as the target of
        # PostfixDeref instead of wrapping it. Recursively push the deref
        # inward past prefix wrappers until it reaches the actual target:
        #   PostfixDeref(ReturnStmt(X), @)
        #     → ReturnStmt(PostfixDeref(X, @))
        #   PostfixDeref(BuiltinCall(scalar, [X]), @)
        #     → BuiltinCall(scalar, [PostfixDeref(X, @)])
        #   PostfixDeref(ReturnStmt(BuiltinCall(scalar, [X])), @)
        #     → ReturnStmt(BuiltinCall(scalar, [PostfixDeref(X, @)]))
        return _push_deref_inward($factory, $target, $sigil_node);
    }

    # §16 PostfixIncDec — not in Tier A
    method PostfixIncDec($ctx) {
        return undef;
    }

    # §17 TernaryExpression ::= Expression _ /\?/ _ Expression _ /:/ _ Expression
    # Returns Constructor:TernaryExpr
    method TernaryExpression($ctx) {
        my @values = _collect_ir_values($ctx);
        my @ir_nodes;
        for my $val (@values) {
            if ($val isa Chalk::Bootstrap::IR::Node) {
                push @ir_nodes, $val;
            }
        }

        # Should have exactly 3 IR nodes: condition, true_expr, false_expr
        return undef unless @ir_nodes >= 3;

        return $factory->make('Constructor',
            'class'      => 'TernaryExpr',
            condition  => $ir_nodes[0],
            true_expr  => $ir_nodes[1],
            false_expr => $ir_nodes[2],
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

            if (!defined $target && $focus isa Chalk::Bootstrap::IR::Node) {
                $target = $focus;
            } elsif (defined $target && !defined $op
                    && $focus isa Chalk::Bootstrap::IR::Node::Constant) {
                $op = $focus;
            } elsif (defined $op && $focus isa Chalk::Bootstrap::IR::Node) {
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
            # FieldDecl target: set its default_value and return it
            if ($target isa Chalk::Bootstrap::IR::Node::Constructor
                    && $target->class() eq 'FieldDecl') {
                return $factory->make('Constructor',
                    'class'         => 'FieldDecl',
                    name          => $target->inputs()->[0],
                    attributes    => $target->inputs()->[1],
                    default_value => $value,
                );
            }
            # VarDecl target: set its initializer and return it
            if ($target isa Chalk::Bootstrap::IR::Node::Constructor
                    && $target->class() eq 'VarDecl') {
                my $result = $factory->make('Constructor',
                    'class'       => 'VarDecl',
                    variable    => $target->inputs()->[0],
                    initializer => $value,
                );
                my $var_name_node = $target->inputs()->[0];
                if ($var_name_node isa Chalk::Bootstrap::IR::Node::Constant
                        && defined $var_name_node->value()
                        && $var_name_node->value() =~ /^[\$\@\%]/) {
                    $update_scope->($var_name_node->value(), $result);
                }
                return $result;
            }
            # Plain assignment: Return as VarDecl if target is variable.
            if ($target isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $target->value()
                    && $target->value() =~ /^[\$\@\%]/) {
                my $result = $factory->make('Constructor',
                    'class'       => 'VarDecl',
                    variable    => $target,
                    initializer => $value,
                );
                $update_scope->($target->value(), $result);
                return $result;
            }
            # Otherwise binary expression for assignment
            return $factory->make('Constructor',
                'class' => 'BinaryExpr',
                op    => $op,
                left  => $target,
                right => $value,
            );
        }

        # Compound assignment (.=, //=, +=, etc.)
        my $compound_result = $factory->make('Constructor',
            'class'  => 'CompoundAssign',
            op     => $op,
            target => $target,
            value  => $value,
        );
        if ($target isa Chalk::Bootstrap::IR::Node::Constant
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
            if ($val isa Chalk::Bootstrap::IR::Node) {
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
            $condition = $_fix_postfix_chain_deep->($factory, $condition);
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
                        $loop_cond = $factory->make('Constructor',
                            'class'   => 'UnaryExpr',
                            op      => _make_const($factory, '!'),
                            operand => $loop_cond,
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
                        $cond = $factory->make('Constructor',
                            'class'   => 'UnaryExpr',
                            op      => _make_const($factory, '!'),
                            operand => $condition,
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

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if (!defined $condition && $focus isa Chalk::Bootstrap::IR::Node) {
                # First IR node is the condition (from ParenExpr)
                # Skip CFG If nodes from ElsifChain
                if ($focus isa Chalk::Bootstrap::IR::Node::If) {
                    $else_body = [$focus];
                    next;
                }
                $condition = $focus;
            } elsif (ref($focus) eq 'ARRAY' && !defined $then_body) {
                # First array is then_body (from Block)
                $then_body = $focus;
            } elsif (ref($focus) eq 'ARRAY' && defined $then_body) {
                # Second array is else_body (from else Block)
                $else_body = $focus;
            } elsif ($focus isa Chalk::Bootstrap::IR::Node::If) {
                # ElsifChain returns a CFG If node — wrap as else_body
                $else_body = [$focus];
            }
        }

        return undef unless defined $condition;

        # Apply fixup to bodies
        $then_body = _fixup_stmts($factory, $then_body // []);
        $else_body = defined $else_body ? _fixup_stmts($factory, $else_body) : undef;

        # For 'unless', wrap condition in UnaryExpr with '!'
        if (defined $keyword && $keyword eq 'unless') {
            $condition = $factory->make('Constructor',
                'class'   => 'UnaryExpr',
                op      => _make_const($factory, '!'),
                operand => $condition,
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

            if (!defined $condition && $focus isa Chalk::Bootstrap::IR::Node) {
                # Skip CFG If nodes from nested ElsifChain
                if ($focus isa Chalk::Bootstrap::IR::Node::If) {
                    $else_body = [$focus];
                    next;
                }
                $condition = $focus;
            } elsif (ref($focus) eq 'ARRAY' && !defined $then_body) {
                $then_body = $focus;
            } elsif (ref($focus) eq 'ARRAY' && defined $then_body) {
                $else_body = $focus;
            } elsif ($focus isa Chalk::Bootstrap::IR::Node::If) {
                # Nested ElsifChain returns a CFG If node
                $else_body = [$focus];
            }
        }

        return undef unless defined $condition;

        $then_body = _fixup_stmts($factory, $then_body // []);
        $else_body = defined $else_body ? _fixup_stmts($factory, $else_body) : undef;

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
                if ($focus isa Chalk::Bootstrap::IR::Node) {
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

        $body = _fixup_stmts($factory, $body // []);

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

                # Collect body variable references for Phi creation
                my $body_var_refs = $collect_body_var_refs->($body);

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

                $_loop_body_var_refs{refaddr($loop)} = {
                    phi_vars            => $body_var_refs,
                    body_final_bindings => \%body_final_bindings,
                };

                my $post_loop_scope = $pre_loop_scope;

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

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
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
            } elsif ($focus isa Chalk::Bootstrap::IR::Node && !defined $list
                    && defined $iterator) {
                $list = $focus;
            }
        }

        return undef unless defined $iterator;

        $body = _fixup_stmts($factory, $body // []);

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

                # Find which variables from the loop body were referenced.
                # The Earley parser is bottom-up: the body was already parsed before
                # ForeachStatement fires, so we cannot retroactively inject sentinels.
                # Instead, scan the body IR for Constant(variable, '$name') nodes
                # to find referenced variable names.
                my $body_var_refs = $collect_body_var_refs->($body);

                # Store body_var_refs keyed by loop refaddr so Program can create Phis.
                # ForeachStatement fires with a narrow scope (only the for-construct
                # subtree), but Program has the full merged scope from all sibling
                # statements and can create Phis with the correct pre-loop values.
                # Remove the iterator variable from body refs — it's defined by the loop.
                my %phi_vars = %$body_var_refs;
                delete $phi_vars{$iterator->value()} if defined $iterator;

                # Also collect post-body scope bindings for backedge wiring.
                # If a variable was assigned inside the loop body (e.g., $sum = $sum + $x),
                # the body leaf cfg_state will have a scope binding for it that differs
                # from the pre-loop value. Store these for Program to use as backedge values.
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

                $_loop_body_var_refs{refaddr($loop)} = {
                    phi_vars           => \%phi_vars,
                    body_final_bindings => \%body_final_bindings,
                };

                # The post-loop scope starts as the pre-loop scope (potentially empty
                # at this point). Program will augment this with Phi nodes.
                my $post_loop_scope = $pre_loop_scope;

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

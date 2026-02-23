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
my %STMT_BOUNDARY_CLASSES = map { $_ => 1 } qw(ClassDecl MethodDecl IfStmt ForeachLoop FieldDecl ReturnStmt DieCall);
my %STOP_KEYWORDS = map { $_ => 1 } qw(push unshift return die my for if unless while until);

class Chalk::Bootstrap::Perl::Actions {
    field $factory;

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

    # Helper: make a Constant IR node
    my sub _make_const($factory, $value) {
        return $factory->make('Constant', const_type => 'string', value => $value);
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

        return $node;
    }

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
                if (!($next isa Chalk::Bootstrap::IR::Node::Constructor
                        && $STMT_BOUNDARY_CLASSES{$next->class()})) {
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
                    # Stop at other bare builtins
                    last if $next isa Chalk::Bootstrap::IR::Node::Constant
                        && defined $next->value()
                        && $STOP_KEYWORDS{$next->value()};
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
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $item->value()
                    && $item->value() eq 'next'
                    && $i + 1 <= $#$stmts) {
                # Merge next + condition → NextUnless or PostfixLoop
                $i++;
                my $cond = $stmts->[$i];
                push @result, $factory->make('Constructor',
                    'class'     => 'NextUnless',
                    condition => $cond,
                );
            } else {
                push @result, $item;
            }
            $i++;
        }
        return \@result;
    }

    # §2 Program ::= _ StatementList? _
    # Collects all statement-level IR nodes into Constructor:Program
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
    method ExpressionStatement($ctx) {
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

        return $factory->make('Constructor',
            'class'  => 'MethodDecl',
            name   => $method_name,
            params => \@params,
            body   => \@body,
        );
    }

    # §9 SubroutineDefinition — pass through (for Tier A we skip sub definitions)
    method SubroutineDefinition($ctx) {
        return undef;
    }

    # §9 AdjustBlock — not in Tier A
    method AdjustBlock($ctx) {
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
        return _fixup_stmts($factory, \@stmts);
    }

    # §18 Variable — return variable name as Constant
    method Variable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 ScalarVariable — return as Constant with variable type
    method ScalarVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 ArrayVariable — return as Constant with variable type
    method ArrayVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return $factory->make('Constant', const_type => 'variable', value => $text);
    }

    # §18 HashVariable — return as Constant with variable type
    method HashVariable($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return $factory->make('Constant', const_type => 'variable', value => $text);
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
        my $style = ($text =~ /\[/) ? 'array' : 'hash';

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
                return $factory->make('Constructor',
                    'class'       => 'VarDecl',
                    variable    => $target->inputs()->[0],
                    initializer => $value,
                );
            }
            # Plain assignment: Return as VarDecl if target is variable.
            if ($target isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $target->value()
                    && $target->value() =~ /^[\$\@\%]/) {
                return $factory->make('Constructor',
                    'class'       => 'VarDecl',
                    variable    => $target,
                    initializer => $value,
                );
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
        return $factory->make('Constructor',
            'class'  => 'CompoundAssign',
            op     => $op,
            target => $target,
            value  => $value,
        );
    }

    # §17 AssignOp — returns operator as Constant
    method AssignOp($ctx) {
        my $text = $ctx->scanned_text();
        $text =~ s/^\s+|\s+$//g;
        return _make_const($factory, $text);
    }

    # §4 PostfixModifier ::= /(?:if|unless|while|until|for|foreach)\b/ _ Expression
    # Returns the modifier type and condition for the parent statement to handle
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

        return undef unless defined $keyword;

        # Return a hash-like structure the parent statement can use
        # For now, store as a special marker using Constant
        return $factory->make('Constructor',
            'class'     => 'PostfixLoop',
            body      => undef,  # set by parent
            modifier  => _make_const($factory, $keyword),
            condition => $condition,
        );
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
                $condition = $focus;
            } elsif (ref($focus) eq 'ARRAY' && !defined $then_body) {
                # First array is then_body (from Block)
                $then_body = $focus;
            } elsif (ref($focus) eq 'ARRAY' && defined $then_body) {
                # Second array is else_body (from else Block)
                $else_body = $focus;
            } elsif ($focus isa Chalk::Bootstrap::IR::Node::Constructor
                    && $focus->class() eq 'IfStmt') {
                # ElsifChain returns an IfStmt — wrap as else_body
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

        my $if_stmt = $factory->make('Constructor',
            'class'     => 'IfStmt',
            condition => $condition,
            then_body => $then_body,
            else_body => $else_body,
        );

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
                    control => $region,
                    scope   => $state->{scope},
                });
            }
        }

        return $if_stmt;
    }

    # §5 ElsifChain ::= /elsif\b/ _ ParenExpr _ Block
    #                  | /elsif\b/ _ ParenExpr _ Block _ ElsifChain
    #                  | /elsif\b/ _ ParenExpr _ Block _ /else\b/ _ Block
    # Returns an IfStmt (elsif is just a nested if)
    method ElsifChain($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $condition;
        my $then_body;
        my $else_body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();

            if (!defined $condition && $focus isa Chalk::Bootstrap::IR::Node) {
                $condition = $focus;
            } elsif (ref($focus) eq 'ARRAY' && !defined $then_body) {
                $then_body = $focus;
            } elsif (ref($focus) eq 'ARRAY' && defined $then_body) {
                $else_body = $focus;
            } elsif ($focus isa Chalk::Bootstrap::IR::Node::Constructor
                    && $focus->class() eq 'IfStmt') {
                $else_body = [$focus];
            }
        }

        return undef unless defined $condition;

        $then_body = _fixup_stmts($factory, $then_body // []);
        $else_body = defined $else_body ? _fixup_stmts($factory, $else_body) : undef;

        return $factory->make('Constructor',
            'class'     => 'IfStmt',
            condition => $condition,
            then_body => $then_body,
            else_body => $else_body,
        );
    }

    # §6 WhileStatement — not needed for Tier C (no while loops in these files)
    method WhileStatement($ctx) {
        return undef;
    }

    # §6 ForStatement — not needed for Tier C (C-style for loops)
    method ForStatement($ctx) {
        return undef;
    }

    # §6 ForeachStatement ::= /for(?:each)?\b/ _ IteratorVariable _ ParenExpr _ Block
    # Returns Constructor:ForeachLoop with iterator, list, and body
    method ForeachStatement($ctx) {
        my @leaves = _collect_ir_leaves($ctx);
        my $iterator;
        my $list;
        my $body;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if ($focus isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $focus->value()
                    && $focus->value() =~ /^[\$\@\%]/
                    && !defined $iterator) {
                $iterator = $focus;
            } elsif ($focus isa Chalk::Bootstrap::IR::Node && !defined $list
                    && defined $iterator) {
                $list = $focus;
            } elsif (ref($focus) eq 'ARRAY') {
                $body //= $focus;
            }
        }

        return undef unless defined $iterator;

        $body = _fixup_stmts($factory, $body // []);

        return $factory->make('Constructor',
            'class'    => 'ForeachLoop',
            iterator => $iterator,
            list     => $list,
            body     => $body,
        );
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

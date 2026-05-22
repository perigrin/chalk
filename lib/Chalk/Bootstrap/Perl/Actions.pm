# ABOUTME: Semantic actions for Perl grammar that build Perl IR nodes from parse results.
# ABOUTME: One method per grammar rule, constructing ClassInfo/MethodInfo/SubInfo/etc.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Assign;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::If;
use Chalk::IR::Node::Loop;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::Node::ExpressionList;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Program;

# Builtin keyword sets used by StatementItem
my %LIST_BUILTINS = map { $_ => 1 } qw(push unshift pop shift splice print say warn sort reverse chomp chop);

# Operator-to-typed-node translation tables used by BinaryExpression
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
    '&.'  => 'BitAnd',     '|.'  => 'BitOr',      '^.'  => 'BitXor',
    '^^'  => 'Xor',
    '<<'  => 'LeftShift',  '>>'  => 'RightShift',
    '='   => 'Assign',
    'x'   => 'Repeat',
    '=~'  => 'Match',      '!~'  => 'NotMatch',
    '//'  => 'DefinedOr',
    'xor' => 'Xor',
    '..'  => 'Range',
    # '...' in binary-expression context is the flip-flop range operator, not
    # the yada-yada placeholder (which is a bare statement, not a binary op).
    # Both '..' and '...' produce Range nodes; the '..' vs '...' semantic
    # distinction (lazy flip-flop vs eager range) is elided in the IR for now.
    '...' => 'Range',
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
        # Phase 7d Step 3: $factory and $typed both point at the same
        # per-Actions typed factory. The Bootstrap singleton is no
        # longer consulted by production action methods. With Step 1
        # injecting $typed into SemanticAction's _one_ctx, every code
        # path (action $factory, action $typed, $ctx->factory) sees
        # the SAME factory instance. This is the unification fix the
        # Earley identity audit recommended.
        $typed   = Chalk::IR::NodeFactory->new();
        $factory = $typed;
        Chalk::Bootstrap::Semiring::SemanticAction::set_factory($typed);
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

    # Helper: extract statement arrayref from a Block focus.
    # Block's new (Phase 3a-migration) focus is a hashref { stmts, graph, type }.
    # Legacy callers received an arrayref; this helper normalizes both shapes
    # so downstream actions can work with a uniform list of body statements.
    my sub _block_stmts($focus) {
        if (ref($focus) eq 'HASH' && exists $focus->{stmts}) {
            return $focus->{stmts};
        }
        if (ref($focus) eq 'ARRAY') {
            return $focus;
        }
        return undef;
    }

    # Helper: classify an IR value node into a Chalk type name for Block's
    # exit-type-union computation. Maps Constant.const_type for literals;
    # everything else defaults to 'Any'.
    #
    # Note: NumericLiteral currently produces Constants with const_type
    # 'string' (the literal text is preserved). Inspect the value to
    # distinguish numeric literals from quoted strings until NumericLiteral
    # is updated to tag them as 'integer'/'float'.
    my sub _classify_value_type($node) {
        return 'Any' unless defined $node && blessed($node);
        if ($node isa Chalk::IR::Node::Constant) {
            my $ct = $node->const_type();
            return 'Int'   if $ct eq 'integer' || $ct eq 'number';
            return 'Num'   if $ct eq 'float';
            return 'Regex' if $ct eq 'regex';
            if ($ct eq 'string') {
                my $v = $node->value();
                if (defined $v) {
                    return 'Int' if $v =~ /^[+-]?\d+$/;
                    return 'Num' if $v =~ /^[+-]?\d*\.\d+(?:[eE][+-]?\d+)?$/
                        || $v =~ /^[+-]?\d+[eE][+-]?\d+$/;
                }
                return 'Str';
            }
            return 'Any';
        }
        return 'Any';
    }

    # Helper: get the effective scope from a Context.
    # Reads the $scope field directly; returns undef if no scope is set.
    my sub _ctx_scope($ctx) {
        return $ctx->scope();
    }

    # Helper: get the control node from a Context's scope, or undef.
    my sub _ctx_control($ctx) {
        my $scope = $ctx->scope();
        return defined $scope ? $scope->control() : undef;
    }

    # Helper: resolve a variable name from scope, creating a Phi if needed.
    # Returns the resolved IR node if the variable is in scope (regular or sentinel),
    # or undef if no scope is active or the variable is not bound.
    # When a sentinel is resolved to a Phi, updates the scope via update_scope.
    my sub _resolve_from_scope($ctx, $sa, $var_name, $factory) {
        return undef unless defined $sa;
        my $scope = _ctx_scope($ctx);
        return undef unless defined $scope;
        my ($value, $new_scope) = $scope->resolve_sentinel($var_name, $factory);
        return undef unless defined $value;
        if ($new_scope) {
            # Preserve control when updating scope after sentinel resolution
            $new_scope = $new_scope->with_control($scope->control()) if defined $scope->control();
            $sa->update_scope($new_scope);
        }
        return $value;
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

        # Register top-level subs on the MOP's main class.
        # These are SubInfo objects that appear at program scope (not inside a ClassBlock).
        # ClassBlock separately registers in-class subs on the declared class.
        # current_mop() is used instead of $ctx->mop() because intermediate
        # multiply contexts do not propagate the mop field.
        my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
        if (defined $mop) {
            my $main = $mop->for_class('main');
            if (defined $main) {
                for my $use (@use_decls) {
                    $main->declare_import($use->name(),
                        args => [$use->args->@*],
                    );
                }
                for my $sub (@top_level_subs) {
                    $main->declare_sub($sub->name(),
                        params => $sub->params(),
                    );
                }
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
                     || $val isa Chalk::IR::SubInfo
                     || (ref($val) eq 'HASH' && (exists $val->{__adjust_body} || exists $val->{__phaser_block}))) {
                push @stmts, $val;
            }
        }
        return \@stmts;
    }

    # §2 StatementItem — collect all IR values for fixup in StatementList/Block.
    # When an ExpressionList node arrives at statement context and its first
    # item is a bare list-builtin call, the remaining items are the call's
    # arguments — merge them into that call rather than emitting N siblings.
    # This is the statement-level "reification" that prevents fragmentation
    # of `push @arr, EXPR` into separate IR nodes.
    method StatementItem($ctx) {
        my @values = _collect_ir_values($ctx);
        my @ir_nodes;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node::ExpressionList) {
                # Reify: check if items[0] is a bare list-builtin call
                my $items = $val->items();
                my $first = $items->[0];
                if (defined $first
                        && $first isa Chalk::IR::Node::Call
                        && $first->dispatch_kind() eq 'builtin'
                        && !$first->paren_form()
                        && $LIST_BUILTINS{$first->name()}) {
                    # Merge remaining items into the list-builtin's args
                    my @merged_args = ($first->inputs()->[1]->@*, $items->@[1..$items->$#*]);
                    my $name_node = $first->inputs()->[0];
                    push @ir_nodes, $ctx->factory->make('Call',
                        dispatch_kind => 'builtin',
                        name          => $name_node->value(),
                        paren_form    => false,
                        inputs        => [$name_node, \@merged_args],
                    );
                } else {
                    # No list-builtin merge — push each item as its own statement
                    push @ir_nodes, $items->@*;
                }
            } elsif ($val isa Chalk::IR::Node
                    || $val isa Chalk::IR::UseInfo
                    || $val isa Chalk::IR::ClassInfo
                    || $val isa Chalk::IR::FieldInfo
                    || $val isa Chalk::IR::MethodInfo
                    || $val isa Chalk::IR::SubInfo
                    || (ref($val) eq 'HASH' && (exists $val->{__adjust_body} || exists $val->{__phaser_block}))) {
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
        # Retrieve the current control token from scope for CFG edge.
        # Fall back to a fresh Start node when no scope is available
        # (e.g., in tests or early-parse contexts without scope tracking).
        my $control = _ctx_control($ctx) // $factory->make('Start');
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

        # Wire body expression into PostfixModifier's annotations.
        # Structural cfg data (loop, if_node, etc.) is on the PostfixModifier leaf
        # context's annotations — not on the outer ExpressionStatement context,
        # since _mul_ctx does not propagate individual annotation keys through
        # the multiply chain. Read annotations from postfix_leaf directly.
        if (defined $postfix_leaf && defined $body_expr) {
            my $postfix_node = $postfix_leaf->extract();
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            if (defined $sa) {
                my $ann = $postfix_leaf->annotations();
                if (defined $ann && (defined $ann->{loop} || defined $ann->{if_node})) {
                    my $scope = _ctx_scope($ctx);
                    if (defined $ann->{loop}) {
                        # Collect post-body scope bindings for Phi backedge wiring.
                        # Walk leaves of this context to find any scope updates
                        # that occurred while parsing the body expression.
                        my $loop = $ann->{loop};
                        my %body_final_bindings;
                        for my $leaf (_collect_ir_leaves($ctx)) {
                            my $leaf_scope = _ctx_scope($leaf);
                            if (defined $leaf_scope) {
                                for my $name ($leaf_scope->variable_names()) {
                                    my $binding = $leaf_scope->lookup($name);
                                    $body_final_bindings{$name} = $binding if defined $binding;
                                }
                            }
                        }

                        # Create Phi nodes for loop-carried variables directly here.
                        # Postfix loops have no iterator variable, so pass undef.
                        my $new_scope = $scope;
                        if (defined $scope) {
                            $new_scope = $scope->merge_for_loop(
                                \%body_final_bindings, $loop, $factory, undef,
                            );
                        }
                        $sa->update_scope($new_scope) if defined $new_scope;
                        $sa->update_annotations({ body_stmts => [$body_expr] });
                    } elsif (defined $ann->{if_node}) {
                        # Detect loop jump keywords (next/last) as body:
                        # set loop_jump marker instead of then_stmts so
                        # targets emit 'next if/unless' instead of 'if { next }'.
                        # NOTE: The If CFG node lives in annotation metadata
                        # (keyed by the IR node's refaddr), not directly in
                        # body_stmts. _build_cfg_lookup resolves this at codegen
                        # time. Future GCM/DCE passes that walk only the IR tree
                        # (not annotations) will need to be extended to see it.
                        if ($body_expr isa Chalk::IR::Node::Constant
                                && defined $body_expr->value()
                                && ($body_expr->value() eq 'next'
                                    || $body_expr->value() eq 'last')) {
                            $sa->update_annotations({ loop_jump => $body_expr->value() });
                        } else {
                            $sa->update_annotations({ then_stmts => [$body_expr] });
                        }
                    }
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
            if ($val isa Chalk::IR::Node::ExpressionList) {
                push @imports, $val->items()->@*;
            } elsif (ref($val) eq 'ARRAY') {
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
            } elsif (defined $rule && $rule eq 'Block') {
                # Block returns { stmts, graph, type }; extract stmts.
                my $stmts = _block_stmts($focus);
                @body = $stmts->@* if defined $stmts;
            } elsif (ref($focus) eq 'ARRAY') {
                if (defined $rule && $rule eq 'AttributeList') {
                    # AttributeList returns arrayref of attribute data
                    # Look for :isa(Parent) -> parent name Constant
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

        # Populate MOP with the class and its members when a MOP is present.
        # current_mop() is used instead of $ctx->mop() because intermediate
        # multiply contexts do not propagate the mop field.
        my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
        if (defined $mop) {
            my $superclass_obj = defined $parent_str
                ? $mop->for_class($parent_str)
                : undef;
            my $mop_class = $mop->declare_class($name_str,
                (defined $superclass_obj ? (superclass => $superclass_obj) : ()),
                (defined $parent_str ? (parent_name => $parent_str) : ()),
            );

            for my $item (@body) {
                if ($item isa Chalk::IR::FieldInfo) {
                    my $sigil = substr($item->name(), 0, 1);
                    # Extract :param name and build attribute string list from FieldInfo.
                    # FieldInfo attributes are hashrefs with {name, value}.
                    my $param_name = undef;
                    my @attr_list;
                    for my $attr ($item->attributes()->@*) {
                        if (ref($attr) eq 'HASH' && defined $attr->{name}) {
                            push @attr_list, ":$attr->{name}";
                            if ($attr->{name} eq 'param') {
                                $param_name = $attr->{value} // substr($item->name(), 1);
                            }
                        }
                    }
                    my $default_value = $item->default_value();
                    $mop_class->declare_field($item->name(),
                        sigil       => $sigil,
                        param_name  => $param_name,
                        attributes  => \@attr_list,
                        (defined $default_value
                            ? (default_value => $default_value,
                               has_default   => true)
                            : ()),
                    );
                } elsif ($item isa Chalk::IR::MethodInfo) {
                    my @bindings = grep {
                        blessed($_) && $_ isa Chalk::IR::Node::VarDecl
                    } $item->body->@*;
                    $mop_class->declare_method($item->name(),
                        params      => $item->params(),
                        return_type => $item->return_type(),
                        body        => $item->body(),
                        (defined $item->graph()
                            ? (graph => $item->graph())
                            : ()),
                        lexical_bindings => \@bindings,
                    );
                } elsif ($item isa Chalk::IR::SubInfo) {
                    $mop_class->declare_sub($item->name(),
                        params => $item->params(),
                        body   => $item->body(),
                        (defined $item->graph()
                            ? (graph => $item->graph())
                            : ()),
                    );
                } elsif ($item isa Chalk::IR::UseInfo) {
                    $mop_class->declare_import($item->name(),
                        args => [$item->args->@*],
                    );
                } elsif (ref($item) eq 'HASH' && exists $item->{__adjust_body}) {
                    $mop_class->declare_adjust();
                }
                # __phaser_block markers in class body intentionally ignored —
                # full phaser MOP integration deferred. The PhaserBlock is
                # captured as a marker so parse succeeds; codegen drops it.
            }

            # Phase 4 post-pass: now that every method in this class is
            # registered on the MOP, walk each method's graph for Call
            # nodes whose target is still undef and resolve them via
            # $mop->find_method. Catches same-class self-calls that
            # MethodCall couldn't resolve earlier (bottom-up order has
            # the inner action firing before the outer ClassBlock).
            for my $method ($mop_class->methods) {
                my $graph = $method->graph;
                next unless defined $graph;
                for my $n ($graph->nodes->@*) {
                    next unless blessed($n) && $n isa Chalk::IR::Node::Call;
                    next if defined $n->target;
                    next unless $n->dispatch_kind eq 'method';
                    my $resolved = $mop->find_method($n->name);
                    $n->set_target($resolved) if defined $resolved;
                }
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
        my $body_graph;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule();

            if ($focus isa Chalk::IR::Node::Constant
                    && !defined $method_name) {
                $method_name = $focus;
            } elsif (defined $rule && $rule eq 'Block') {
                my $stmts = _block_stmts($focus);
                @body = $stmts->@* if defined $stmts;
                if (ref($focus) eq 'HASH' && defined $focus->{graph}) {
                    $body_graph = $focus->{graph};
                }
            } elsif (ref($focus) eq 'ARRAY') {
                if (defined $rule && ($rule eq 'Signature'
                        || $rule eq 'SignatureParams')) {
                    @params = $focus->@*;
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

        my $fixed_body = \@body;

        my $method_name_val = defined $method_name ? $method_name->value() : '<unknown>';
        my @param_strs = map { $_->value() } @params;

        # Block synthesized the data-flow graph; finalize it with
        # schedule annotations, fall-through Return synthesis, and
        # control-flow inner-body seeding for codegen.
        my $graph = $self->_finalize_body_graph($ctx, $fixed_body, $body_graph);

        return Chalk::IR::MethodInfo->new(
            name        => $method_name_val,
            params      => \@param_strs,
            return_type => $return_type,
            body        => $fixed_body,
            graph       => $graph,
        );
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
        my $body_graph;

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
            } elsif (defined $rule && $rule eq 'Block') {
                my $stmts = _block_stmts($focus);
                @body = $stmts->@* if defined $stmts;
                if (ref($focus) eq 'HASH' && defined $focus->{graph}) {
                    $body_graph = $focus->{graph};
                }
            } elsif (ref($focus) eq 'ARRAY') {
                if (defined $rule && ($rule eq 'Signature'
                        || $rule eq 'SignatureParams')) {
                    @params = $focus->@*;
                } else {
                    if (!@body) {
                        @body = $focus->@*;
                    }
                }
            }
        }

        # If we couldn't find the sub name, skip this node
        return unless defined $sub_name;

        my $fixed_body = \@body;

        my $sub_name_val = $sub_name->value();
        my @param_strs = map { $_->value() } @params;

        my $graph = $self->_finalize_body_graph($ctx, $fixed_body, $body_graph);

        return Chalk::IR::SubInfo->new(
            name   => $sub_name_val,
            params => \@param_strs,
            body   => $fixed_body,
            scope  => $scope,
            graph  => $graph,
        );
    }

    # Finalize a method/sub body graph: walk the Context subtree to collect
    # control-flow annotations (if_node, loop, try_node) into the graph's
    # schedule, synthesize an implicit Return on fall-through bodies, and
    # seed any control-flow inner-body statements into the cache for codegen.
    #
    # Block already synthesizes the data-flow graph via merge() calls from
    # inner VariableDeclaration / AssignmentExpression actions, so this
    # helper does NOT (and must not) re-seed Start - the graph's own
    # start() accessor finds it via cache scan.
    method _finalize_body_graph($ctx, $fixed_body, $body_graph) {
        my $graph = $body_graph // Chalk::IR::Graph->new;

        # Collect structural annotation entries into the graph's schedule.
        # Codegen (Perl/Target/Perl.pm:_emit_method_decl) consumes this to
        # populate %_cfg_lookup for if/loop/try emission.
        my $schedule = $graph->schedule();
        my @stack = ($ctx);
        while (@stack) {
            my $c = pop @stack;
            my $ann = $c->annotations();
            if (defined $ann
                    && (defined $ann->{if_node}
                        || defined $ann->{loop}
                        || defined $ann->{try_node})) {
                my $ir_node = $c->extract();
                if (defined $ir_node && ref($ir_node)) {
                    $schedule->{refaddr($ir_node)} = $ann;
                }
                if (defined $ann->{try_node} && ref($ann->{try_node})) {
                    $schedule->{refaddr($ann->{try_node})} = $ann;
                }
            }
            push @stack, reverse $c->children()->@*;
        }

        # Collect explicit Return/Unwind nodes from the body.
        my @returns;
        for my $stmt ($fixed_body->@*) {
            if ($stmt isa Chalk::IR::Node::Return
                    || $stmt isa Chalk::IR::Node::Unwind) {
                push @returns, $stmt;
            }
        }

        # Perl's implicit-return semantics: when no explicit Return/Unwind
        # was found and the body is non-empty, the last expression is the
        # implicit return value. Wrap it in a Return CFG node so the graph
        # is always properly terminated. Use the last side-effect node as
        # the Return's control predecessor (the chain tail).
        if (!@returns && $fixed_body->@*) {
            my $last = $fixed_body->[-1];
            if (ref($last) && blessed($last) && $last->isa('Chalk::IR::Node')) {
                my $return_ctrl = $graph->start() // $factory->make('Start');
                for my $stmt (reverse $fixed_body->@*) {
                    next unless ref($stmt) && blessed($stmt)
                        && $stmt->isa('Chalk::IR::Node');
                    if ($stmt isa Chalk::IR::Node::VarDecl) {
                        $return_ctrl = $stmt;
                        last;
                    }
                }
                my $implicit_return = $factory->make_cfg('Return',
                    inputs    => [$return_ctrl, $last],
                    synthetic => true,
                );
                push @returns, $implicit_return;
            }
        }

        # Seed Returns + control-flow inner-body statements so codegen can
        # reach them. The Block fixup already merged the data-flow chain;
        # this adds nodes that the schedule annotations reference but the
        # main chain doesn't (then_stmts/else_stmts/loop bodies).
        #
        # Phase 7b Stage 1: transitively seed everything reachable from
        # these roots via inputs(). The graph's %cache becomes the
        # complete set of IR nodes for this body; foreign or orphan
        # nodes built through the singleton factory but never reached
        # from this body's roots stay out. This is what enables safe
        # bidirectional traversal in Graph::nodes() — consumer pointers
        # may cross graph boundaries, but cache-membership filtering
        # keeps the result graph-local.
        my @seeds = @returns;
        for my $state (values $schedule->%*) {
            for my $key (qw(then_stmts else_stmts statements body_stmts)) {
                next unless defined $state->{$key}
                    && ref($state->{$key}) eq 'ARRAY';
                push @seeds, $state->{$key}->@*;
            }
            # CFG nodes the annotation points to (the If/Loop/Try itself
            # and its surrounding Region/Proj structure) are seed roots
            # even if no body data-flow reaches them.
            for my $key (qw(if_node loop try_node region
                             body_proj exit_proj true_proj false_proj
                             loop_if exit_ctrl)) {
                push @seeds, $state->{$key} if defined $state->{$key};
            }
        }

        my %seen;
        my @worklist = grep { defined $_ && ref($_) && blessed($_)
                              && $_->isa('Chalk::IR::Node') } @seeds;
        while (my $n = shift @worklist) {
            next if $seen{$n->id}++;
            $graph->_seed($n);
            for my $input ($n->inputs->@*) {
                if (ref($input) eq 'ARRAY') {
                    for my $el ($input->@*) {
                        next unless defined $el && blessed($el)
                            && $el->isa('Chalk::IR::Node');
                        push @worklist, $el;
                    }
                    next;
                }
                next unless defined $input && blessed($input)
                    && $input->isa('Chalk::IR::Node');
                push @worklist, $input;
            }
        }

        return $graph;
    }

    # §9 AdjustBlock ::= /ADJUST\b/ _ Block
    # Returns a hashref marker so ClassBlock can identify and register ADJUST blocks.
    method AdjustBlock($ctx) {
        my @body;
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            my $stmts = _block_stmts($focus);
            if (defined $stmts) {
                @body = $stmts->@*;
            }
        }

        return { __adjust_body => \@body };
    }

    # §9 PhaserBlock ::= /(?:BEGIN|END|INIT|CHECK|UNITCHECK)\b/ _ Block
    # Phaser blocks are runtime-side-effect constructs (Perl phase hooks).
    # Captured as a marker for now; full phaser-IR integration deferred.
    # Returning the marker rather than undef so StatementItem can include
    # it (matches AdjustBlock pattern).
    method PhaserBlock($ctx) {
        my $name;
        my @body;
        my $text = $ctx->scanned_text() // '';
        if ($text =~ /^(BEGIN|END|INIT|CHECK|UNITCHECK)\b/) {
            $name = $1;
        }
        for my $leaf (_collect_ir_leaves($ctx)) {
            my $focus = $leaf->extract();
            my $stmts = _block_stmts($focus);
            if (defined $stmts) {
                @body = $stmts->@*;
            }
        }
        return { __phaser_block => { name => $name, body => \@body } };
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
            my $rule = $leaf->rule();

            # Block leaves are the try and catch bodies (in source order).
            if (defined $rule && $rule eq 'Block') {
                my $stmts = _block_stmts($focus);
                if (defined $stmts) {
                    if (!defined $try_body) {
                        $try_body = $stmts;
                    } else {
                        $catch_body = $stmts;
                    }
                }
            } elsif (ref($focus) eq 'ARRAY' && !defined $try_body) {
                $try_body = $focus;
            } elsif ($focus isa Chalk::IR::Node::Constant && !defined $catch_var) {
                # Constant node is the catch variable name
                $catch_var = $focus->value();
            } elsif (ref($focus) eq 'ARRAY' && defined $try_body) {
                $catch_body = $focus;
            }
        }

        return undef unless defined $try_body;

        $catch_body //= [];
        $catch_var //= '$_';

        # Build annotation entry with try_node key (same pattern as IfStatement)
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $scope = _ctx_scope($ctx);
            if (defined $scope) {
                my $catch_var_const = $factory->make('Constant',
                    const_type => 'variable',
                    value      => $catch_var,
                );
                my $try_node = $ctx->factory->make('TryCatch',
                    inputs       => [$try_body, $catch_var_const, $catch_body],
                );

                $sa->update_annotations({
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

    # §12 ExpressionList — collect items into a first-class ExpressionList IR node.
    # Previously returned a plain arrayref; now returns an IR node so
    # statement-context callers receive ONE value instead of N siblings.
    # Consumers that need the raw list call ->items() on the node.
    method ExpressionList($ctx) {
        my @items;
        for my $val (_collect_ir_values($ctx)) {
            if ($val isa Chalk::IR::Node::ExpressionList) {
                push @items, $val->items()->@*;
            } elsif (ref($val) eq 'ARRAY') {
                push @items, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @items, $val;
            }
        }
        return $ctx->factory->make('ExpressionList',
            inputs       => [\@items],
        );
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
                my $stmts = _block_stmts($focus);
                my @body = defined $stmts
                    ? $stmts->@*
                    : (defined $focus && !ref($focus) ? ($focus) : ());
                my $block_node = $ctx->factory->make('AnonSub',
                    inputs       => [[], \@body],
                );
                unshift @args, $block_node;
                $has_block = true;
                next;
            }

            if ($focus isa Chalk::IR::Node::ExpressionList) {
                push @args, $focus->items()->@*;
            } elsif (ref($focus) eq 'ARRAY') {
                push @args, $focus->@*;
            } elsif ($focus isa Chalk::IR::Node) {
                push @args, $focus;
            }
        }

        if (defined $func_name && $func_name eq 'return') {
            # return EXPR → Return CFG node
            my $value   = $args[0]; # single value for Tier A
            my $control = _ctx_control($ctx) // $factory->make('Start');
            return $factory->make_cfg('Return',
                inputs => [$control, $value],
            );
        }

        if (defined $func_name && $func_name eq 'die') {
            # die EXPR → Unwind CFG node (exceptional exit)
            my $control = _ctx_control($ctx) // $factory->make('Start');
            return $factory->make_cfg('Unwind',
                inputs => [$control, \@args],
            );
        }

        # Generic builtin or function call → BuiltinCall
        if (defined $func_name) {
            my $name_node = _make_const($factory, $func_name);
            # Detect paren-form vs bare-form call from scanned text.
            # Alt 0 is `QualifiedIdentifier _ /\(/ _ ExpressionList? _ /\)/`:
            # the identifier is immediately followed by `(` (with optional
            # whitespace). Alts 1-3 are bare forms (no immediate paren).
            # paren_form is recorded on the Call node so consumers can
            # distinguish bounded calls (should not unwrap) from bare-form
            # calls that may participate in postfix-chain stitching.
            my $text = $ctx->scanned_text() // '';
            my $is_paren_form = $text =~ /^\s*[\w:]+\s*\(/ ? true : false;
            return $ctx->factory->make('Call',
                dispatch_kind => 'builtin',
                name          => $name_node->value(),
                paren_form    => $is_paren_form,
                inputs        => [$name_node, \@args],
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
                return $ctx->factory->make('Interpolate',
                    inputs       => [\@parts],
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
    # Returns a hashref { stmts => [...], graph => Chalk::IR::Graph, type => $t }
    # where:
    #   - stmts: body statement IR nodes (+ __adjust_body/__phaser_block markers)
    #   - graph: the computation graph accumulated by inner statements
    #     (falls back to a fresh empty Graph if no inner action attached one)
    #   - type:  the union of exit value types - every explicit Return/Unwind
    #     value type, plus the implicit fall-through (final expression's type)
    #     when a fall-through path exists. Empty block yields 'Void'.
    method Block($ctx) {
        my @stmts;
        for my $val (_collect_ir_values($ctx)) {
            if (ref($val) eq 'ARRAY') {
                push @stmts, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @stmts, $val;
            } elsif (ref($val) eq 'HASH'
                    && (exists $val->{__adjust_body}
                        || exists $val->{__phaser_block})) {
                push @stmts, $val;
            }
        }

        # Collect exit-value types by walking our own SA Context subtree for
        # Return/Unwind IR foci. Inner method/sub/anonymous-sub bodies are
        # skipped: their returns belong to that nested scope, not to us.
        my %exit_types;
        my $ctx_addr = refaddr($ctx);
        my @walk = ($ctx);
        while (my $node = pop @walk) {
            my $rule = $node->rule();
            if (defined $rule
                    && refaddr($node) != $ctx_addr
                    && ($rule eq 'AnonymousSub'
                        || $rule eq 'SubroutineDefinition'
                        || $rule eq 'MethodDefinition')) {
                next;
            }
            my $f = $node->extract();
            if (defined $f && blessed($f)
                    && ($f isa Chalk::IR::Node::Return
                        || $f isa Chalk::IR::Node::Unwind)) {
                my $val_in = $f->inputs->[1];
                my $t = _classify_value_type($val_in);
                $exit_types{$t}++ if defined $t;
                next;
            }
            push @walk, $node->children->@*;
        }

        # Fall-through contribution: when the last top-level statement is
        # neither a Return nor an Unwind, the block also exits with that
        # expression's value. Classify the last IR node's type directly;
        # TI's Block.type is unavailable here because TI prunes at
        # ExpressionStatement boundaries (see _is_completed_sub_expr).
        my $has_fall = !@stmts
            || !(blessed($stmts[-1])
                && ($stmts[-1] isa Chalk::IR::Node::Return
                    || $stmts[-1] isa Chalk::IR::Node::Unwind));
        if ($has_fall && @stmts) {
            my $fall_t = _classify_value_type($stmts[-1]);
            $exit_types{$fall_t}++ if defined $fall_t;
        }

        my @types = sort keys %exit_types;
        my $type;
        if (!@types) {
            $type = 'Void';
        } elsif (@types == 1) {
            $type = $types[0];
        } else {
            $type = join('|', @types);
        }

        my $graph = $ctx->graph() // Chalk::IR::Graph->new;

        # Control-chain post-processing: rebuild side-effect nodes in
        # source order so each one's inputs[0] points at the previous
        # side-effect node (or Start for the first). The action layer
        # cannot chain across sibling statements because Scope.control
        # does not propagate sibling-to-sibling within a StatementList -
        # _merge_scope only fires at the parent rule's multiply, which
        # is too late for the child action to see. See
        # phase_3a_migration_cross_stmt_scope.md.
        my $start = $graph->start() // $factory->make('Start');
        $graph->merge($start);
        my $current_control = $start;
        for my $i (0..$#stmts) {
            my $s = $stmts[$i];
            next unless blessed($s);
            if ($s isa Chalk::IR::Node::VarDecl) {
                my $existing_ctrl = $s->control();
                if (!defined $existing_ctrl
                        || refaddr($existing_ctrl) != refaddr($current_control)) {
                    my $rebuilt = $ctx->factory->make('VarDecl',
                        inputs       => [$current_control, $s->name(), $s->init()],
                    );
                    $graph->unmerge($s);
                    $graph->merge($rebuilt);
                    $stmts[$i] = $rebuilt;
                    $s = $rebuilt;
                }
                $current_control = $s;
            } elsif ($s isa Chalk::IR::Node::Return
                        || $s isa Chalk::IR::Node::Unwind) {
                # Return/Unwind also need their control input updated to
                # the current chain tail. The ReturnStatement action sees
                # only its own multiply context and falls back to Start.
                my $existing_ctrl = $s->inputs->[0];
                if (!defined $existing_ctrl
                        || refaddr($existing_ctrl) != refaddr($current_control)) {
                    my $op = $s isa Chalk::IR::Node::Return
                        ? 'Return' : 'Unwind';
                    my $synthetic = $s isa Chalk::IR::Node::Return
                        && $s->can('synthetic') ? $s->synthetic : false;
                    my $rebuilt = $factory->make_cfg($op,
                        inputs => [$current_control, $s->inputs->[1]],
                        ($op eq 'Return' && $synthetic
                            ? (synthetic => $synthetic) : ()),
                    );
                    $graph->unmerge($s);
                    $graph->merge($rebuilt);
                    $stmts[$i] = $rebuilt;
                    $s = $rebuilt;
                }
                # Return/Unwind terminate the chain - don't advance control.
            } elsif ($s isa Chalk::IR::Node::Call
                        || $s isa Chalk::IR::Node::Assign
                        || $s isa Chalk::IR::Node::CompoundAssign
                        || $s isa Chalk::IR::Node::RegexSubst) {
                # Statement-position side-effect data node. Constructed by
                # its action (CallExpression, AssignmentExpression, etc.)
                # as a pure data node, sometimes without ever being merged
                # into a graph. Thread it into the effect chain via the
                # late-binding control_in setter inherited from Chalk::IR::Node;
                # merge into the graph so $graph->nodes and reachability
                # walks see it.
                $graph->merge($s);
                if (!defined $s->control_in
                        || refaddr($s->control_in) != refaddr($current_control)) {
                    $s->set_control_in($current_control);
                }
                $current_control = $s;
            } elsif ($s isa Chalk::IR::Node::If
                        || $s isa Chalk::IR::Node::Loop) {
                # CFG control-flow statement. Its control input lives
                # in inputs[0] (set at construction by the corresponding
                # action to the parsing-time scope.control). Rewire it
                # to the current chain tail if they disagree; advance
                # past the post-construct Region which the action
                # stashed on the node via set_region().
                my $existing_ctrl = $s->inputs->[0];
                if (!defined $existing_ctrl
                        || refaddr($existing_ctrl) != refaddr($current_control)) {
                    $s->set_control_in($current_control);
                }
                $current_control = $s->region // $s;
            }
        }

        return {
            stmts => \@stmts,
            graph => $graph,
            type  => $type,
        };
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

        # Side-effect-shaped: inputs[0]=control, [1]=name, [2]=init.
        # Control comes from the in-scope control input - the previous
        # side-effect node, or a fresh Start if this is the first.
        my $control = _ctx_control($ctx) // $factory->make('Start');
        my $var_decl = $ctx->factory->make('VarDecl',
            inputs       => [$control, $var_name, undef],
        );

        # Get or create the in-flight graph. If no inner action has yet
        # published one (e.g., this is the first side-effect in a body),
        # allocate a fresh Chalk::IR::Graph here and publish it upward
        # via update_graph so subsequent siblings/Block see the same one.
        my $graph = $ctx->graph() // Chalk::IR::Graph->new;
        # Seed Start so $graph->start() finds it via cache scan rather
        # than relying on inputs() walks (which only nodes() does).
        if ($control->operation() eq 'Start') {
            $graph->merge($control);
        }
        $graph->merge($var_decl);

        # Update scope: bind variable to the VarDecl and advance control
        # so subsequent side-effect actions chain after this one. Publish
        # the graph so it propagates up to Block / MethodDefinition.
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $scope = _ctx_scope($ctx);
            if (defined $scope) {
                my $new_scope = $scope
                    ->define($var_name->value(), $var_decl)
                    ->with_control($var_decl);
                $sa->update_scope($new_scope);
            }
            $sa->update_graph($graph);
        }

        return $var_decl;
    }

    # §13 ParenExpr — transparent
    method ParenExpr($ctx) {
        my @values = _collect_ir_values($ctx);
        for my $val (@values) {
            if ($val isa Chalk::IR::Node::ExpressionList) {
                # Multi-element paren: return items as arrayref (hash init, etc.)
                return $val->items();
            }
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
            if ($val isa Chalk::IR::Node::ExpressionList) {
                push @elements, $val->items()->@*;
            } elsif (ref($val) eq 'ARRAY') {
                push @elements, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @elements, $val;
            }
        }
        return $ctx->factory->make('ArrayRef',
            inputs       => [\@elements],
        );
    }

    # §13 HashConstructor ::= /\{/ _ ExpressionList? _ /\}/
    # Returns Constructor:HashRefExpr
    method HashConstructor($ctx) {
        my @values = _collect_ir_values($ctx);
        my @pairs;
        for my $val (@values) {
            if ($val isa Chalk::IR::Node::ExpressionList) {
                push @pairs, $val->items()->@*;
            } elsif (ref($val) eq 'ARRAY') {
                push @pairs, $val->@*;
            } elsif ($val isa Chalk::IR::Node) {
                push @pairs, $val;
            }
        }
        return $ctx->factory->make('HashRef',
            inputs       => [\@pairs],
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

        $body //= [];

        return $ctx->factory->make('AnonSub',
            inputs       => [\@params, $body],
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
        return $ctx->factory->make($unop_type,
            inputs       => [$op_node, $operand],
            operand      => $operand,
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
                    return $ctx->factory->make('RegexSubst',
                        flags        => $flags_str,
                        inputs       => [$left, _make_const($factory, $1), _make_const($factory, $2), $flags_node],
                    );
                }
            } else {
                # /pattern/flags or m/pattern/flags
                my $flags_node = _make_const($factory, '');
                my $flags_str  = (defined $flags_node ? $flags_node->value() : '') // '';
                return $ctx->factory->make('RegexMatch',
                    flags        => $flags_str,
                    inputs       => [$left, $right, $flags_node],
                );
            }
        }

        my $op_str    = $op->value();
        my $binop_type = $BINOP_MAP{$op_str} // die "Unknown binary op: $op_str";
        return $ctx->factory->make($binop_type,
            inputs       => [$op, $left, $right],
            left         => $left,
            right        => $right,
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
                $result = $ctx->factory->make('Call',
                    dispatch_kind => 'method',
                    name          => $op->inputs()->[1]->value(),
                    inputs        => [$result, $op->inputs()->[1], $op->inputs()->[2]],
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
                        $args[-1] = $ctx->factory->make('Subscript',
                            inputs       => [$inner_target, $op->inputs()->[1], $op->inputs()->[2]],
                        );
                        $result = $ctx->factory->make('Call',
                            dispatch_kind => 'builtin',
                            name          => $result->inputs()->[0]->value(),
                            inputs        => [$result->inputs()->[0], \@args],
                        );
                        next;
                    }
                }
                $result = $ctx->factory->make('Subscript',
                    inputs       => [$result, $op->inputs()->[1], $op->inputs()->[2]],
                );
            } elsif ($op isa Chalk::IR::Node::PostfixDeref) {
                my $s = $op->inputs()->[1];
                $result = $ctx->factory->make('PostfixDeref',
                    sigil        => (ref($s) ? $s->value() : $s),
                    inputs       => (ref($s) ? [$result, $s] : [$result]),
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
                if ($focus isa Chalk::IR::Node::ExpressionList) {
                    push @args, $focus->items()->@*;
                } elsif (ref($focus) eq 'ARRAY') {
                    push @args, $focus->@*;
                } elsif ($focus isa Chalk::IR::Node) {
                    push @args, $focus;
                }
            }
        }

        return undef unless defined $method_name;

        # Note: Call->target (the resolved MOP::Method handle) is set by
        # ClassBlock's post-pass after the surrounding class registers
        # all of its methods on the MOP. By the time this MethodCall
        # action runs, the enclosing ClassBlock hasn't yet completed, so
        # find_method() would miss the callee in same-class self-calls.
        return $ctx->factory->make('Call',
            dispatch_kind => 'method',
            name          => $method_name->value(),
            inputs        => [$invocant, $method_name, \@args],
        );
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
            } elsif ($val isa Chalk::IR::Node::ExpressionList && $style eq 'call' && !defined $index) {
                # ExpressionList IR node — unwrap items as call arguments
                $index = $val->items();
                last;
            } elsif (ref($val) eq 'ARRAY' && $style eq 'call' && !defined $index) {
                # Legacy arrayref path — capture as call arguments
                $index = $val;
                last;
            }
        }

        return $ctx->factory->make('Subscript',
            inputs       => [$target, $index, _make_const($factory, $style)],
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

        return $ctx->factory->make('PostfixDeref',
            sigil        => $sigil_node->value(),
            inputs       => [$target, $sigil_node],
        );
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
        return $ctx->factory->make('CompoundAssign',
            op           => $op_node,
            inputs       => [$op_node, $target, $one_node],
        );
    }

    # §16 PreIncDec ::= /\+\+/ _ Expression | /--/ _ Expression
    # Mirror of PostfixIncDec: emit CompoundAssign(+=/-=, target, 1).
    # Pre/post distinction is elided here (both become CompoundAssign); a typed
    # PreIncrement/PostIncrement node distinction is deferred to a future pass.
    method PreIncDec($ctx) {
        my $scanned = $ctx->scanned_text() // '';
        my $op_str = ($scanned =~ /--/) ? '-=' : '+=';
        my @leaves = _collect_ir_leaves($ctx);
        my $target;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (defined $focus && $focus isa Chalk::IR::Node) {
                $target //= $focus;
            }
        }
        return undef unless defined $target;
        my $op_node  = $factory->make('Constant', value => $op_str,  const_type => 'string');
        my $one_node = $factory->make('Constant', value => '1',      const_type => 'number');
        return $ctx->factory->make('CompoundAssign',
            op           => $op_node,
            inputs       => [$op_node, $target, $one_node],
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

        return $ctx->factory->make('TernaryExpr',
            inputs       => [$ir_nodes[0], $ir_nodes[1], $ir_nodes[2]],
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
            my $scope = _ctx_scope($ctx);
            return unless defined $scope;
            my $new_scope = $scope->define($var_name, $ir_node);
            $sa->update_scope($new_scope);
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
            # VarDecl target: set its initializer and return it.
            # Preserve the original VarDecl's control input so the chain
            # stays anchored at the same point (this replaces the bare
            # VarDecl-without-init, not a new side-effect after it).
            if ($target isa Chalk::IR::Node::VarDecl) {
                # If value is an arrayref (from ParenExpr/ExpressionList),
                # wrap it in a HashRef node so it can be stored as a node input.
                # The emitter will render it as (k, v, ...) for hash variable init.
                my $init_value = $value;
                if (ref($value) eq 'ARRAY') {
                    $init_value = $ctx->factory->make('HashRef',
                        inputs       => [$value],
                    );
                }
                my $ctrl_in = $target->inputs()->[0];
                my $name_in = $target->inputs()->[1];
                my $result = $ctx->factory->make('VarDecl',
                    inputs       => [$ctrl_in, $name_in, $init_value],
                );

                # Update scope: rebind the variable to the refined VarDecl
                # and advance control so the next side-effect chains after it.
                # Replace the bare VarDecl in the graph with the refined one
                # (the bare version was merged by VariableDeclaration; the
                # refined version supersedes it).
                my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
                if (defined $sa
                        && $name_in isa Chalk::IR::Node::Constant
                        && defined $name_in->value()
                        && $name_in->value() =~ /^[\$\@\%]/) {
                    my $scope = _ctx_scope($ctx);
                    if (defined $scope) {
                        $sa->update_scope(
                            $scope
                                ->define($name_in->value(), $result)
                                ->with_control($result)
                        );
                    }
                    my $graph = $ctx->graph() // Chalk::IR::Graph->new;
                    $graph->unmerge($target);  # drop the bare VarDecl
                    $graph->merge($result);
                    $sa->update_graph($graph);
                }
                return $result;
            }
            # Plain variable assignment ($var = expr) — emit as BinaryExpr (Assign).
            # VarDecl is only for my/our/state declarations (handled above).
            my $assign_op_str = $op->value();
            my $assign_binop_type = $BINOP_MAP{$assign_op_str} // die "Unknown binary op: $assign_op_str";
            my $assign_result = $ctx->factory->make($assign_binop_type,
                inputs       => [$op, $target, $value],
                left         => $target,
                right        => $value,
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
        my $compound_result = $ctx->factory->make('CompoundAssign',
            op           => $op,
            inputs       => [$op, $target, $value],
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

        return undef unless defined $keyword;

        # Build CFG nodes for loop-type modifiers (for/foreach/while/until)
        if ($keyword =~ /^(?:for|foreach|while|until)$/) {
            my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
            if (defined $sa) {
                my $scope   = _ctx_scope($ctx);
                my $control = _ctx_control($ctx) // $factory->make('Start');
                if (defined $scope) {
                    my $loop_cond = $condition // $factory->make('Constant',
                        const_type => 'string', value => '__loop_bound__');
                    # For 'until', negate the condition (until X = while !X)
                    if ($keyword eq 'until') {
                        my $not_op = _make_const($factory, '!');
                        my $not_type = $UNOP_MAP{'!'} // die "Unknown unary op: !";
                        $loop_cond = $ctx->factory->make($not_type,
                            inputs       => [$not_op, $loop_cond],
                            operand      => $loop_cond,
                        );
                    }
                    my $loop = $factory->make('Loop',
                        entry_ctrl    => $control,
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
                    $loop->set_region($region);
                    $sa->update_scope($scope->with_control($region));
                    $sa->update_annotations({
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
                my $scope   = _ctx_scope($ctx);
                my $control = _ctx_control($ctx) // $factory->make('Start');
                if (defined $scope) {
                    # For 'unless', negate the condition (unless X = if !X)
                    my $cond = $condition;
                    if ($keyword eq 'unless') {
                        my $not_op2 = _make_const($factory, '!');
                        my $not_type2 = $UNOP_MAP{'!'} // die "Unknown unary op: !";
                        $cond = $ctx->factory->make($not_type2,
                            inputs       => [$not_op2, $condition],
                            operand      => $condition,
                        );
                    }
                    my $if_node = $factory->make('If',
                        control   => $control,
                        condition => $cond,
                    );
                    my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
                    my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
                    my $region = $factory->make('Region',
                        controls => [$true_proj, $false_proj],
                    );
                    $if_node->set_region($region);
                    $sa->update_scope($scope->with_control($region));
                    $sa->update_annotations({
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
            } elsif (defined $rule && $rule eq 'Block') {
                my $stmts = _block_stmts($focus);
                if (defined $stmts) {
                    if (!defined $then_body) {
                        $then_body = $stmts;
                        $then_leaf = $leaf;
                    } else {
                        $else_body = $stmts;
                        $else_leaf = $leaf;
                    }
                }
            } elsif (ref($focus) eq 'ARRAY' && !defined $then_body) {
                $then_body = $focus;
                $then_leaf = $leaf;
            } elsif (ref($focus) eq 'ARRAY' && defined $then_body) {
                $else_body = $focus;
                $else_leaf = $leaf;
            } elsif ($focus isa Chalk::IR::Node::If) {
                # ElsifChain returns a CFG If node - wrap as else_body
                $else_body = [$focus];
            }
        }

        return undef unless defined $condition;

        $then_body //= [];

        # For 'unless', wrap condition in UnaryExpr with '!'
        if (defined $keyword && $keyword eq 'unless') {
            my $not_op3 = _make_const($factory, '!');
            my $not_type3 = $UNOP_MAP{'!'} // die "Unknown unary op: !";
            $condition = $ctx->factory->make($not_type3,
                inputs       => [$not_op3, $condition],
                operand      => $condition,
            );
        }

        # Build CFG nodes: If/Proj/Region for control flow
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $scope   = _ctx_scope($ctx);
            my $control = _ctx_control($ctx) // $factory->make('Start');
            if (defined $scope) {
                my $if_node = $factory->make('If',
                    control   => $control,
                    condition => $condition,
                );
                my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
                my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
                my $region = $factory->make('Region',
                    controls => [$true_proj, $false_proj],
                );

                # Extract per-branch final scopes from the leaf Contexts that
                # provided then_body and else_body. The scope field on those leaves
                # records the scope as it stood at the end of each branch.
                #
                # The pre-branch scope comes from the condition leaf's scope field,
                # not from scope directly: by the time the complete event runs, multiply()
                # has already merged the then-block's scope into the inherited state,
                # so scope may be contaminated with branch assignments.
                my $pre_scope;
                if (defined $cond_leaf) {
                    $pre_scope = _ctx_scope($cond_leaf);
                }
                $pre_scope //= $scope;

                my $then_scope  = $pre_scope;
                my $else_scope  = $pre_scope;
                if (defined $then_leaf) {
                    $then_scope = _ctx_scope($then_leaf) // $pre_scope;
                }
                if (defined $else_leaf) {
                    $else_scope = _ctx_scope($else_leaf) // $pre_scope;
                }

                # Merge branch scopes with eager Phi creation for variables
                # that differ between branches.
                my $pre_snapshot = $pre_scope->snapshot();
                my $merged_scope = $pre_scope->merge_with_phis(
                    $then_scope, $else_scope, $region, $factory,
                );

                # Merge CFG and Phi nodes into the in-flight graph so they
                # reach the method's graph via $graph->nodes(). Phis only
                # appear for divergent bindings; trivial Phis were already
                # collapsed inside merge_with_phis.
                my $graph = $ctx->graph() // Chalk::IR::Graph->new;
                $graph->merge($if_node);
                $graph->merge($true_proj);
                $graph->merge($false_proj);
                $graph->merge($region);

                # Tell the If node its post-construct merge point so the
                # Block control-chain fixup pass can advance past it.
                $if_node->set_region($region);
                my $diff = $merged_scope->diff($pre_snapshot);
                for my $var_name (keys $diff->%*) {
                    my $node = $diff->{$var_name};
                    next unless defined $node && blessed($node);
                    next unless $node isa Chalk::IR::Node::Phi;
                    $graph->merge($node);
                }
                $sa->update_graph($graph);

                $sa->update_scope($merged_scope->with_control($region));
                $sa->update_annotations({
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
            my $rule = $leaf->rule();

            if (!defined $condition && $focus isa Chalk::IR::Node) {
                # Skip CFG If nodes from nested ElsifChain
                if ($focus isa Chalk::IR::Node::If) {
                    $else_body = [$focus];
                    next;
                }
                $condition = $focus;
            } elsif (defined $rule && $rule eq 'Block') {
                my $stmts = _block_stmts($focus);
                if (defined $stmts) {
                    if (!defined $then_body) {
                        $then_body = $stmts;
                    } else {
                        $else_body = $stmts;
                    }
                }
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

        $then_body //= [];

        # Build CFG nodes for the elsif branch
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $scope   = _ctx_scope($ctx);
            my $control = _ctx_control($ctx) // $factory->make('Start');
            if (defined $scope) {
                my $if_node = $factory->make('If',
                    control   => $control,
                    condition => $condition,
                );
                my $true_proj  = $factory->make('Proj', source => $if_node, index => 0);
                my $false_proj = $factory->make('Proj', source => $if_node, index => 1);
                my $region = $factory->make('Region',
                    controls => [$true_proj, $false_proj],
                );
                $if_node->set_region($region);
                $sa->update_scope($scope->with_control($region));
                $sa->update_annotations({
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
        my $cond_leaf;

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
                    $cond_leaf = $leaf;
                } elsif (ref($focus) eq 'ARRAY' && $focus->@*) {
                    # ParenExpr may produce an array; take first element as condition
                    $condition = $focus->[0];
                    $cond_leaf = $leaf;
                }
            } elsif (defined $condition && !defined $body
                    && defined $rule && $rule eq 'Block') {
                my $stmts = _block_stmts($focus);
                $body = $stmts if defined $stmts;
            } elsif (defined $condition && !defined $body && ref($focus) eq 'ARRAY') {
                # Block body
                $body = $focus;
            }
        }

        return undef unless defined $keyword && defined $condition;

        $body //= [];

        # Build CFG nodes: Loop/If/Proj/Region for control flow
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $scope   = _ctx_scope($ctx);
            my $control = _ctx_control($ctx) // $factory->make('Start');
            if (defined $scope) {
                # Pre-loop scope: read from the condition leaf, not from
                # $ctx directly. By the time WhileStatement's complete event
                # runs, multiply() has already merged the body's scope into
                # $ctx, contaminating the pre-loop view. The condition leaf
                # captured scope before the body was multiplied in. Same
                # workaround as IfStatement uses.
                my $pre_loop_scope = $scope;
                if (defined $cond_leaf) {
                    my $cond_scope = _ctx_scope($cond_leaf);
                    $pre_loop_scope = $cond_scope if defined $cond_scope;
                }

                my $loop = $factory->make('Loop',
                    entry_ctrl    => $control,
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
                    my $leaf_scope = _ctx_scope($leaf);
                    if (defined $leaf_scope) {
                        for my $name ($leaf_scope->variable_names()) {
                            my $binding = $leaf_scope->lookup($name);
                            $body_final_bindings{$name} = $binding if defined $binding;
                        }
                    }
                }

                # Create Phi nodes for loop-carried variables directly here.
                # While loops have no iterator variable, so pass undef.
                my $pre_snapshot = $pre_loop_scope->snapshot();
                my $post_loop_scope = $pre_loop_scope->merge_for_loop(
                    \%body_final_bindings, $loop, $factory, undef,
                );

                my $region = $factory->make('Region',
                    controls => [$exit_proj],
                );
                $loop->set_region($region);

                # Merge CFG and Phi nodes into the in-flight graph so they
                # reach the method graph via $graph->nodes().
                my $graph = $ctx->graph() // Chalk::IR::Graph->new;
                $graph->merge($loop);
                $graph->merge($if_node);
                $graph->merge($body_proj);
                $graph->merge($exit_proj);
                $graph->merge($region);
                my $diff = $post_loop_scope->diff($pre_snapshot);
                for my $var_name (keys $diff->%*) {
                    my $node = $diff->{$var_name};
                    next unless defined $node && blessed($node);
                    next unless $node isa Chalk::IR::Node::Phi;
                    $graph->merge($node);
                }
                $sa->update_graph($graph);

                $sa->update_scope($post_loop_scope->with_control($region));
                $sa->update_annotations({
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
        my $list_leaf;

        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            my $rule = $leaf->rule() // '';

            if ($focus isa Chalk::IR::Node::Constant
                    && defined $focus->value()
                    && $focus->value() =~ /^[\$\@\%]/
                    && !defined $iterator) {
                $iterator = $focus;
            } elsif ($rule eq 'Block') {
                my $stmts = _block_stmts($focus);
                $body //= $stmts if defined $stmts;
            } elsif (ref($focus) eq 'ARRAY' && defined $iterator && !defined $list) {
                # First array after iterator is the list (from ParenExpr)
                $list = $focus;
                $list_leaf = $leaf;
            } elsif (ref($focus) eq 'ARRAY' && defined $list) {
                # Second array is the body (from Block)
                $body //= $focus;
            } elsif ($focus isa Chalk::IR::Node && !defined $list
                    && defined $iterator) {
                $list = $focus;
                $list_leaf = $leaf;
            }
        }

        return undef unless defined $iterator;

        $body //= [];

        # Build CFG nodes: Loop/If/Proj/Region for control flow
        my $sa = Chalk::Bootstrap::Semiring::SemanticAction->current_instance();
        if (defined $sa) {
            my $scope   = _ctx_scope($ctx);
            my $control = _ctx_control($ctx) // $factory->make('Start');
            if (defined $scope) {
                # Pre-loop scope: read from the list-leaf, not from $ctx
                # directly. By the time ForeachStatement's complete event
                # runs, multiply() has already merged the body's scope into
                # $ctx, contaminating the pre-loop view. The list leaf
                # captured scope before the body was multiplied in.
                my $pre_loop_scope = $scope;
                if (defined $list_leaf) {
                    my $ls = _ctx_scope($list_leaf);
                    $pre_loop_scope = $ls if defined $ls;
                }

                my $loop_cond = $factory->make('Constant',
                    const_type => 'string', value => '__loop_bound__');
                my $loop = $factory->make('Loop',
                    entry_ctrl    => $control,
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
                # the body leaf scope field will have a scope binding that differs from the
                # pre-loop value. These become the backedge values in the Phi nodes.
                my %body_final_bindings;
                for my $leaf (_collect_ir_leaves($ctx)) {
                    my $leaf_scope = _ctx_scope($leaf);
                    if (defined $leaf_scope) {
                        for my $name ($leaf_scope->variable_names()) {
                            my $binding = $leaf_scope->lookup($name);
                            $body_final_bindings{$name} = $binding if defined $binding;
                        }
                    }
                }

                # Create Phi nodes for loop-carried variables directly here.
                # The iterator variable is defined by the loop itself and excluded.
                my $iterator_name = defined $iterator ? $iterator->value() : undef;
                my $pre_snapshot = $pre_loop_scope->snapshot();
                my $post_loop_scope = $pre_loop_scope->merge_for_loop(
                    \%body_final_bindings, $loop, $factory, $iterator_name,
                );

                my $region = $factory->make('Region',
                    controls => [$exit_proj],
                );
                $loop->set_region($region);

                # Merge CFG and Phi nodes into the in-flight graph.
                my $graph = $ctx->graph() // Chalk::IR::Graph->new;
                $graph->merge($loop);
                $graph->merge($if_node);
                $graph->merge($body_proj);
                $graph->merge($exit_proj);
                $graph->merge($region);
                my $diff = $post_loop_scope->diff($pre_snapshot);
                for my $var_name (keys $diff->%*) {
                    my $node = $diff->{$var_name};
                    next unless defined $node && blessed($node);
                    next unless $node isa Chalk::IR::Node::Phi;
                    $graph->merge($node);
                }
                $sa->update_graph($graph);

                $sa->update_scope($post_loop_scope->with_control($region));
                $sa->update_annotations({
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

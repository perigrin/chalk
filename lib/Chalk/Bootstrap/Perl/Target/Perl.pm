# ABOUTME: Walks Perl IR (Program/UseDecl/ClassDecl/MethodDecl/etc) and emits Perl source.
# ABOUTME: Generates feature class code that is behaviorally equivalent to the original.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::Perl::Target::Perl :isa(Chalk::Bootstrap::Target) {

    # Lookup from IR node refaddr → cfg_state entry, built by generate_with_cfg
    field %_cfg_lookup;

    method generate($ir) {
        die "generate() requires a Constructor:Program IR node"
            unless defined($ir)
            && $ir isa Chalk::Bootstrap::IR::Node::Constructor
            && $ir->class() eq 'Program';

        return $self->_emit_program($ir);
    }

    # Generate code with cfg_state-aware dispatch for control flow.
    # Walks the Context tree to build IR node → cfg_state lookup,
    # then generates code using cfg_state for if/loop dispatch.
    method generate_with_cfg($ir, $sa, $ctx) {
        die "generate_with_cfg() requires a Constructor:Program IR node"
            unless defined($ir)
            && $ir isa Chalk::Bootstrap::IR::Node::Constructor
            && $ir->class() eq 'Program';

        %_cfg_lookup = ();
        $self->_build_cfg_lookup($sa, $ctx);
        my $code = $self->_emit_program($ir);
        %_cfg_lookup = ();
        return $code;
    }

    # Walk Context tree, mapping IR node refaddr → cfg_state for control flow nodes.
    # First-found wins: parent rules (e.g. ExpressionStatement) that wire body
    # expressions into cfg_state take priority over child rules (e.g. PostfixModifier)
    # that have empty stmts.
    method _build_cfg_lookup($sa, $ctx) {
        my @stack = ($ctx);
        while (@stack) {
            my $node = pop @stack;
            my $state = $sa->cfg_state($node);
            if (defined $state && (defined $state->{if_node} || defined $state->{loop})) {
                my $ir_node = $node->extract();
                if (defined $ir_node && ref($ir_node) && !exists $_cfg_lookup{refaddr($ir_node)}) {
                    $_cfg_lookup{refaddr($ir_node)} = $state;
                }
            }
            push @stack, reverse $node->children()->@*;
        }
        return;
    }

    method generate_distribution($ir) {
        # For Perl target, return a single file mapping
        my $code = $self->generate($ir);

        # Extract class name from the IR to determine file path
        my $stmts = $ir->inputs()->[0];
        my $class_name;
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && $stmt->class() eq 'ClassDecl') {
                $class_name = $stmt->inputs()->[0]->value();
                last;
            }
        }

        if (defined $class_name) {
            my $path = $class_name;
            $path =~ s{::}{/}g;
            return { "lib/$path.pm" => $code };
        }

        return { 'output.pm' => $code };
    }

    method _emit_program($node) {
        my $stmts = $node->inputs()->[0];
        my @lines;
        for my $stmt ($stmts->@*) {
            my $line = $self->_emit_node($stmt);
            push @lines, $line if defined $line;
        }
        return join("\n", @lines) . "\n";
    }

    # Statement-level types that handle their own formatting (no auto-semicolon)
    my %STATEMENT_TYPES = map { $_ => 1 } qw(
        Program UseDecl ClassDecl MethodDecl ReturnStmt DieCall FieldDecl
        VarDecl CompoundAssign NextUnless
    );

    # Expression types that need semicolons when used as statements
    my %EXPR_TYPES = map { $_ => 1 } qw(
        BinaryExpr UnaryExpr MethodCallExpr SubscriptExpr PostfixDerefExpr
        TernaryExpr HashRefExpr ArrayRefExpr AnonSubExpr RegexMatch
        RegexSubst BuiltinCall BacktickExpr InterpolatedString
    );

    method _emit_node($node) {
        return undef unless defined $node;

        # Check cfg_state lookup for control flow dispatch
        if (%_cfg_lookup && ref($node)) {
            my $state = $_cfg_lookup{refaddr($node)};
            if (defined $state) {
                if (defined $state->{if_node}) {
                    return $self->emit_cfg_if(
                        $state->{if_node},
                        $state->{true_proj},
                        $state->{false_proj},
                        $state->{then_stmts} // [],
                        $state->{else_stmts} // [],
                    );
                }
                if (defined $state->{loop}) {
                    return $self->emit_cfg_loop(
                        $state->{loop},
                        $state->{loop_if},
                        $state->{body_proj},
                        $state->{exit_proj},
                        $state->{body_stmts} // [],
                        $state->{iterator},
                        $state->{list},
                    );
                }
            }
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            return $self->_emit_constant($node);
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();

            # Expression-type nodes get semicolons when used as statements
            if ($EXPR_TYPES{$class}) {
                return $self->_emit_expr($node) . ";";
            }

            if ($class eq 'Program')    { return $self->_emit_program($node); }
            if ($class eq 'UseDecl')    { return $self->_emit_use_decl($node); }
            if ($class eq 'ClassDecl')  { return $self->_emit_class_decl($node); }
            if ($class eq 'MethodDecl') { return $self->_emit_method_decl($node); }
            if ($class eq 'ReturnStmt') { return $self->_emit_return_stmt($node); }
            if ($class eq 'DieCall')    { return $self->_emit_die_call($node); }
            if ($class eq 'FieldDecl')  { return $self->_emit_field_decl($node); }
            if ($class eq 'VarDecl')         { return $self->_emit_var_decl($node); }
            if ($class eq 'CompoundAssign')  { return $self->_emit_compound_assign($node); }
            if ($class eq 'NextUnless')      { return $self->_emit_next_unless($node); }
            die "Unknown Constructor class: $class";
        }

        die "Unknown IR node type: " . ref($node);
    }

    method _emit_constant($node) {
        my $value = $node->value();
        return "'" . $self->_escape_single_quote($value) . "'";
    }

    method _emit_use_decl($node) {
        my $module = $node->inputs()->[0];
        my $args   = $node->inputs()->[1];

        my $module_name = $module->value();

        # Version strings don't get quoted
        if ($module_name =~ /^v?[0-9]/) {
            if (defined $args) {
                my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
                return "use $module_name " . join(', ', @arg_strs) . ";";
            }
            return "use $module_name;";
        }

        if (defined $args) {
            my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
            return "use $module_name " . join(', ', @arg_strs) . ";";
        }

        return "use $module_name;";
    }

    method _emit_class_decl($node) {
        my $name   = $node->inputs()->[0]->value();
        my $parent = $node->inputs()->[1];
        my $body   = $node->inputs()->[2];

        my $decl = "class $name";
        if (defined $parent) {
            $decl .= " :isa(${\$parent->value()})";
        }
        $decl .= " {";

        my @lines = ($decl);
        for my $item ($body->@*) {
            my $code = $self->_emit_node($item);
            if (defined $code) {
                # Indent body by 4 spaces
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";

        return join("\n", @lines);
    }

    method _emit_method_decl($node) {
        my $name   = $node->inputs()->[0]->value();
        my $params = $node->inputs()->[1];
        my $body   = $node->inputs()->[2];

        my $sig = '(' . join(', ', map { $_->value() } $params->@*) . ')';
        my $decl = "method $name$sig {";

        my @lines = ($decl);
        for my $item ($body->@*) {
            my $code = $self->_emit_node($item);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";

        return join("\n", @lines);
    }

    method _emit_return_stmt($node) {
        my $value = $node->inputs()->[0];
        return "return " . $self->_emit_expr($value) . ";";
    }

    method _emit_die_call($node) {
        my $args = $node->inputs()->[0];
        my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
        return "die " . join(', ', @arg_strs) . ";";
    }

    method _emit_field_decl($node) {
        my $name_node     = $node->inputs()->[0];
        my $attrs         = $node->inputs()->[1];
        my $default_value = $node->inputs()->[2];

        my $name = $name_node->value();
        my $decl = "field $name";

        if (ref($attrs) eq 'ARRAY' && $attrs->@*) {
            for my $attr ($attrs->@*) {
                my $attr_name = $attr->inputs()->[0]->value();
                $decl .= " :$attr_name";
            }
        }

        if (defined $default_value) {
            $decl .= " = " . $self->_emit_expr($default_value);
        }

        return "$decl;";
    }

    method _emit_interpolated_string($node) {
        my $parts = $node->inputs()->[0];
        my $result = '"';
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                $result .= $part->value();
            } else {
                # Literal string — escape for double-quoted context
                my $lit = $part->value();
                $lit =~ s/\\/\\\\/g;
                $lit =~ s/"/\\"/g;
                $lit =~ s/\n/\\n/g;
                $lit =~ s/\t/\\t/g;
                $lit =~ s/\$/\\\$/g;
                $lit =~ s/\@/\\\@/g;
                $result .= $lit;
            }
        }
        $result .= '"';
        return $result;
    }

    # Emit an expression (no trailing semicolon, no statement wrapper)
    method _emit_expr($node) {
        return 'undef' unless defined $node;

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            my $val = $node->value();
            my $ct = $node->const_type();
            # Variables and special values don't get quoted
            if ($ct eq 'variable' || $val =~ /^[\$\@\%]/) {
                return $val;
            }
            # Numeric values
            if ($val =~ /^-?[0-9]+(?:\.[0-9]+)?$/) {
                return $val;
            }
            # Boolean/special values
            if ($val eq 'true' || $val eq 'false' || $val eq 'undef') {
                return $val;
            }
            return "'" . $self->_escape_single_quote($val) . "'";
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();
            if ($class eq 'InterpolatedString') { return $self->_emit_interpolated_string($node); }
            if ($class eq 'BinaryExpr')         { return $self->_emit_binary_expr($node); }
            if ($class eq 'UnaryExpr')          { return $self->_emit_unary_expr($node); }
            if ($class eq 'MethodCallExpr')     { return $self->_emit_method_call_expr($node); }
            if ($class eq 'SubscriptExpr')      { return $self->_emit_subscript_expr($node); }
            if ($class eq 'PostfixDerefExpr')   { return $self->_emit_postfix_deref_expr($node); }
            if ($class eq 'TernaryExpr')        { return $self->_emit_ternary_expr($node); }
            if ($class eq 'HashRefExpr')        { return $self->_emit_hash_ref_expr($node); }
            if ($class eq 'ArrayRefExpr')       { return $self->_emit_array_ref_expr($node); }
            if ($class eq 'AnonSubExpr')        { return $self->_emit_anon_sub_expr($node); }
            if ($class eq 'RegexMatch')         { return $self->_emit_regex_match($node); }
            if ($class eq 'RegexSubst')         { return $self->_emit_regex_subst($node); }
            if ($class eq 'BuiltinCall')        { return $self->_emit_builtin_call($node); }
            if ($class eq 'BacktickExpr')       { return $self->_emit_backtick_expr($node); }
            if ($class eq 'CompoundAssign')     { return $self->_emit_compound_assign($node); }
            if ($class eq 'VarDecl')            { return $self->_emit_var_decl_expr($node); }
            # Fall through to _emit_node for statement-level types
            return $self->_emit_node($node);
        }

        return $self->_emit_node($node);
    }

    method _emit_var_decl($node) {
        my $var  = $node->inputs()->[0]->value();
        my $init = $node->inputs()->[1];

        if (defined $init) {
            return "my $var = " . $self->_emit_expr($init) . ";";
        }
        return "my $var;";
    }

    # VarDecl as expression (no semicolon)
    method _emit_var_decl_expr($node) {
        my $var  = $node->inputs()->[0]->value();
        my $init = $node->inputs()->[1];

        if (defined $init) {
            return "my $var = " . $self->_emit_expr($init);
        }
        return "my $var";
    }

    method _emit_binary_expr($node) {
        my $op    = $node->inputs()->[0]->value();
        my $left  = $node->inputs()->[1];
        my $right = $node->inputs()->[2];

        return $self->_emit_expr($left) . " $op " . $self->_emit_expr($right);
    }

    method _emit_unary_expr($node) {
        my $op      = $node->inputs()->[0]->value();
        my $operand = $node->inputs()->[1];

        # Parenthesize compound operands to preserve precedence
        # (e.g., unless desugars to !cond, and !$a && $b != !($a && $b))
        my $needs_parens = $operand isa Chalk::Bootstrap::IR::Node::Constructor
            && ($operand->class() eq 'BinaryExpr' || $operand->class() eq 'TernaryExpr');

        my $expr = $self->_emit_expr($operand);
        if ($needs_parens) {
            $expr = "($expr)";
        }

        if ($op eq 'not') {
            return "not $expr";
        }
        return "$op$expr";
    }

    method _emit_compound_assign($node) {
        my $op     = $node->inputs()->[0]->value();
        my $target = $node->inputs()->[1];
        my $value  = $node->inputs()->[2];

        return $self->_emit_expr($target) . " $op " . $self->_emit_expr($value);
    }

    method _emit_method_call_expr($node) {
        my $invocant    = $node->inputs()->[0];
        my $method_name = $node->inputs()->[1]->value();
        my $args        = $node->inputs()->[2];

        my $inv = defined $invocant ? $self->_emit_expr($invocant) : '$self';
        my @arg_strs = map { $self->_emit_expr($_) } $args->@*;
        return "$inv->$method_name(" . join(', ', @arg_strs) . ")";
    }

    method _emit_subscript_expr($node) {
        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2]->value();

        my $tgt = defined $target ? $self->_emit_expr($target) : '$self';
        if ($style eq 'array') {
            return "$tgt\->[" . $self->_emit_expr($index) . "]";
        }
        return "$tgt\->{" . $self->_emit_expr($index) . "}";
    }

    method _emit_postfix_deref_expr($node) {
        my $target = $node->inputs()->[0];
        my $sigil  = $node->inputs()->[1]->value();

        my $tgt = defined $target ? $self->_emit_expr($target) : '$self';
        return "$tgt\->${sigil}*";
    }

    method _emit_ternary_expr($node) {
        my $cond       = $node->inputs()->[0];
        my $true_expr  = $node->inputs()->[1];
        my $false_expr = $node->inputs()->[2];

        return $self->_emit_expr($cond) . " ? "
             . $self->_emit_expr($true_expr) . " : "
             . $self->_emit_expr($false_expr);
    }

    method _emit_hash_ref_expr($node) {
        my $pairs = $node->inputs()->[0];
        if (!$pairs->@*) {
            return '{}';
        }
        my @strs = map { $self->_emit_expr($_) } $pairs->@*;
        return '{ ' . join(', ', @strs) . ' }';
    }

    method _emit_array_ref_expr($node) {
        my $elements = $node->inputs()->[0];
        if (!$elements->@*) {
            return '[]';
        }
        my @strs = map { $self->_emit_expr($_) } $elements->@*;
        return '[' . join(', ', @strs) . ']';
    }

    method _emit_anon_sub_expr($node) {
        my $params = $node->inputs()->[0];
        my $body   = $node->inputs()->[1];

        my $sig = '(' . join(', ', map { $_->value() } $params->@*) . ')';
        my @lines = ("sub $sig {");
        for my $stmt ($body->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    method _emit_regex_match($node) {
        my $target  = $node->inputs()->[0];
        my $pattern = $node->inputs()->[1];

        my $pat_val = $pattern->value();
        return $self->_emit_expr($target) . " =~ $pat_val";
    }

    method _emit_regex_subst($node) {
        my $target      = $node->inputs()->[0];
        my $pattern     = $node->inputs()->[1]->value();
        my $replacement = $node->inputs()->[2]->value();
        my $flags       = $node->inputs()->[3]->value();

        return $self->_emit_expr($target) . " =~ s/$pattern/$replacement/$flags";
    }

    method _emit_builtin_call($node) {
        my $name = $node->inputs()->[0]->value();
        my $args = $node->inputs()->[1];

        my @arg_strs = map { $self->_emit_expr($_) } $args->@*;

        # Some builtins use list syntax (no parens)
        if ($name eq 'push' || $name eq 'unshift' || $name eq 'die'
                || $name eq 'return' || $name eq 'print' || $name eq 'say') {
            return "$name " . join(', ', @arg_strs);
        }

        return "$name(" . join(', ', @arg_strs) . ")";
    }

    method _emit_next_unless($node) {
        my $condition = $node->inputs()->[0];
        return "next unless " . $self->_emit_expr($condition) . ";";
    }

    # Emit Perl if/else from an If CFG node with true/false Proj branches.
    method emit_cfg_if($if_node, $true_proj, $false_proj,
                       $true_stmts = [], $false_stmts = [],
                       $prefix = 'if') {
        my $cond = $if_node->inputs()->[1];  # condition input
        my $cond_expr = $self->_emit_expr($cond);

        my @lines;
        push @lines, "$prefix ($cond_expr) {";
        for my $stmt ($true_stmts->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        if ($false_stmts->@*) {
            # Detect elsif: single If CFG node in else branch
            if (scalar $false_stmts->@* == 1
                    && ref($false_stmts->[0])
                    && %_cfg_lookup) {
                my $elsif_state = $_cfg_lookup{refaddr($false_stmts->[0])};
                if (defined $elsif_state && defined $elsif_state->{if_node}) {
                    my $elsif_code = $self->emit_cfg_if(
                        $elsif_state->{if_node},
                        $elsif_state->{true_proj},
                        $elsif_state->{false_proj},
                        $elsif_state->{then_stmts} // [],
                        $elsif_state->{else_stmts} // [],
                        '} elsif',
                    );
                    push @lines, $elsif_code;
                    return join("\n", @lines);
                }
            }
            push @lines, "} else {";
            for my $stmt ($false_stmts->@*) {
                my $code = $self->_emit_node($stmt);
                if (defined $code) {
                    for my $line (split /\n/, $code) {
                        push @lines, "    $line";
                    }
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit Perl if/else with Phi variable declaration.
    # Phi(Region, val_a, val_b) becomes a my variable declared before the if,
    # assigned in each branch.
    method emit_cfg_phi_if($if_node, $phi) {
        my $cond = $if_node->inputs()->[1];
        my $cond_expr = $self->_emit_expr($cond);

        my $region = $phi->inputs()->[0];
        my $values = $phi->inputs()->[1];  # arrayref of [val_a, val_b]
        my $val_a_expr = $self->_emit_expr($values->[0]);
        my $val_b_expr = $self->_emit_expr($values->[1]);

        my $phi_var = '$_phi_' . $phi->id();

        my @lines;
        push @lines, "my $phi_var;";
        push @lines, "if ($cond_expr) {";
        push @lines, "    $phi_var = $val_a_expr;";
        push @lines, "} else {";
        push @lines, "    $phi_var = $val_b_expr;";
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit Perl loop from a Loop CFG node.
    # When iterator/list are present, emits foreach syntax.
    method emit_cfg_loop($loop, $loop_if, $body_proj, $exit_proj,
                         $body_stmts = [], $iterator = undef, $list = undef) {
        my @lines;

        if (defined $iterator && defined $list) {
            # Foreach loop: for my $var (list) { ... }
            my $iter_expr = $self->_emit_expr($iterator);
            my $list_expr;
            if (ref($list) eq 'ARRAY') {
                $list_expr = join(', ', map { $self->_emit_expr($_) } $list->@*);
            } else {
                $list_expr = $self->_emit_expr($list);
            }
            push @lines, "for my $iter_expr ($list_expr) {";
        } else {
            # While loop: while (cond) { ... }
            my $cond = $loop_if->inputs()->[1];
            my $cond_expr = $self->_emit_expr($cond);
            push @lines, "while ($cond_expr) {";
        }

        for my $stmt ($body_stmts->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    method _emit_backtick_expr($node) {
        my $command = $node->inputs()->[0];
        return '`' . $self->_emit_expr($command) . '`';
    }

    method _escape_single_quote($str) {
        $str =~ s/\\/\\\\/g;
        $str =~ s/'/\\'/g;
        return $str;
    }

    # Emit Perl code from a cfg_state entry.
    # Dispatches to emit_cfg_if or emit_cfg_loop based on which CFG node
    # references are present in the state.
    # Returns undef if the state has no control flow structure to emit.
    method emit_from_cfg_state($sa, $ctx) {
        my $state = $sa->cfg_state($ctx);
        return unless defined $state;

        # If/else: cfg_state has if_node
        if (defined $state->{if_node}) {
            return $self->emit_cfg_if(
                $state->{if_node},
                $state->{true_proj},
                $state->{false_proj},
                $state->{then_stmts} // [],
                $state->{else_stmts} // [],
            );
        }

        # Loop: cfg_state has loop
        if (defined $state->{loop}) {
            return $self->emit_cfg_loop(
                $state->{loop},
                $state->{loop_if},
                $state->{body_proj},
                $state->{exit_proj},
                $state->{body_stmts} // [],
                $state->{iterator},
                $state->{list},
            );
        }

        return;
    }
}

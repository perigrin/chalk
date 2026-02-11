# ABOUTME: Walks Perl IR (Program/UseDecl/ClassDecl/MethodDecl/etc) and emits Perl source.
# ABOUTME: Generates feature class code that is behaviorally equivalent to the original.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::Perl::Target::Perl :isa(Chalk::Bootstrap::Target) {

    method generate($ir) {
        die "generate() requires a Constructor:Program IR node"
            unless defined($ir)
            && $ir isa Chalk::Bootstrap::IR::Node::Constructor
            && $ir->class() eq 'Program';

        return $self->_emit_program($ir);
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
        VarDecl IfStmt ForeachLoop CompoundAssign PostfixLoop NextUnless
    );

    # Expression types that need semicolons when used as statements
    my %EXPR_TYPES = map { $_ => 1 } qw(
        BinaryExpr UnaryExpr MethodCallExpr SubscriptExpr PostfixDerefExpr
        TernaryExpr HashRefExpr ArrayRefExpr AnonSubExpr RegexMatch
        RegexSubst BuiltinCall BacktickExpr InterpolatedString
    );

    method _emit_node($node) {
        return undef unless defined $node;

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
            if ($class eq 'IfStmt')          { return $self->_emit_if_stmt($node); }
            if ($class eq 'ForeachLoop')     { return $self->_emit_foreach_loop($node); }
            if ($class eq 'CompoundAssign')  { return $self->_emit_compound_assign($node); }
            if ($class eq 'PostfixLoop')     { return $self->_emit_postfix_loop($node); }
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

    method _emit_if_stmt($node) {
        my $cond      = $node->inputs()->[0];
        my $then_body = $node->inputs()->[1];
        my $else_body = $node->inputs()->[2];

        my @lines;
        push @lines, "if (" . $self->_emit_expr($cond) . ") {";
        for my $stmt ($then_body->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }

        if (defined $else_body) {
            # Check if else_body is a single IfStmt (elsif chain)
            if (scalar $else_body->@* == 1
                    && $else_body->[0] isa Chalk::Bootstrap::IR::Node::Constructor
                    && $else_body->[0]->class() eq 'IfStmt') {
                # Emit as elsif
                my $elsif_code = $self->_emit_if_stmt($else_body->[0]);
                # Replace leading "if" with "} elsif"
                $elsif_code =~ s/^if/} elsif/;
                push @lines, $elsif_code;
                return join("\n", @lines);
            }

            push @lines, "} else {";
            for my $stmt ($else_body->@*) {
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

    method _emit_foreach_loop($node) {
        my $iter = $node->inputs()->[0]->value();
        my $list = $node->inputs()->[1];
        my $body = $node->inputs()->[2];

        my @lines;
        push @lines, "for my $iter (" . $self->_emit_expr($list) . ") {";
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

    method _emit_binary_expr($node) {
        my $op    = $node->inputs()->[0]->value();
        my $left  = $node->inputs()->[1];
        my $right = $node->inputs()->[2];

        return $self->_emit_expr($left) . " $op " . $self->_emit_expr($right);
    }

    method _emit_unary_expr($node) {
        my $op      = $node->inputs()->[0]->value();
        my $operand = $node->inputs()->[1];

        if ($op eq 'not') {
            return "not " . $self->_emit_expr($operand);
        }
        return "$op" . $self->_emit_expr($operand);
    }

    method _emit_compound_assign($node) {
        my $op     = $node->inputs()->[0]->value();
        my $target = $node->inputs()->[1];
        my $value  = $node->inputs()->[2];

        return $self->_emit_expr($target) . " $op " . $self->_emit_expr($value) . ";";
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

    method _emit_postfix_loop($node) {
        my $body      = $node->inputs()->[0];
        my $modifier  = $node->inputs()->[1]->value();
        my $condition = $node->inputs()->[2];

        my $body_code = defined $body ? $self->_emit_expr($body) : '';
        return "$body_code $modifier " . $self->_emit_expr($condition) . ";";
    }

    method _emit_next_unless($node) {
        my $condition = $node->inputs()->[0];
        return "next unless " . $self->_emit_expr($condition) . ";";
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
}

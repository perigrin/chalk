# ABOUTME: Walks Perl IR (Program/UseDecl/ClassDecl/MethodDecl/etc) and emits Perl source.
# ABOUTME: Generates feature class code that is behaviorally equivalent to the original.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;
use Chalk::IR::Node;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::UnaryOp;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::Node::RegexMatch;
use Chalk::IR::Node::RegexSubst;
use Chalk::IR::Node::BacktickExpr;
use Chalk::IR::Node::Aggregate;
use Chalk::IR::Node::Regex;
use Chalk::IR::Node::TryCatch;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::Program;

class Chalk::Bootstrap::Perl::Target::Perl :isa(Chalk::Bootstrap::Target) {

    # Lookup from IR node refaddr → cfg_state entry, built by generate_with_cfg
    field %_cfg_lookup;

    # Struct schemas for StructRef/FieldAccess lowering (schema_name → { fields => [...] })
    field $_struct_schemas = {};

    # Set of variable base names declared with aggregate sigils (% or @).
    # Used by _emit_subscript_expr to emit $hash{key} instead of $hash->{key}
    # when the variable was declared as %hash.  Keys are bare names (no sigil).
    field %_aggregate_vars;

    # Set struct schemas for StructRef/FieldAccess lowering.
    method set_struct_schemas($schemas) {
        $_struct_schemas = $schemas;
    }

    # Public wrapper for _emit_expr (used by tests and external callers).
    method emit_expr($node) {
        return $self->_emit_expr($node);
    }

    method generate($ir) {
        die "generate() requires a Program IR node"
            unless defined($ir)
            && ($ir isa Chalk::IR::Program
                || ($ir isa Chalk::Bootstrap::IR::Node::Constructor
                    && $ir->class() eq 'Program'));

        return $self->_emit_program($ir);
    }

    # Generate code with cfg_state-aware dispatch for control flow.
    # Walks the Context tree to build IR node → cfg_state lookup,
    # then generates code using cfg_state for if/loop dispatch.
    method generate_with_cfg($ir, $sa, $ctx) {
        die "generate_with_cfg() requires a Program IR node"
            unless defined($ir)
            && ($ir isa Chalk::IR::Program
                || ($ir isa Chalk::Bootstrap::IR::Node::Constructor
                    && $ir->class() eq 'Program'));

        %_cfg_lookup = ();
        %_aggregate_vars = ();
        $self->_build_cfg_lookup($sa, $ctx);
        $self->_scan_aggregate_vars($ir);
        my $code = $self->_emit_program($ir);
        %_cfg_lookup = ();
        %_aggregate_vars = ();
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
            if (defined $state && (defined $state->{if_node} || defined $state->{loop} || defined $state->{try_node})) {
                my $ir_node = $node->extract();
                # Only register IR nodes that are directly associated with
                # control flow — not parent nodes (ClassDecl, MethodDecl,
                # Program) that inherit cfg_state from child If/Loop nodes.
                # cfg_state propagates upward through the Context comonad,
                # so without this guard, ClassDecl gets mapped to an If and
                # _emit_node emits a bare if-block instead of the class.
                if (defined $ir_node && ref($ir_node) && !exists $_cfg_lookup{refaddr($ir_node)}
                        && !($ir_node isa Chalk::IR::Program)
                        && !($ir_node isa Chalk::IR::UseInfo)
                        && !($ir_node isa Chalk::IR::ClassInfo)
                        && !($ir_node isa Chalk::IR::FieldInfo)
                        && !($ir_node isa Chalk::IR::MethodInfo)
                        && !($ir_node isa Chalk::IR::SubInfo)
                        && !($ir_node isa Chalk::Bootstrap::IR::Node::Constructor
                             && ($ir_node->class() eq 'Program'
                                 || $ir_node->class() eq 'ClassDecl'
                                 || $ir_node->class() eq 'MethodDecl'
                                 || $ir_node->class() eq 'SubDecl'
                                 || $ir_node->class() eq 'UseDecl'
                                 || $ir_node->class() eq 'FieldDecl'))) {
                    $_cfg_lookup{refaddr($ir_node)} = $state;
                }
            }
            push @stack, reverse $node->children()->@*;
        }
        return;
    }

    # Scan IR tree for VarDecl nodes with aggregate sigils (% or @).
    # Populates %_aggregate_vars so _emit_subscript_expr can emit
    # $hash{key} instead of $hash->{key} for hash variables.
    method _scan_aggregate_vars($ir) {
        my @stack = ($ir);
        while (@stack) {
            my $node = pop @stack;
            next unless defined $node && ref($node);
            if ($node isa Chalk::IR::Node::VarDecl) {
                my $var = $node->inputs()->[0];
                if (defined $var && $var isa Chalk::Bootstrap::IR::Node::Constant) {
                    my $name = $var->value();
                    if (defined $name && $name =~ /^([\@\%])(.+)/) {
                        $_aggregate_vars{$2} = $1;
                    }
                }
            }
            if ($node isa Chalk::IR::Program) {
                # Program metadata struct — push all contained items for traversal
                push @stack, $node->use_decls()->@*;
                push @stack, $node->classes()->@*;
                push @stack, $node->top_level_subs()->@*;
                push @stack, $node->other_stmts()->@*;
            } elsif ($node isa Chalk::IR::ClassInfo) {
                # ClassInfo metadata struct — push body items for traversal
                push @stack, $node->body()->@*;
            } elsif ($node isa Chalk::IR::FieldInfo) {
                # FieldInfo metadata struct — check for aggregate-sigil field names
                my $name = $node->name();
                if (defined $name && $name =~ /^([\@\%])(.+)/) {
                    $_aggregate_vars{$2} = $1;
                }
            } elsif ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
                # Also check legacy Constructor:FieldDecl for class-scope fields
                if ($node->class() eq 'FieldDecl') {
                    my $var = $node->inputs()->[0];
                    if (defined $var && $var isa Chalk::Bootstrap::IR::Node::Constant) {
                        my $name = $var->value();
                        if (defined $name && $name =~ /^([\@\%])(.+)/) {
                            $_aggregate_vars{$2} = $1;
                        }
                    }
                }
                for my $input ($node->inputs()->@*) {
                    if (ref($input) eq 'ARRAY') {
                        # Skip plain hashrefs (e.g., attribute data), push only IR nodes
                        push @stack, grep { ref($_) ne 'HASH' } @$input;
                    } elsif (ref($input) && ref($input) ne 'HASH') {
                        push @stack, $input;
                    }
                }
            } elsif (ref($node) && ref($node) ne 'HASH' && $node->can('inputs')) {
                for my $input ($node->inputs()->@*) {
                    if (ref($input) eq 'ARRAY') {
                        push @stack, grep { ref($_) ne 'HASH' } @$input;
                    } elsif (ref($input) && ref($input) ne 'HASH') {
                        push @stack, $input;
                    }
                }
            }
        }
    }

    method generate_distribution($ir) {
        # For Perl target, return a single file mapping
        my $code = $self->generate($ir);

        # Extract class name from the IR to determine file path
        my @stmts;
        if ($ir isa Chalk::IR::Program) {
            @stmts = ($ir->classes()->@*, $ir->top_level_subs()->@*);
        } else {
            @stmts = $ir->inputs()->[0]->@*;
        }
        my $class_name;
        for my $stmt (@stmts) {
            if ($stmt isa Chalk::IR::ClassInfo) {
                $class_name = $stmt->name();
                last;
            } elsif ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
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
        my @stmts;
        if ($node isa Chalk::IR::Program) {
            # Reassemble ordered output: use_decls first, then classes, top-level subs, other
            push @stmts, $node->use_decls()->@*;
            push @stmts, $node->classes()->@*;
            push @stmts, $node->top_level_subs()->@*;
            push @stmts, $node->other_stmts()->@*;
        } else {
            # Legacy Constructor:Program — stmts are inputs()->[0]
            @stmts = $node->inputs()->[0]->@*;
        }
        my @lines;
        for my $stmt (@stmts) {
            my $line = $self->_emit_node($stmt);
            push @lines, $line if defined $line;
        }
        return join("\n", @lines) . "\n";
    }

    method _emit_node($node) {
        return undef unless defined $node;

        # Check cfg_state lookup for control flow dispatch
        if (%_cfg_lookup && ref($node)) {
            my $state = $_cfg_lookup{refaddr($node)};
            if (defined $state) {
                if (defined $state->{if_node}) {
                    # loop_jump: emit 'next if/unless $cond' instead of block
                    if (defined $state->{loop_jump}) {
                        return $self->_emit_loop_jump(
                            $state->{loop_jump},
                            $state->{if_node},
                        );
                    }
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
                if (defined $state->{try_node}) {
                    return $self->emit_cfg_try_catch(
                        $state->{try_stmts}   // [],
                        $state->{catch_var},
                        $state->{catch_stmts} // [],
                    );
                }
            }
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            # Loop control keywords must be emitted as bare keywords, not quoted
            my $val = $node->value() // '';
            if ($val eq 'next' || $val eq 'last' || $val eq 'redo') {
                return "$val;";
            }
            return $self->_emit_constant($node);
        }

        # Typed fast-paths for computation nodes
        if ($node isa Chalk::IR::Node::BinOp
                || $node isa Chalk::IR::Node::UnaryOp
                || $node isa Chalk::IR::Node::Call
                || $node isa Chalk::IR::Node::Subscript
                || $node isa Chalk::IR::Node::PostfixDeref
                || $node isa Chalk::IR::Node::HashRef
                || $node isa Chalk::IR::Node::ArrayRef
                || $node isa Chalk::IR::Node::AnonSub
                || $node isa Chalk::IR::Node::RegexMatch
                || $node isa Chalk::IR::Node::RegexSubst
                || $node isa Chalk::IR::Node::BacktickExpr
                || $node isa Chalk::IR::Node::Interpolate) {
            return $self->_emit_expr($node) . ";";
        }
        if ($node isa Chalk::IR::Node::VarDecl) {
            return $self->_emit_var_decl($node);
        }
        if ($node isa Chalk::IR::Node::CompoundAssign) {
            return $self->_emit_compound_assign($node) . ";";
        }

        if ($node isa Chalk::IR::UseInfo) {
            return $self->_emit_use_decl($node);
        }

        if ($node isa Chalk::IR::FieldInfo) {
            return $self->_emit_field_decl($node);
        }

        if ($node isa Chalk::IR::MethodInfo) {
            return $self->_emit_method_decl($node);
        }

        if ($node isa Chalk::IR::SubInfo) {
            return $self->_emit_sub_decl($node);
        }

        if ($node isa Chalk::IR::ClassInfo) {
            return $self->_emit_class_decl($node);
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();

            if ($class eq 'Program')    { return $self->_emit_program($node); }
            if ($class eq 'UseDecl')    { return $self->_emit_use_decl($node); }
            if ($class eq 'ClassDecl')  { return $self->_emit_class_decl($node); }
            if ($class eq 'MethodDecl') { return $self->_emit_method_decl($node); }
            if ($class eq 'SubDecl')    { return $self->_emit_sub_decl($node); }
            if ($class eq 'ReturnStmt') { return $self->_emit_return_stmt($node); }
            if ($class eq 'DieCall')    { return $self->_emit_die_call($node); }
            if ($class eq 'FieldDecl')  { return $self->_emit_field_decl($node); }
            die "Unknown Constructor class: $class";
        }

        die "Unknown IR node type: " . ref($node);
    }

    method _emit_constant($node) {
        my $value = $node->value();
        return "'" . $self->_escape_single_quote($value) . "'";
    }

    method _emit_use_decl($node) {
        my ($module_name, $args);
        if ($node isa Chalk::IR::UseInfo) {
            $module_name = $node->name();
            $args = scalar($node->args()->@*) ? $node->args() : undef;
        } else {
            my $module = $node->inputs()->[0];
            $args      = $node->inputs()->[1];
            $module_name = $module->value();
        }

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
        my ($name, $parent, $body);
        if ($node isa Chalk::IR::ClassInfo) {
            $name   = $node->name();
            $parent = $node->parent();
            $body   = $node->body();
        } else {
            $name   = $node->inputs()->[0]->value();
            my $parent_node = $node->inputs()->[1];
            $parent = defined $parent_node ? $parent_node->value() : undef;
            $body   = $node->inputs()->[2];
        }

        my $decl = "class $name";
        if (defined $parent) {
            $decl .= " :isa($parent)";
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
        my ($name, $params, $body);
        if ($node isa Chalk::IR::MethodInfo) {
            $name   = $node->name();
            $params = $node->params();    # plain strings
            $body   = $node->body();
        } else {
            $name   = $node->inputs()->[0]->value();
            $params = $node->inputs()->[1];  # Constant nodes
            $body   = $node->inputs()->[2];
        }

        my $sig;
        if ($node isa Chalk::IR::MethodInfo) {
            $sig = '(' . join(', ', $params->@*) . ')';
        } else {
            $sig = '(' . join(', ', map { $_->value() } $params->@*) . ')';
        }
        # Scope aggregate vars: params shadow class-scope aggregate names
        my %saved = %_aggregate_vars;
        $self->_scope_body_vars($params, $body, $node isa Chalk::IR::MethodInfo);
        my $result = $self->_emit_body_block("method $name$sig {", $body);
        %_aggregate_vars = %saved;
        return $result;
    }

    # SubDecl inputs: [name, params, body, scope]
    # Dual-path: accepts Chalk::IR::SubInfo (plain strings) or Constructor:SubDecl (Constant nodes).
    method _emit_sub_decl($node) {
        my ($name, $params, $body, $scope);
        if ($node isa Chalk::IR::SubInfo) {
            $name   = $node->name();
            $params = $node->params();    # plain strings
            $body   = $node->body();
            $scope  = $node->scope();
        } else {
            $name   = $node->inputs()->[0]->value();
            $params = $node->inputs()->[1];  # Constant nodes
            $body   = $node->inputs()->[2];
            my $scope_node = $node->inputs()->[3];
            $scope  = defined $scope_node ? $scope_node->value() : 'package';
        }

        my $sig;
        if ($node isa Chalk::IR::SubInfo) {
            $sig = '(' . join(', ', $params->@*) . ')';
        } else {
            $sig = '(' . join(', ', map { $_->value() } $params->@*) . ')';
        }
        my $prefix = $scope eq 'package' ? 'sub' : "$scope sub";
        # Scope aggregate vars: params shadow class-scope aggregate names
        my %saved = %_aggregate_vars;
        $self->_scope_body_vars($params, $body, $node isa Chalk::IR::SubInfo);
        my $result = $self->_emit_body_block("$prefix $name$sig {", $body);
        %_aggregate_vars = %saved;
        return $result;
    }

    # Adjust %_aggregate_vars for a method/sub body scope.
    # Remove param names (params are always scalars) and add body-local
    # VarDecl aggregate names.
    # $params_are_strings: true when params are plain strings (MethodInfo/SubInfo),
    # false when params are Constant nodes (Constructor:MethodDecl/SubDecl).
    method _scope_body_vars($params, $body, $params_are_strings = false) {
        # Params shadow: $reachable param means $reachable is a scalar here
        for my $p ($params->@*) {
            my $pname = $params_are_strings ? $p : $p->value();
            if ($pname =~ /^\$(.+)/) {
                delete $_aggregate_vars{$1};
            }
        }
        # Add body-local aggregate VarDecls
        for my $item ($body->@*) {
            next unless $item isa Chalk::IR::Node::VarDecl;
            my $var = $item->inputs()->[0];
            next unless defined $var && $var isa Chalk::Bootstrap::IR::Node::Constant;
            my $vname = $var->value();
            if (defined $vname && $vname =~ /^([\@\%])(.+)/) {
                $_aggregate_vars{$2} = $1;
            }
        }
    }

    method _emit_body_block($decl_line, $body) {
        my @lines = ($decl_line);
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
        my ($name, $attrs, $default_value);
        if ($node isa Chalk::IR::FieldInfo) {
            $name          = $node->name();
            $attrs         = $node->attributes();
            $default_value = $node->default_value();
        } else {
            my $name_node  = $node->inputs()->[0];
            $name          = $name_node->value();
            $attrs         = $node->inputs()->[1];
            $default_value = $node->inputs()->[2];
        }
        my $decl = "field $name";

        if (ref($attrs) eq 'ARRAY' && $attrs->@*) {
            for my $attr ($attrs->@*) {
                my $attr_name;
                if (ref($attr) eq 'HASH') {
                    $attr_name = $attr->{name};
                } else {
                    # Legacy Constructor:_Attribute node
                    $attr_name = $attr->inputs()->[0]->value();
                }
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
            # Regex literals — emit bare (not quoted)
            if ($ct eq 'regex') {
                return $val;
            }
            return "'" . $self->_escape_single_quote($val) . "'";
        }

        # Typed fast-paths for computation nodes
        if ($node isa Chalk::IR::Node::Interpolate) { return $self->_emit_interpolated_string($node); }
        if ($node isa Chalk::IR::Node::BinOp)       { return $self->_emit_binary_expr($node); }
        if ($node isa Chalk::IR::Node::UnaryOp)     { return $self->_emit_unary_expr($node); }
        if ($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'method') {
            return $self->_emit_method_call_expr($node);
        }
        if ($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'builtin') {
            return $self->_emit_builtin_call($node);
        }
        if ($node isa Chalk::IR::Node::Subscript)   { return $self->_emit_subscript_expr($node); }
        if ($node isa Chalk::IR::Node::PostfixDeref) { return $self->_emit_postfix_deref_expr($node); }
        if ($node isa Chalk::IR::Node::HashRef)     { return $self->_emit_hash_ref_expr($node); }
        if ($node isa Chalk::IR::Node::ArrayRef)    { return $self->_emit_array_ref_expr($node); }
        if ($node isa Chalk::IR::Node::AnonSub)     { return $self->_emit_anon_sub_expr($node); }
        if ($node isa Chalk::IR::Node::RegexMatch)  { return $self->_emit_regex_match($node); }
        if ($node isa Chalk::IR::Node::RegexSubst)  { return $self->_emit_regex_subst($node); }
        if ($node isa Chalk::IR::Node::BacktickExpr) { return $self->_emit_backtick_expr($node); }
        if ($node isa Chalk::IR::Node::CompoundAssign) { return $self->_emit_compound_assign($node); }
        if ($node isa Chalk::IR::Node::VarDecl)     { return $self->_emit_var_decl_expr($node); }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();
            if ($class eq 'TernaryExpr')  { return $self->_emit_ternary_expr($node); }
            if ($class eq 'StructRef')    { return $self->_emit_struct_ref_expr($node); }
            if ($class eq 'FieldAccess')  { return $self->_emit_field_access_expr($node); }
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
        my $needs_parens = ($operand isa Chalk::IR::Node::BinOp)
            || ($operand isa Chalk::Bootstrap::IR::Node::Constructor
                && $operand->class() eq 'TernaryExpr');

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

    # Prefix builtins that take a single argument and should absorb subscripts:
    # exists $hash{key}, delete $arr[0], defined $h{k}, etc.
    my %SUBSCRIPT_ABSORBING_BUILTINS = map { $_ => 1 }
        qw(exists delete defined scalar ref);

    method _emit_subscript_expr($node) {
        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2]->value();

        # Fix stale-value merge: SubscriptExpr(BuiltinCall(exists, [$var]), $key)
        # should emit as exists($var->{$key}), not exists($var)->{$key}.
        # Push the subscript inside the builtin argument.
        if (defined $target
                && ($target isa Chalk::IR::Node::Call && $target->dispatch_kind() eq 'builtin')) {
            my $bname = $target->inputs()->[0]->value();
            if ($SUBSCRIPT_ABSORBING_BUILTINS{$bname}) {
                my @args = $target->inputs()->[1]->@*;
                my $inner = $args[-1];
                my $inner_expr = $self->_emit_expr($inner);
                my $sub_expr = $self->_format_subscript($inner_expr, $index, $style);
                my @other_args = map { $self->_emit_expr($_) } @args[0 .. $#args - 1];
                return "$bname(" . join(', ', @other_args, $sub_expr) . ")";
            }
        }

        # Fix stale-value merge: SubscriptExpr(UnaryExpr(!, BuiltinCall(exists, ...)), $key)
        # Push the subscript past the unary op into the builtin argument.
        if (defined $target
                && ($target isa Chalk::IR::Node::UnaryOp)) {
            my $op = $target->inputs()->[0]->value();
            my $operand = $target->inputs()->[1];
            if ($operand isa Chalk::IR::Node::Call && $operand->dispatch_kind() eq 'builtin') {
                my $bname = $operand->inputs()->[0]->value();
                if ($SUBSCRIPT_ABSORBING_BUILTINS{$bname}) {
                    my @args = $operand->inputs()->[1]->@*;
                    my $inner = $args[-1];
                    my $inner_expr = $self->_emit_expr($inner);
                    my $sub_expr = $self->_format_subscript($inner_expr, $index, $style);
                    my @other_args = map { $self->_emit_expr($_) } @args[0 .. $#args - 1];
                    return "$op$bname(" . join(', ', @other_args, $sub_expr) . ")";
                }
            }
        }

        my $tgt = defined $target ? $self->_emit_expr($target) : '$self';

        # Direct hash/array element: if the target is a $ variable whose name
        # was declared with % or @ sigil, emit direct subscript (no arrow).
        # $hash{key} for %hash, $arr[idx] for @array.
        if ($tgt =~ /^\$(.+)/ && %_aggregate_vars && exists $_aggregate_vars{$1}) {
            if ($style eq 'array') {
                return "$tgt\[" . $self->_emit_expr($index) . "]";
            }
            if ($style ne 'call') {
                return "$tgt\{" . $self->_emit_expr($index) . "}";
            }
        }

        if ($style eq 'array') {
            return "$tgt\->[" . $self->_emit_expr($index) . "]";
        }
        if ($style eq 'call') {
            # Coderef call: $f->($arg1, $arg2)
            my @args;
            if (ref($index) eq 'ARRAY') {
                @args = map { $self->_emit_expr($_) } $index->@*;
            } elsif (defined $index) {
                @args = ($self->_emit_expr($index));
            }
            return "$tgt\->(" . join(', ', @args) . ")";
        }
        return "$tgt\->{" . $self->_emit_expr($index) . "}";
    }

    # Format a subscript access, using direct syntax for aggregate vars.
    method _format_subscript($tgt_expr, $index_node, $style) {
        my $idx = $self->_emit_expr($index_node);
        my $is_aggregate = ($tgt_expr =~ /^\$(.+)/ && %_aggregate_vars
                            && exists $_aggregate_vars{$1});
        if ($style eq 'array') {
            return $is_aggregate ? "${tgt_expr}[$idx]" : "${tgt_expr}->[$idx]";
        }
        return $is_aggregate ? "${tgt_expr}\{$idx}" : "${tgt_expr}->{$idx}";
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

    # Lower StructRef back to hash constructor: { key1 => val1, key2 => val2, ... }
    method _emit_struct_ref_expr($node) {
        my $schema_name = $node->inputs()->[0]->value();
        my $field_vals  = $node->inputs()->[1];

        my $schema = $_struct_schemas->{$schema_name};
        unless (defined $schema) {
            # Fallback: emit as empty hash if schema not found
            return '{}';
        }

        my @fields = $schema->{fields}->@*;
        my @pairs;
        for my $i (0 .. $#fields) {
            my $key = "'" . $fields[$i]{name} . "'";
            my $val = (defined $field_vals && $i < scalar($field_vals->@*))
                ? $self->_emit_expr($field_vals->[$i])
                : 'undef';
            push @pairs, "$key => $val";
        }

        return '{ ' . join(', ', @pairs) . ' }';
    }

    # Lower FieldAccess back to hash key access: $target->{'field_name'}
    method _emit_field_access_expr($node) {
        my $target     = $node->inputs()->[2];
        my $field_name = $node->inputs()->[1]->value();

        my $tgt = defined $target ? $self->_emit_expr($target) : '$self';
        return "$tgt\->{'$field_name'}";
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

    # Emit 'next if/unless $cond' from an If CFG node with loop_jump marker.
    # PostfixModifier negated the condition for 'unless', so the If node's
    # condition is !($original). We detect the negation wrapper and strip it
    # to emit 'next unless $original' for readability.
    # The If node is found via _build_cfg_lookup (cfg_state side-table keyed
    # by IR node refaddr). GCM/DCE passes that need to see this conditional
    # branch must walk cfg_state, not just the IR statement list.
    method _emit_loop_jump($jump_keyword, $if_node) {
        my $cond = $if_node->inputs()->[1];
        # Detect negation wrapper: UnaryExpr('!', expr) → emit 'unless expr'
        if (($cond isa Chalk::IR::Node::UnaryOp)
                && $cond->inputs()->[0] isa Chalk::Bootstrap::IR::Node::Constant
                && $cond->inputs()->[0]->value() eq '!') {
            my $inner = $cond->inputs()->[1];
            return "$jump_keyword unless " . $self->_emit_expr($inner) . ";";
        }
        return "$jump_keyword if " . $self->_emit_expr($cond) . ";";
    }

    # Emit Perl if/else from an If CFG node with true/false Proj branches.
    # $true_proj/$false_proj: retained for future GCM/peephole passes
    # that schedule data-flow nodes relative to Proj control anchors.
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
    # $loop/$body_proj/$exit_proj: retained for future GCM/peephole passes.
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

        # Try/catch: cfg_state has try_node
        if (defined $state->{try_node}) {
            return $self->emit_cfg_try_catch(
                $state->{try_stmts}   // [],
                $state->{catch_var},
                $state->{catch_stmts} // [],
            );
        }

        return;
    }

    # Emit Perl try { ... } catch ($var) { ... } from cfg_state.
    method emit_cfg_try_catch($try_stmts, $catch_var, $catch_stmts) {
        my @lines;
        push @lines, "try {";
        for my $stmt ($try_stmts->@*) {
            my $code = $self->_emit_node($stmt);
            if (defined $code) {
                for my $line (split /\n/, $code) {
                    push @lines, "    $line";
                }
            }
        }
        push @lines, "} catch ($catch_var) {";
        for my $stmt ($catch_stmts->@*) {
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
}

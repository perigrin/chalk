# ABOUTME: Walks Perl IR and emits native C code for each class method.
# ABOUTME: Generates a .c implementation file and a .h header file per class.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Perl::Target::EmitHelpers;
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::IR::Node;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::BinOp;
use Chalk::IR::Node::HashRef;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::AnonSub;
use Chalk::IR::UseInfo;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;

class Chalk::Bootstrap::Perl::Target::C :isa(Chalk::Bootstrap::Perl::Target::EmitHelpers) {
    field @_anon_sub_helpers;  # accumulated static C functions for anonymous subs
    field $_anon_sub_counter = 0;  # monotonic counter for unique anonymous sub names
    field @_exported_functions;    # list of exported C function names
    field @_skipped_methods;       # list of method names that could not be compiled
    field @_anon_sub_registrations; # list of { name => ..., c_name => ... } for anon sub registration
    field $field_types :param = {};  # hashref: field_name => class_name for known-typed fields
    field $_field_type_slugs;        # hashref: field_name => C slug, derived from field_types
    field $compiled_class_metadata :param = {};  # hashref: class_name => { slug, readers, methods }
    field $_method_dispatch;  # hashref: method_name => { type => 'reader'|'method', ... }
    field $_polymorphic_dispatch;  # hashref: method_name => [{ slug, class_name }, ...] for stash-compare chains
    method _method_dispatch() { return $_method_dispatch; }
    method _polymorphic_dispatch() { return $_polymorphic_dispatch; }
    method _class_slug_for($class_name) {
        return $self->_class_slug($class_name);
    }
    method _analyze_class($ir) {
        my $class_decl = $self->_find_class_decl($ir);
        return unless defined $class_decl;

        # Set the current class slug for identifier namespacing
        my $class_name = $class_decl isa Chalk::IR::ClassInfo
            ? $class_decl->name()
            : $class_decl->inputs()->[0]->value();
        $self->_set_current_slug($self->_class_slug($class_name));

        # Build field map once and store it for use throughout code generation
        $self->_set_field_map($self->_build_field_index_map($class_decl));

        # Pre-scan methods to build $self->_get_class_methods_ref() for direct call optimization
        $self->_set_class_methods($self->_scan_class_methods($class_decl));

        my $body = $class_decl isa Chalk::IR::ClassInfo
            ? $class_decl->body()
            : $class_decl->inputs()->[2];

        # Collect class-scope variable metadata from ALL VarDecl items in class body.
        # These are compiled as static C variables, initialized at module load time.
        $self->_reset_class_scope_vars();
        for my $item ($body->@*) {
            next unless $item isa Chalk::IR::Node::VarDecl;
            my $raw_var = $item->inputs()->[0]->value();
            my $sigil = substr($raw_var, 0, 1);
            my $var = $raw_var;
            $var =~ s/^[\$\@\%]//;
            my $init = $item->inputs()->[1];
            # Skip VarDecl whose init is a SubDecl/SubInfo (those are sub definitions)
            next if defined $init
                && $init isa Chalk::Bootstrap::IR::Node::Constructor
                && $init->class() eq 'SubDecl';
            next if defined $init && $init isa Chalk::IR::SubInfo;
            # Skip VarDecl for variables that are fields (ADJUST assigns them,
            # but they're already handled by the field map)
            next if defined $self->_get_field_map() && exists $self->_get_field_map()->{$var};
            $self->_set_class_scope_var($var, {
                sigil       => $sigil,
                init        => $init,
                static_name => "_csv_" . $self->_get_current_slug() . "_${var}",
            });
        }

        # Extract `use constant { NAME => value, ... }` declarations.
        # Constants are inlined as numeric literals in the generated C,
        # since C doesn't have Perl's constant sub mechanism.
        $self->_reset_use_constants();
        for my $item ($body->@*) {
            my ($use_name, $use_args);
            if ($item isa Chalk::IR::UseInfo) {
                $use_name = $item->name();
                $use_args = $item->args();
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                     && $item->class() eq 'UseDecl') {
                my $mn = $item->inputs()->[0];
                next unless defined $mn;
                $use_name = $mn->value();
                my $raw = $item->inputs()->[1];
                $use_args = defined $raw
                    ? (ref($raw) eq 'ARRAY' ? $raw : [$raw])
                    : [];
            } else {
                next;
            }
            next unless defined $use_name && $use_name eq 'constant';
            my $args = $use_args;
            next unless defined $args && ref($args) eq 'ARRAY';
            my $hash_expr = $args->[0];
            next unless $hash_expr isa Chalk::IR::Node::HashRef;
            my $pairs = $hash_expr->inputs()->[0];
            next unless defined $pairs && ref($pairs) eq 'ARRAY';
            for (my $i = 0; $i < $pairs->@*; $i += 2) {
                my $key_node = $pairs->[$i];
                my $val_node = $pairs->[$i + 1];
                next unless $key_node isa Chalk::Bootstrap::IR::Node::Constant;
                next unless $val_node isa Chalk::Bootstrap::IR::Node::Constant;
                my $kv = $key_node->value();
                my $vv = $val_node->value();
                # Only inline numeric constant values
                if ($vv =~ /^-?[0-9]+$/) {
                    $self->_set_use_constant($kv, $vv);
                }
            }
        }

        return;
    }
    method _emit_method($method_decl) {
        my ($name, $params, $body);
        if ($method_decl isa Chalk::IR::MethodInfo) {
            $name = $method_decl->name();
            $body = $method_decl->body();
            # Normalize plain string params to Constant nodes so downstream
            # code can uniformly call ->value() on each param.
            my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
            $params = [
                map { $factory->make('Constant', const_type => 'variable', value => $_) }
                    $method_decl->params()->@*
            ];
        } else {
            $name   = $method_decl->inputs()->[0]->value();
            $params = $method_decl->inputs()->[1];  # Constant nodes
            $body   = $method_decl->inputs()->[2];
        }

        my $func_name = "${\  $self->_get_current_slug()}_${name}";

        if (scalar $body->@* == 1) {
            my $body_item = $body->[0];
            my $returns_value = (defined $body_item
                && $body_item isa Chalk::IR::Node::Return);
            my $dies = (defined $body_item
                && $body_item isa Chalk::IR::Node::Unwind);

            if ($returns_value) {
                my $value = $body_item->inputs()->[1];  # inputs[0]=control, inputs[1]=value

                if ($value isa Chalk::IR::Node::Interpolate) {
                    return $self->_emit_interp_return($name, $value);
                } elsif ($value isa Chalk::Bootstrap::IR::Node::Constant
                         && ($value->const_type() // '') ne 'variable'
                         && $value->value() !~ /^[\$\@\%]/) {
                    my $str = $self->_escape_c_string($value->value());
                    my $c_expr = "newSVpvs(\"$str\")";
                    my $raw = $value->value();
                    if ($raw eq '1' || $raw eq 'true') {
                        $c_expr = '&PL_sv_yes';
                    } elsif ($raw eq '0' || $raw eq 'false' || $raw eq '') {
                        $c_expr = '&PL_sv_no';
                    } elsif ($raw eq 'undef') {
                        $c_expr = '&PL_sv_undef';
                    } elsif ($raw =~ /\A-?\d+\z/) {
                        $c_expr = "newSViv($raw)";
                    }
                    my @c_params = ('SV *self');
                    for my $p ($params->@*) {
                        my $pname = $p->value();
                        $pname =~ s/^\$//;
                        push @c_params, "SV *$pname";
                    }
                    my @helper;
                    push @helper, "SV * ${func_name}(pTHX_ " . join(', ', @c_params) . ") {";
                    for my $p (@c_params) {
                        push @helper, "    PERL_UNUSED_ARG(${\($p =~ s/^SV \*//r)});"
                            unless $p =~ /^SV \*self$/;
                    }
                    push @helper, "    return $c_expr;";
                    push @helper, "}";
                    push @_exported_functions, {
                        name        => $func_name,
                        return_type => 'SV *',
                        params      => 'pTHX_ ' . join(', ', @c_params),
                    };
                    return { helper => \@helper };
                }
            }

            if ($dies) {
                my $args = $body_item->inputs()->[0];
                my $msg = '';
                if (ref($args) eq 'ARRAY' && $args->@*) {
                    $msg = $self->_escape_c_string($args->[0]->value());
                }

                my @c_params = ('SV *self');
                for my $p ($params->@*) {
                    my $pname = $p->value();
                    $pname =~ s/^\$//;
                    push @c_params, "SV *$pname";
                }

                my @helper;
                push @helper, "void ${func_name}(pTHX_ " . join(', ', @c_params) . ") {";
                push @helper, "    croak(\"%s\", \"$msg\");";
                push @helper, "}";
                push @_exported_functions, {
                    name        => $func_name,
                    return_type => 'void',
                    params      => 'pTHX_ ' . join(', ', @c_params),
                };
                return { helper => \@helper };
            }
        }

        if ($body->@* == 0) {
            my @helper;
            push @helper, "void ${func_name}(pTHX_ SV *self) {";
            push @helper, "    PERL_UNUSED_ARG(self);";
            push @helper, "    /* empty */";
            push @helper, "}";
            push @_exported_functions, {
                name        => $func_name,
                return_type => 'void',
                params      => 'pTHX_ SV *self',
            };
            return { helper => \@helper };
        }

        my $return_type;
        if ($method_decl isa Chalk::IR::MethodInfo) {
            $return_type = $method_decl->return_type();  # already a plain string
        } else {
            my $return_type_node = $method_decl->inputs()->[3];
            $return_type = $return_type_node ? $return_type_node->value() : undef;
        }
        return $self->_emit_complex_method($name, $params, $body, $return_type);
    }

    # Emit a multi-statement method body as a C helper + XSUB wrapper.
    method _emit_complex_method($name, $params, $body, $ir_return_type = undef) {
        my @code;

        my $last_item = $body->[-1];
        my $last_is_return = (defined $last_item
            && $last_item isa Chalk::IR::Node::Return);
        my $body_has_returns = $self->_body_contains_return($body);
        my $single_stmt_return = (!$last_is_return
            && scalar($body->@*) == 1
            && defined $last_item
            && $self->_is_single_stmt_return_expr($last_item));
        my $tail_expr_return = (!$last_is_return
            && defined $last_item
            && ($self->_is_unambiguous_value_expr($last_item)
                || ($body_has_returns && $self->_is_bare_return_expr($last_item)))
            );
        my $heuristic_has_return = $last_is_return || $tail_expr_return
               || $single_stmt_return || $body_has_returns;
        my $has_return;
        if (defined $ir_return_type && $ir_return_type eq 'Void'
                && ($last_is_return || $body_has_returns)) {
            $has_return = true;
            $ir_return_type = 'Any';
        } elsif (defined $ir_return_type) {
            $has_return = $ir_return_type ne 'Void';
        } else {
            $has_return = $heuristic_has_return;
        }

        my %declared_vars;

        my @xs_params = ('SV *self');
        for my $p ($params->@*) {
            my $pname = $p->value();
            $pname =~ s/^[\$\@\%]//;
            push @xs_params, "SV *$pname";
            $declared_vars{"param:$pname"} = true;
        }

        $self->_collect_var_decls($body, \%declared_vars);
        $self->_collect_all_var_refs($body, \%declared_vars);

        my $has_early_return = $self->_has_early_return($body);

        my $prev_return_context = $self->_get_return_context();
        $self->_set_return_context($has_return);

        for my $idx (0 .. $body->@* - 1) {
            my $is_last = ($idx == $body->@* - 1);
            my $stmt = $self->_emit_stmt($body->[$idx], \%declared_vars, $is_last);
            push @code, $stmt if defined $stmt;
        }

        if (!$last_is_return && @code) {
            my $last_code = $code[-1];
            if ($last_code =~ /\n/) {
                my @parts = split(/\n/, $last_code);
                my $final_line = pop @parts;
                $code[-1] = join("\n", @parts);
                if ($final_line =~ s/;\s*$//) {
                    if ($final_line =~ /^(?:sv_setsv|hv_clear|av_clear)\b/) {
                        push @code, "$final_line;";
                    } else {
                        my $wrapped = $self->_wrap_retval($final_line);
                        push @code, "retval = $wrapped;";
                    }
                } else {
                    push @code, $final_line;
                }
            } else {
                if ($last_code =~ s/;\s*$//) {
                    if ($last_code =~ /^(?:sv_setsv|hv_clear|av_clear)\b/) {
                        $code[-1] = "$last_code;";
                    } else {
                        my $wrapped = $self->_wrap_retval($last_code);
                        $code[-1] = "retval = $wrapped;";
                    }
                }
            }
        }

        $self->_set_return_context($prev_return_context);

        my @helper;
        # Exported C function: no "static", no "_impl_" prefix.
        # Called from Boolean.xs via the function pointer or direct call.
        my $func_name = "${\  $self->_get_current_slug()}_${name}";
        my $c_ret_type = $has_return ? $self->_xs_c_type_for($ir_return_type) : 'void';
        push @helper, "$c_ret_type ${func_name}(pTHX_ " . join(', ', @xs_params) . ") {";

        if ($has_return) {
            push @helper, '    SV *retval = NULL;';
        }
        for my $var (sort keys %declared_vars) {
            next if $var eq 'hash';
            next if $var =~ /^param:/;
            push @helper, "    SV *${var}_sv = NULL;";
        }

        for my $stmt (@code) {
            my $rewritten = $stmt;
            $rewritten =~ s/\bRETVAL\b/retval/g;
            $rewritten =~ s/\breturn\s*;/return \&PL_sv_undef;/g;
            for my $line (split /\n/, $rewritten) {
                push @helper, "    $line";
            }
        }

        if ($has_early_return) {
            push @helper, '    xsreturn:';
        }
        if ($has_return) {
            push @helper, '    return retval;';
        } elsif ($c_ret_type ne 'void') {
            push @helper, '    return &PL_sv_undef;';
        }
        push @helper, '}';

        # Track exported function for .h generation.
        # The .h prototype needs pTHX_ as the first parameter for threaded perls.
        push @_exported_functions, {
            name        => $func_name,
            return_type => $c_ret_type,
            params      => 'pTHX_ ' . join(', ', @xs_params),
        };

        return { helper => \@helper, returns => $has_return };
    }

    # Emit a class-scope sub declaration as a static C helper function.
    method _emit_sub($name, $params, $body) {
        my @code;

        # Track current sub name for __SUB__ recursion resolution.
        # Save/restore both _current_sub_name and _return_context so that
        # an exception during body compilation does not leak state into
        # subsequent method/sub compilation within the same class.
        my $prev_sub_name = $self->_get_current_sub_name();
        my $prev_return_context = $self->_get_return_context();
        $self->_set_current_sub_name($name);

        my $result = eval {

        my $last_item = $body->[-1];
        my $last_is_return = (defined $last_item
            && $last_item isa Chalk::IR::Node::Return);
        $last_is_return ||= (defined $last_item
            && $last_item isa Chalk::Bootstrap::IR::Node::Constant
            && ($last_item->value() // '') eq 'return');
        my $body_has_returns = $self->_body_contains_return($body);
        my $single_stmt_return = (!$last_is_return
            && scalar($body->@*) == 1
            && defined $last_item
            && $self->_is_single_stmt_return_expr($last_item));
        my $tail_expr_return = (!$last_is_return
            && defined $last_item
            && ($self->_is_unambiguous_value_expr($last_item)
                || ($body_has_returns && $self->_is_bare_return_expr($last_item)))
            );
        my $has_return = $last_is_return || $tail_expr_return
               || $single_stmt_return || $body_has_returns;

        my %declared_vars;

        my @xs_params;
        for my $p ($params->@*) {
            my $pname;
            if ($p isa Chalk::Bootstrap::IR::Node) {
                $pname = $p->value();
            } else {
                $pname = "$p";
            }
            $pname =~ s/^[\$\@\%]//;
            push @xs_params, "SV *$pname";
            $declared_vars{"param:$pname"} = true;
        }

        $self->_collect_var_decls($body, \%declared_vars);
        $self->_collect_all_var_refs($body, \%declared_vars);

        my $has_early_return = $self->_has_early_return($body);

        $self->_set_return_context($has_return);

        for my $idx (0 .. $body->@* - 1) {
            my $is_last = ($idx == $body->@* - 1);
            my $stmt = $self->_emit_stmt($body->[$idx], \%declared_vars, $is_last);
            push @code, $stmt if defined $stmt;
        }

        if (!$last_is_return && @code) {
            my $last_code = $code[-1];
            if ($last_code =~ s/;\s*$//) {
                if ($last_code =~ /^(?:sv_setsv|hv_clear|av_clear)\b/) {
                    $code[-1] = "$last_code;";
                } else {
                    my $wrapped = $self->_wrap_retval($last_code);
                    $code[-1] = "retval = $wrapped;";
                    $has_return = true;
                }
            }
        }

        my @helper;
        # Class-scope subs are static helpers — not exported, not in the .h file.
        my $helper_name = "${\  $self->_get_current_slug()}_${name}";
        my $param_str = @xs_params ? 'pTHX_ ' . join(', ', @xs_params) : 'pTHX';
        push @helper, "static SV * $helper_name($param_str) {";

        push @helper, '    SV *retval = NULL;';
        for my $var (sort keys %declared_vars) {
            next if $var eq 'hash';
            next if $var =~ /^param:/;
            push @helper, "    SV *${var}_sv = NULL;";
        }

        for my $stmt (@code) {
            my $rewritten = $stmt;
            $rewritten =~ s/\bRETVAL\b/retval/g;
            $rewritten =~ s/\breturn\s*;/return \&PL_sv_undef;/g;
            for my $line (split /\n/, $rewritten) {
                push @helper, "    $line";
            }
        }

        if ($has_early_return) {
            push @helper, '    xsreturn:';
        }
        if ($has_return) {
            push @helper, '    return retval;';
        } else {
            push @helper, '    return &PL_sv_undef;';
        }
        push @helper, '}';

        { helper => \@helper };
        }; # end eval

        # Always restore state, even if body compilation threw
        $self->_set_current_sub_name($prev_sub_name);
        $self->_set_return_context($prev_return_context);

        die $@ if $@;
        return $result;
    }

    # Emit a Constant IR node as a C expression

    # Emit an InterpolatedString as a C expression building an SV via
    # sv_catpvs/sv_catsv. Variables are resolved from the declared_vars
    # (local C vars) or ObjectFIELDS (field access).

    # Emit binary expression as C code using Perl API

    # Emit unary expression

    # Emit method call using dSP/PUSHMARK/call_method/SPAGAIN stack protocol.
    # Uses GCC statement expression to return the method's scalar result.
    # Arguments containing nested method calls (dSP) are pre-evaluated into
    # temp variables before any XPUSHs — nested dSP reads PL_stack_sp which
    # would clobber the outer stack entries if evaluated inline.
    method _emit_method_call_expr($node, $declared_vars) {
        my ($invocant_node, $method_name, $args);
        if ($node isa Chalk::IR::Node::Call) {
            # Typed Call node: inputs() = [invocant, arg0, arg1, ...]
            $invocant_node = $node->inputs()->[0];
            $method_name   = $node->name();
            $args          = [ $node->inputs()->@[1 .. $node->inputs()->$#*] ];
        } else {
            # Constructor MethodCallExpr: inputs() = [invocant, name_const, args_arrayref]
            $invocant_node = $node->inputs()->[0];
            $method_name   = $node->inputs()->[1]->value();
            $args          = $node->inputs()->[2];
        }

        # Determine invocant C expression ($self if undef).
        # If the invocant is wrapped in PostfixDerefExpr('$'), unwrap it:
        # call_method needs the blessed reference on the stack, not SvRV(ref).
        my $invocant_expr;
        if (defined $invocant_node) {

            if ($invocant_node isa Chalk::IR::Node::PostfixDeref) {
                # Unwrap any PostfixDeref sigil ($, $#, @, %) — call_method
                # needs the blessed object reference, not a dereferenced value.
                $invocant_expr = $self->_emit_expr($invocant_node->inputs()->[0], $declared_vars);
            } else {
                $invocant_expr = $self->_emit_expr($invocant_node, $declared_vars);
            }
        } else {
            $invocant_expr = 'self';
        }

        my $escaped_name = $self->_escape_c_string($method_name);

        # Pre-evaluate args that contain nested method calls or complex
        # expressions with dSP. These must be evaluated before PUSHMARK
        # because nested dSP reads PL_stack_sp which hasn't been updated
        # by the outer XPUSHs calls yet, clobbering the stack.
        my @pre_eval;
        my @arg_exprs;
        for my $arg ($args->@*) {
            my $arg_expr = $self->_emit_expr($arg, $declared_vars);
            if ($arg_expr =~ /\bdSP\b/) {
                my $tmp = '_mca' . scalar(@pre_eval);
                push @pre_eval, "SV *$tmp = $arg_expr";
                push @arg_exprs, $tmp;
            } else {
                push @arg_exprs, $arg_expr;
            }
        }
        # Also pre-evaluate invocant if it contains dSP
        if ($invocant_expr =~ /\bdSP\b/) {
            my $tmp = '_mci';
            push @pre_eval, "SV *$tmp = $invocant_expr";
            $invocant_expr = $tmp;
        }

        # Self-call optimization: when invocant is self and method exists in this
        # class, call the C function directly instead of Perl method dispatch.
        # All exported C functions return SV* — no SvREFCNT_inc needed because
        # direct C calls return owned SVs (unlike call_method/POPs which returns
        # a mortal needing refcount bump).
        # Skip methods that failed C compilation — they exist in Perl but not as
        # C functions, so call_method dispatch is required.
        my %_skipped_set = map { $_ => 1 } @_skipped_methods;
        if ($invocant_expr eq 'self' && defined $self->_get_class_methods()
                && exists $self->_get_class_methods()->{$method_name}
                && !exists $_skipped_set{$method_name}) {
            my $slug = $self->_get_current_slug();
            my $c_func_name = "${slug}_${method_name}";
            my @call_args = ('self', @arg_exprs);
            my $args_str = join(', ', @call_args);
            my @stmts;
            push @stmts, @pre_eval;
            push @stmts, "${c_func_name}(aTHX_ ${args_str})";
            return '({ ' . join('; ', @stmts) . '; })';
        }

        # Direct cross-class call optimization: when the invocant is a known-typed
        # field, emit {target_slug}_{method}(aTHX_ {invocant}, {args...}) instead
        # of the generic call_method dSP/PUSHMARK/POPs sequence.
        # This requires field_types to declare the target class for the field.
        # Skip UNIVERSAL methods (can, isa, DOES, VERSION) — these are inherited
        # from Perl's UNIVERSAL class and are not compiled into any target class.
        my %_universal_methods = ('can' => 1, 'isa' => 1, 'DOES' => 1, 'VERSION' => 1);
        if ($_field_type_slugs && keys $_field_type_slugs->%*
                && !exists $_universal_methods{$method_name}) {
            # Identify when the invocant node is a plain variable referencing a typed field.
            # The invocant_node is a Constant with the field name as its value.
            my $field_name;
            if (defined $invocant_node
                    && $invocant_node isa Chalk::Bootstrap::IR::Node::Constant) {
                my $raw = $invocant_node->value();
                # Strip leading sigil if present (e.g., "$semiring" → "semiring")
                (my $bare = $raw) =~ s/^[\$\@\%]//;
                $field_name = $bare if exists $_field_type_slugs->{$bare};
            }
            if (defined $field_name) {
                my $target_slug  = $_field_type_slugs->{$field_name};
                my $c_func_name  = "${target_slug}_${method_name}";
                my @call_args    = ($invocant_expr, @arg_exprs);
                my $args_str     = join(', ', @call_args);
                my @stmts;
                push @stmts, @pre_eval;
                push @stmts, "SV *_mcr = SvREFCNT_inc(${c_func_name}(aTHX_ ${args_str}))";
                push @stmts, '_mcr';
                return '({ ' . join('; ', @stmts) . '; })';
            }
        }

        # Type-aware dispatch: when compiled_class_metadata maps method names to
        # known classes, dispatch based on whether it's a :reader (ObjectFIELDS)
        # or an explicit method (direct C call).
        if ($_method_dispatch && exists $_method_dispatch->{$method_name}) {
            my $info = $_method_dispatch->{$method_name};
            if ($info->{type} eq 'reader') {
                # :reader accessor — direct field access via ObjectFIELDS
                my $idx = $info->{field_idx};
                my @stmts;
                push @stmts, @pre_eval;
                push @stmts, "ObjectFIELDS(SvRV($invocant_expr))[$idx]";
                return '({ ' . join('; ', @stmts) . '; })';
            }
            elsif ($info->{type} eq 'method') {
                # Explicit method — direct C call (no SvREFCNT_inc, returns owned SV)
                my $slug = $info->{slug};
                my $c_func_name = "${slug}_${method_name}";
                my @call_args = ($invocant_expr, @arg_exprs);
                my $args_str = join(', ', @call_args);
                my @stmts;
                push @stmts, @pre_eval;
                push @stmts, "${c_func_name}(aTHX_ ${args_str})";
                return '({ ' . join('; ', @stmts) . '; })';
            }
        }

        # NOTE: XS-only dispatch paths ($_cv_cache, $_composite_field_types,
        # $_semiring_intrinsics, %_multi_class_methods, $_class_registry,
        # %_fallback_method_slugs, $self->_get_param_fields()) are not available in the
        # C target. Fall through to standard call_method dispatch.

        # Polymorphic dispatch: when multiple compiled classes implement this method,
        # emit a stash-compare chain with direct C calls and a call_method fallback.
        # Each stash pointer is initialized in init_statics via gv_stashpvn and stored
        # in a file-scope static for O(1) pointer comparison at each call site.
        if ($_polymorphic_dispatch && exists $_polymorphic_dispatch->{$method_name}) {
            my @candidates = $_polymorphic_dispatch->{$method_name}->@*;

            my @call_args  = ($invocant_expr, @arg_exprs);
            my $args_str   = join(', ', @call_args);

            my @stmts;
            push @stmts, @pre_eval;
            push @stmts, "HV *_pd_stash = SvROK($invocant_expr) ? SvSTASH(SvRV($invocant_expr)) : NULL";
            push @stmts, 'SV *_mcr';

            # Build the if/else-if chain of stash compares with direct C calls.
            my @branches;
            for my $cand (@candidates) {
                my $slug      = $cand->{slug};
                my $c_func    = "${slug}_${method_name}";
                push @branches,
                    "if (_pd_stash == _${slug}_stash) { _mcr = SvREFCNT_inc(${c_func}(aTHX_ ${args_str})); }";
            }

            # Assemble the call_method fallback as the else branch.
            my @fallback;
            push @fallback, 'dSP';
            push @fallback, 'ENTER; SAVETMPS';
            push @fallback, 'PUSHMARK(SP)';
            push @fallback, "XPUSHs($invocant_expr)";
            for my $expr (@arg_exprs) {
                push @fallback, "XPUSHs($expr)";
            }
            push @fallback, 'PUTBACK';
            push @fallback, "call_method(\"$escaped_name\", G_SCALAR)";
            push @fallback, 'SPAGAIN';
            push @fallback, '_mcr = SvREFCNT_inc(POPs)';
            push @fallback, 'PUTBACK; FREETMPS; LEAVE';
            my $fallback_str = join('; ', @fallback);

            # Join branches into an if/else-if/.../else chain.
            my $chain = join(' else ', @branches) . " else { $fallback_str; }";
            push @stmts, $chain;
            push @stmts, '_mcr';

            return '({ ' . join('; ', @stmts) . '; })';
        }

        my @stmts;
        push @stmts, @pre_eval;

        push @stmts, 'dSP';
        push @stmts, 'ENTER; SAVETMPS';
        push @stmts, 'PUSHMARK(SP)';
        push @stmts, "XPUSHs($invocant_expr)";
        for my $expr (@arg_exprs) {
            push @stmts, "XPUSHs($expr)";
        }
        push @stmts, 'PUTBACK';
        push @stmts, "call_method(\"$escaped_name\", G_SCALAR)";
        push @stmts, 'SPAGAIN';
        push @stmts, 'SV *_mcr = SvREFCNT_inc(POPs)';
        push @stmts, 'PUTBACK; FREETMPS; LEAVE';
        push @stmts, '_mcr';

        return '({ ' . join('; ', @stmts) . '; })';
    }

    # Emit postfix deref (->@*, ->%*, ->$*)

    # Emit ternary expression

    # Emit hash ref constructor

    # Emit array ref constructor

    # Compile anonymous sub as a static C function with a CV wrapper.
    # The body is compiled to native C just like regular methods. A CV
    # is created via newXS in the BOOT block so call_sv can dispatch to it.
    # The CV is cached in a static SV* for zero-overhead repeated use.
    method _emit_anon_sub_expr($node, $declared_vars) {
        # Clear current sub name so __SUB__ recursion detection does not
        # fire for coderef calls inside this anonymous sub's body.
        my $prev_sub_name = $self->_get_current_sub_name();
        $self->_set_current_sub_name('');

        my $params_node = $node->inputs()->[0];
        my $body_items  = $node->inputs()->[1] // [];

        my $idx = $_anon_sub_counter++;
        my $fn_name = "_anon_${\  $self->_get_current_slug()}_${idx}";
        my $cv_var  = "_cv_${fn_name}";

        # Build parameter list for the static function
        my @c_params;
        my @xsub_params;
        # Anon subs have their own scope — don't inherit outer declared_vars
        # which would cause param names to collide with outer var declarations.
        my %anon_vars;
        for my $p ($params_node->@*) {
            my $pname = $p->value();
            $pname =~ s/^\$//;
            push @c_params, "SV *$pname";
            push @xsub_params, $pname;
            $anon_vars{"param:$pname"} = 1;
        }

        # Try to compile the body to native C
        my @body_c;
        my $compile_ok = true;
        for my $stmt ($body_items->@*) {
            my $c;
            try {
                $c = $self->_emit_expr($stmt, \%anon_vars);
            } catch ($e) {
                $compile_ok = false;
                last;
            }
            if (!defined $c) {
                $compile_ok = false;
                last;
            }
            push @body_c, $c;
        }

        if ($compile_ok && @body_c) {
            # Emit the static C function
            my $sig = @c_params ? join(', ', @c_params) : 'void';
            push @_anon_sub_helpers, "static SV *${fn_name}(pTHX_ $sig) {";
            # Last expression is the return value
            if (@body_c == 1) {
                push @_anon_sub_helpers, "    return SvREFCNT_inc($body_c[0]);";
            } else {
                for my $i (0 .. $#body_c - 1) {
                    push @_anon_sub_helpers, "    $body_c[$i];";
                }
                push @_anon_sub_helpers, "    return SvREFCNT_inc($body_c[-1]);";
            }
            push @_anon_sub_helpers, '}';
            push @_anon_sub_helpers, '';

            # Emit the XSUB wrapper for call_sv dispatch
            push @_anon_sub_helpers, "XS_INTERNAL(XS_${fn_name});";
            push @_anon_sub_helpers, "XS_INTERNAL(XS_${fn_name})";
            push @_anon_sub_helpers, '{';
            push @_anon_sub_helpers, '    dXSARGS;';
            my @fetch;
            for my $i (0 .. $#xsub_params) {
                push @fetch, "    SV *$xsub_params[$i] = ST($i);";
            }
            push @_anon_sub_helpers, @fetch;
            my $call_args = @xsub_params
                ? 'aTHX_ ' . join(', ', @xsub_params)
                : 'aTHX';
            push @_anon_sub_helpers, "    SV *retval = ${fn_name}($call_args);";
            push @_anon_sub_helpers, '    ST(0) = retval;';
            push @_anon_sub_helpers, '    sv_2mortal(retval);';
            push @_anon_sub_helpers, '    XSRETURN(1);';
            push @_anon_sub_helpers, '}';
            push @_anon_sub_helpers, '';

            # Register in anon_sub_registrations for BOOT block generation.
            # cv_var is the static SV* name used in method bodies; it is declared
            # at file scope alongside regex statics and initialized in init_statics.
            push @_anon_sub_registrations, {
                name   => "::${fn_name}",
                c_name => "XS_${fn_name}",
                cv_var => $cv_var,
            };

            $self->_set_current_sub_name($prev_sub_name);
            return $cv_var;
        }

        # Fallback: compile via eval_pv if body compilation fails
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $perl_src = $perl_target->_emit_anon_sub_expr($node);
        my $prefix = 'use feature "signatures"; no warnings "experimental::signatures"; ';
        my $escaped = $self->_escape_c_string($prefix . $perl_src);
        $self->_set_current_sub_name($prev_sub_name);
        return "eval_pv(\"$escaped\", TRUE)";
    }

    # Emit regex match using native Perl regex C API (pregcomp/pregexec).
    # Compiles the regex once into a static REGEXP* and reuses it.

    # Emit regex substitution via eval_pv, setting $_ to target first

    # Emit builtin call as C expression
    method _emit_builtin_call($node, $declared_vars) {
        my ($name, $args);
        if ($node isa Chalk::IR::Node::Call) {
            $name = $node->name();
            $args = $node->inputs();
        } else {
            $name = $node->inputs()->[0]->value();
            $args = $node->inputs()->[1];
        }

        # defined() — check SvOK
        if ($name eq 'defined' && $args->@* == 1) {
            my $arg = $self->_emit_expr($args->[0], $declared_vars);
            return "(SvOK($arg) ? &PL_sv_yes : &PL_sv_no)";
        }

        # ref() — check SvROK
        if ($name eq 'ref' && $args->@* == 1) {
            my $arg = $self->_emit_expr($args->[0], $declared_vars);
            return "(SvROK($arg) ? sv_2mortal(newSVpv(sv_reftype(SvRV($arg), TRUE), 0)) : sv_2mortal(newSVpvs(\"\")))";
        }

        # refaddr() — return the pointer value of the referent as UV
        # Guard with SvROK check: Perl's refaddr() returns undef for non-refs.
        # Without this, SvRV on a non-reference (e.g. true/false) segfaults.
        if ($name eq 'refaddr' && $args->@* == 1) {
            my $arg = $self->_emit_expr($args->[0], $declared_vars);
            return "(SvROK($arg) ? sv_2mortal(newSVuv(PTR2UV(SvRV($arg)))) : &PL_sv_undef)";
        }

        # scalar() — for arrays, return count
        if ($name eq 'scalar' && $args->@* == 1) {
            my $arg = $self->_emit_expr($args->[0], $declared_vars);
            return "sv_2mortal(newSViv(av_len((AV*)$arg) + 1))";
        }

        # push — av_push wrapped in statement expression (av_push returns void)
        if ($name eq 'push' && $args->@* >= 2) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_expr($arr_node, $declared_vars);
            # PostfixDeref ->@* already returns (AV*)SvRV(...), no need to double-deref
            my $av_expr;
            if ($arr_node isa Chalk::IR::Node::PostfixDeref) {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            # Flatten list-producing value arguments (values %hash) into
            # individual av_push calls instead of wrapping in an extra AV.
            my $val_node = $args->[1];
            if ($val_node isa Chalk::IR::Node::Call && $val_node->dispatch_kind() eq 'builtin') {
                my $val_name = $val_node->name();
                my $val_args = $val_node->inputs();
                if ($val_name eq 'values') {
                    my $hash_expr = $self->_emit_expr($val_args->[0], $declared_vars);
                    my $hv_expr;
                    if ($val_args->[0] isa Chalk::IR::Node::PostfixDeref) {
                        $hv_expr = $hash_expr;
                    } else {
                        $hv_expr = "(HV*)SvRV($hash_expr)";
                    }
                    return "({ HV *_vhv = $hv_expr; "
                        . "hv_iterinit(_vhv); HE *_he; "
                        . "while ((_he = hv_iternext(_vhv))) "
                        . "av_push($av_expr, SvREFCNT_inc(HeVAL(_he))); "
                        . "$arr; })";
                }
                # push @arr, reverse @src — iterate source backwards, push each element
                if ($val_name eq 'reverse') {
                    my $src_expr = $self->_emit_expr($val_args->[0], $declared_vars);
                    my $src_av;
                    if ($val_args->[0] isa Chalk::IR::Node::PostfixDeref) {
                        $src_av = $src_expr;
                    } else {
                        $src_av = "(AV*)SvRV($src_expr)";
                    }
                    return "({ AV *_rsrc = $src_av; I32 _rlen = av_len(_rsrc); "
                        . "I32 _ri; for (_ri = _rlen; _ri >= 0; _ri--) "
                        . "av_push($av_expr, SvREFCNT_inc(*av_fetch(_rsrc, _ri, 0))); "
                        . "$arr; })";
                }
            }
            my $val = $self->_emit_expr($val_node, $declared_vars);
            return "({ av_push($av_expr, SvREFCNT_inc($val)); $arr; })";
        }

        # sprintf — native C via Perl_sv_setpvf
        if ($name eq 'sprintf' && $args->@* >= 1) {
            my $fmt = $self->_emit_expr($args->[0], $declared_vars);
            my @c_args = map { $self->_emit_expr($_, $declared_vars) } $args->@[1 .. $#$args];
            return "({ SV *_sv = sv_2mortal(newSVpvs(\"\")); Perl_sv_setpvf(aTHX_ _sv, SvPV_nolen($fmt)" .
                (@c_args ? ", " . join(", ", map { "SvPV_nolen($_)" } @c_args) : "") .
                "); _sv; })";
        }

        # join — native C via sv_catsv
        if ($name eq 'join' && $args->@* >= 2) {
            my $sep = $self->_emit_expr($args->[0], $declared_vars);
            if ($args->@* == 2) {
                # join($sep, @array) — iterate over arrayref
                my $arr = $self->_emit_expr($args->[1], $declared_vars);
                return "({ SV *_result = sv_2mortal(newSVpvs(\"\")); " .
                    "AV *_items = (AV*)SvRV($arr); " .
                    "I32 _len = av_len(_items); " .
                    "I32 _i; " .
                    "for (_i = 0; _i <= _len; _i++) { " .
                    "if (_i > 0) sv_catsv(_result, $sep); " .
                    "sv_catsv(_result, *av_fetch(_items, _i, 0)); " .
                    "} _result; })";
            } else {
                # join($sep, $a, $b, ...) — concatenate scalar args directly
                my @c_args = map { $self->_emit_expr($_, $declared_vars) } $args->@[1 .. $args->$#*];
                my $code = "({ SV *_result = sv_2mortal(newSVsv($c_args[0])); ";
                for my $i (1 .. $#c_args) {
                    $code .= "sv_catsv(_result, $sep); sv_catsv(_result, $c_args[$i]); ";
                }
                $code .= "_result; })";
                return $code;
            }
        }

        # warn — native Perl_warn with string argument
        if ($name eq 'warn' && $args->@* >= 1) {
            my $arg = $self->_emit_expr($args->[0], $declared_vars);
            return "({ Perl_warn(aTHX_ \"%s\", SvPV_nolen($arg)); &PL_sv_undef; })";
        }

        # split — eval_pv with actual args from IR
        if ($name eq 'split' && $args->@* >= 2) {
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my @arg_strs = map { $perl_target->_emit_expr($_) } $args->@*;
            my $perl_call = "split(" . join(', ', @arg_strs) . ")";
            my $escaped = $self->_escape_c_string($perl_call);
            return "eval_pv(\"$escaped\", TRUE)";
        }

        # length($str) — character length via sv_len_utf8 (handles UTF-8 strings)
        if ($name eq 'length' && $args->@* == 1) {
            my $arg = $self->_emit_expr($args->[0], $declared_vars);
            return "sv_2mortal(newSViv(sv_len_utf8($arg)))";
        }

        # shift(@arr) — native array shift via av_shift
        if ($name eq 'shift' && $args->@* == 1) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_expr($arr_node, $declared_vars);
            my $av_expr;
            if ($arr_node isa Chalk::IR::Node::PostfixDeref) {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            return "av_shift($av_expr)";
        }

        # pop(@arr) — native array pop via av_pop
        if ($name eq 'pop' && $args->@* == 1) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_expr($arr_node, $declared_vars);
            my $av_expr;
            if ($arr_node isa Chalk::IR::Node::PostfixDeref) {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            return "av_pop($av_expr)";
        }

        # reverse(@arr) — reverse an array into a new AV
        if ($name eq 'reverse' && $args->@* == 1) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_expr($arr_node, $declared_vars);
            my $av_expr;
            if ($arr_node isa Chalk::IR::Node::PostfixDeref) {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            return "({ AV *_src = $av_expr; I32 _len = av_len(_src); "
                . "AV *_rev = newAV(); av_extend(_rev, _len); "
                . "I32 _ri; for (_ri = _len; _ri >= 0; _ri--) "
                . "av_push(_rev, SvREFCNT_inc(*av_fetch(_src, _ri, 0))); "
                . "sv_2mortal(newRV_noinc((SV*)_rev)); })";
        }

        # keys(%hash) — scalar context returns count, list context returns AV of keys.
        # Standalone keys() returns count via HvUSEDKEYS. When used as argument
        # to sort/map/grep, the caller invokes _emit_keys_list directly.
        if ($name eq 'keys' && $args->@* == 1) {
            my $hash_node = $args->[0];
            my $hash = $self->_emit_expr($hash_node, $declared_vars);
            my $hv_expr;
            if ($hash_node isa Chalk::IR::Node::PostfixDeref) {
                $hv_expr = $hash;
            } else {
                $hv_expr = "(HV*)SvRV($hash)";
            }
            return "sv_2mortal(newSViv(HvUSEDKEYS($hv_expr)))";
        }

        # sort — bare sort (no block) using sortsv with sv_cmp
        if ($name eq 'sort' && $args->@* == 1) {
            my $list_node = $args->[0];
            # Detect sort keys %$hash — emit keys as list, then sort
            my $list_expr;
            if ($list_node isa Chalk::IR::Node::Call && $list_node->dispatch_kind() eq 'builtin'
                        && $list_node->name() eq 'keys') {
                my $keys_arg = $list_node->inputs()->[0];
                $list_expr = $self->_emit_keys_list($keys_arg, $declared_vars);
            } else {
                $list_expr = $self->_emit_expr($list_node, $declared_vars);
            }
            my $av_init = ($list_expr =~ /^\(AV\*\)/)
                ? "AV *_ssrc = $list_expr; "
                : "AV *_ssrc = (AV*)SvRV($list_expr); ";
            return "({ ${av_init}"
                . "SSize_t _slen = av_len(_ssrc) + 1; "
                . "AV *_sorted = newAV(); av_extend(_sorted, _slen - 1); "
                . "SV **_stmp = (SV**)safemalloc((_slen ? _slen : 1) * sizeof(SV*)); "
                . "SSize_t _si; "
                . "for (_si = 0; _si < _slen; _si++) { "
                .   "SV **_ep = av_fetch(_ssrc, _si, 0); "
                .   "_stmp[_si] = _ep ? SvREFCNT_inc(*_ep) : &PL_sv_undef; "
                . "} "
                . "sortsv(_stmp, _slen, Perl_sv_cmp_locale); "
                . "for (_si = 0; _si < _slen; _si++) av_push(_sorted, _stmp[_si]); "
                . "Safefree(_stmp); "
                . "newRV_noinc((SV*)_sorted); })";
        }

        # values(%hash) — native hash value iteration via hv_iternext
        if ($name eq 'values' && $args->@* == 1) {
            my $hash_node = $args->[0];
            my $hash = $self->_emit_expr($hash_node, $declared_vars);
            my $hv_expr;
            if ($hash_node isa Chalk::IR::Node::PostfixDeref) {
                $hv_expr = $hash;
            } else {
                $hv_expr = "(HV*)SvRV($hash)";
            }
            return "({ AV *_vav = newAV(); HV *_vhv = $hv_expr; "
                . "hv_iterinit(_vhv); HE *_he; "
                . "while ((_he = hv_iternext(_vhv))) "
                . "av_push(_vav, SvREFCNT_inc(HeVAL(_he))); "
                . "newRV_noinc((SV*)_vav); })";
        }

        # map { BLOCK } LIST — native C loop.
        # The parser sometimes loses the block, leaving only the range arg.
        # When map has 1 arg (range only), emit array of empty hashrefs (chart init pattern).
        # When map has 2 args (block + range), emit block body for each element.
        if ($name eq 'map' && $args->@* >= 1) {
            my ($block_node, $list_node, @block_body_items);
            if ($args->@* == 2) {
                $block_node = $args->[0];
                $list_node  = $args->[1];
            } elsif ($args->@* > 2) {
                # Multi-item from _fixup_stmts: first N-1 args are block body,
                # last arg is the list source (e.g., map { STMT; EXPR } LIST).
                $list_node = $args->[-1];
                @block_body_items = $args->@[0 .. $#{$args} - 1];
            } else {
                # Single arg: range only, block was lost in parsing.
                # Default to empty hashref (map { {} } RANGE pattern).
                $list_node = $args->[0];
            }

            # Emit the block body — evaluate the last expression.
            # The block may be an AnonSubExpr (explicit block) or a bare
            # expression node (e.g., MethodCallExpr from map { $_->m() } @arr).
            # For bare expressions, we bind $_ to the current element via _mtopic.
            my $block_body;
            my $needs_topic_binding = false;
            if (@block_body_items) {
                # Multi-item block from _fixup_stmts LIST_BUILTIN consumption.
                # Items are the block body statements; last is the return value.
                $needs_topic_binding = true;
                my %map_vars = ($declared_vars ? $declared_vars->%* : ());
                $map_vars{'_'} = 1;
                my @block_stmts;
                for my $stmt (@block_body_items) {
                    if ($stmt isa Chalk::IR::Node::VarDecl) {
                        my $vname = $stmt->inputs()->[0]->value() =~ s/^\$//r;
                        $map_vars{$vname} = 1;
                        my $init = $self->_emit_expr($stmt->inputs()->[1], \%map_vars);
                        push @block_stmts, "SV *${vname}_sv = $init";
                    } else {
                        push @block_stmts, $self->_emit_expr($stmt, \%map_vars);
                    }
                }
                $block_body = '({ ' . join('; ', @block_stmts) . '; })';
            } elsif (defined $block_node && $block_node isa Chalk::IR::Node::AnonSub) {
                my $body = $block_node->inputs()->[1] // [];
                if ($body->@* > 1) {
                    # Multi-statement block: emit all stmts as compound statement expr.
                    # VarDecl items declare local C variables; last item is the return value.
                    $needs_topic_binding = true;
                    my %map_vars = ($declared_vars ? $declared_vars->%* : ());
                    $map_vars{'_'} = 1;
                    my @block_stmts;
                    for my $stmt ($body->@*) {
                        if ($stmt isa Chalk::IR::Node::VarDecl) {
                            my $vname = $stmt->inputs()->[0]->value() =~ s/^\$//r;
                            $map_vars{$vname} = 1;
                            my $init = $self->_emit_expr($stmt->inputs()->[1], \%map_vars);
                            push @block_stmts, "SV *${vname}_sv = $init";
                        } else {
                            push @block_stmts, $self->_emit_expr($stmt, \%map_vars);
                        }
                    }
                    $block_body = '({ ' . join('; ', @block_stmts) . '; })';
                } elsif ($body->@*) {
                    $block_body = $self->_emit_expr($body->[-1], $declared_vars);
                }
            } elsif (defined $block_node) {
                # Bare expression block: bind $_ (topic) to current element
                $needs_topic_binding = true;
                my $topic_vars = { ($declared_vars ? $declared_vars->%* : ()), '_' => 1 };
                $block_body = $self->_emit_expr($block_node, $topic_vars);
            }
            $block_body //= 'newRV_noinc((SV*)newHV())';

            # Build topic binding prefix for loops with bare expression blocks.
            # When $_ is used in the block body, it maps to __sv (the C variable
            # for $_ following the ${var}_sv naming convention where var='_').
            # The PREINIT section already declares __sv from _collect_var_decls.
            # Only emit topic binding when the block body actually references __sv,
            # otherwise it would reference an undeclared variable.
            my $body_uses_topic = $needs_topic_binding
                && defined $block_body && $block_body =~ /__sv/;
            my $topic_range = $body_uses_topic ? '__sv = newSViv(_mi); ' : '';
            my $topic_array = $body_uses_topic
                ? '{ SV **_mep = av_fetch(_msrc, _mi, 0); __sv = (_mep && *_mep) ? *_mep : &PL_sv_undef; } '
                : '';

            # If list is a range (BinaryExpr with '..'), emit integer for loop
            if ($list_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $list_node->class() eq 'BinaryExpr'
                    && defined $list_node->inputs()->[0]
                    && $list_node->inputs()->[0] isa Chalk::Bootstrap::IR::Node::Constant
                    && $list_node->inputs()->[0]->value() eq '..') {
                my $range_left  = $self->_emit_expr($list_node->inputs()->[1], $declared_vars);
                my $range_right = $self->_emit_expr($list_node->inputs()->[2], $declared_vars);
                return "({ AV *_mav = newAV(); "
                    . "SV *_mrs = $range_left; SV *_mre = $range_right; "
                    . "SSize_t _ms = SvROK(_mrs) ? av_len((AV*)SvRV(_mrs)) : SvIV(_mrs); "
                    . "SSize_t _me = SvROK(_mre) ? av_len((AV*)SvRV(_mre)) : SvIV(_mre); "
                    . "SSize_t _mi; "
                    . "for (_mi = _ms; _mi <= _me; _mi++) { ${topic_range}"
                    . "av_push(_mav, SvREFCNT_inc($block_body)); } "
                    . "newRV_noinc((SV*)_mav); })";
            }

            # Generic: iterate over AV
            my $list_expr = $self->_emit_expr($list_node, $declared_vars);
            # PostfixDerefExpr with '@' already returns (AV*)SvRV(...) —
            # don't double-dereference.
            my $av_init = ($list_expr =~ /^\(AV\*\)/)
                ? "AV *_msrc = $list_expr; "
                : "AV *_msrc = (AV*)SvRV($list_expr); ";
            return "({ AV *_mav = newAV(); "
                . $av_init
                . "SSize_t _mlen = av_len(_msrc) + 1; SSize_t _mi; "
                . "for (_mi = 0; _mi < _mlen; _mi++) { ${topic_array}"
                . "av_push(_mav, SvREFCNT_inc($block_body)); } "
                . "newRV_noinc((SV*)_mav); })";
        }

        # delete($hash{$key}) — native hash entry removal via hv_delete_ent
        if ($name eq 'delete' && $args->@* == 1) {
            my $sub_node = $args->[0];
            if ($sub_node isa Chalk::IR::Node::Subscript) {
                my $target = $self->_emit_expr($sub_node->inputs()->[0], $declared_vars);
                my $key = $self->_emit_expr($sub_node->inputs()->[1], $declared_vars);
                my $field_sig = $self->_field_sigil_for_expr($target);
                my $hv = (defined $field_sig && $field_sig eq '%')
                    ? "(HV*)$target" : "(HV*)SvRV($target)";
                return "hv_delete_ent($hv, $key, G_DISCARD, 0)";
            }
        }

        # exists($hash{$key}) — native hash key existence check via hv_exists_ent
        if ($name eq 'exists' && $args->@* == 1) {
            my $sub_node = $args->[0];
            if ($sub_node isa Chalk::IR::Node::Subscript) {
                my $target = $self->_emit_expr($sub_node->inputs()->[0], $declared_vars);
                my $key = $self->_emit_expr($sub_node->inputs()->[1], $declared_vars);
                my $field_sig = $self->_field_sigil_for_expr($target);
                my $hv = (defined $field_sig && $field_sig eq '%')
                    ? "(HV*)$target" : "(HV*)SvRV($target)";
                return "(hv_exists_ent($hv, $key, 0) ? &PL_sv_yes : &PL_sv_no)";
            }
        }

        # pack('NN', $a, $b) — native C for common big-endian 32-bit patterns.
        # Falls through to eval_pv for other templates.
        if ($name eq 'pack' && $args->@* >= 2) {
            my $tmpl_node = $args->[0];
            if ($tmpl_node isa Chalk::Bootstrap::IR::Node::Constant) {
                my $tmpl = $tmpl_node->value() // '';
                $tmpl =~ s/^['"]|['"]$//g;
                if ($tmpl eq 'NN' && $args->@* == 3) {
                    my $a = $self->_emit_expr($args->[1], $declared_vars);
                    my $b = $self->_emit_expr($args->[2], $declared_vars);
                    return "({ U32 _pa = htonl((U32)SvUV($a)); U32 _pb = htonl((U32)SvUV($b)); "
                        . "SV *_pk = sv_2mortal(newSVpvn(\"\", 0)); "
                        . "sv_catpvn(_pk, (char*)&_pa, sizeof(U32)); "
                        . "sv_catpvn(_pk, (char*)&_pb, sizeof(U32)); "
                        . "_pk; })";
                }
            }
        }

        # substr — character-correct extraction
        # For UTF-8 strings, byte offsets differ from character offsets.
        # Use sv_pos_u2b to convert character offset/length to byte offset/length.
        if ($name eq 'substr' && $args->@* >= 2) {
            my $str = $self->_emit_expr($args->[0], $declared_vars);
            my $off = $self->_emit_expr($args->[1], $declared_vars);
            if ($args->@* >= 3) {
                my $len = $self->_emit_expr($args->[2], $declared_vars);
                return "({ SV *_s = $str; SSize_t _o = SvIV($off); SSize_t _n = SvIV($len); "
                    . "STRLEN _sl; char *_sp = SvPV(_s, _sl); "
                    . "I32 _bo = (I32)_o; I32 _bn = (I32)_n; "
                    . "if (SvUTF8(_s)) sv_pos_u2b(_s, &_bo, &_bn); "
                    . "SV *_r = newSVpvn(_sp + (STRLEN)_bo, (STRLEN)_bn); "
                    . "if (SvUTF8(_s)) SvUTF8_on(_r); sv_2mortal(_r); })";
            }
            return "({ SV *_s = $str; SSize_t _o = SvIV($off); "
                . "STRLEN _sl; char *_sp = SvPV(_s, _sl); "
                . "I32 _bo = (I32)_o; "
                . "if (SvUTF8(_s)) { I32 _dummy = 0; sv_pos_u2b(_s, &_bo, &_dummy); } "
                . "SV *_r = newSVpvn(_sp + (STRLEN)_bo, _sl - (STRLEN)_bo); "
                . "if (SvUTF8(_s)) SvUTF8_on(_r); sv_2mortal(_r); })";
        }

        # Qualified function call (e.g., Chalk::Bootstrap::Terminal::match) —
        # use call_pv with C-local args on the stack instead of eval_pv
        if ($name =~ /::/) {
            my @arg_exprs = map { $self->_emit_expr($_, $declared_vars) } $args->@*;
            my $escaped_name = $self->_escape_c_string($name);
            my @stmts = ('dSP', 'ENTER', 'SAVETMPS', 'PUSHMARK(SP)');
            for my $arg (@arg_exprs) {
                push @stmts, "XPUSHs($arg)";
            }
            push @stmts, 'PUTBACK';
            push @stmts, "call_pv(\"$escaped_name\", G_SCALAR)";
            push @stmts, 'SPAGAIN';
            push @stmts, 'SV *_cpv = SvREFCNT_inc(POPs)';
            push @stmts, 'PUTBACK', 'FREETMPS', 'LEAVE';
            push @stmts, '_cpv';
            return '({ ' . join('; ', @stmts) . '; })';
        }

        # Check if this is a call to a known class-scope sub.
        # Compiled subs get direct _impl_ C calls.
        # Uncompiled subs get call_pv with the FQ package name (not eval_pv).
        if ($self->_get_class_subs()->%* && exists $self->_get_class_subs()->{$name}) {
            my @c_args;
            for my $arg ($args->@*) {
                push @c_args, $self->_emit_expr($arg, $declared_vars);
            }

            if ($self->_get_class_subs()->{$name}{compiled}) {
                # Direct C call to compiled helper (static, slug-namespaced)
                my $helper_name = "${\  $self->_get_current_slug()}_${name}";
                # Pad missing args with &PL_sv_undef for default params
                my $expected = $self->_get_class_subs()->{$name}{params} // [];
                while (scalar @c_args < scalar $expected->@*) {
                    push @c_args, '&PL_sv_undef';
                }
                my $call_args;
                if (@c_args) {
                    $call_args = 'aTHX_ ' . join(', ', @c_args);
                } else {
                    $call_args = 'aTHX';
                }
                return "$helper_name($call_args)";
            } else {
                # Uncompiled sub — use call_pv with fully-qualified name.
                # The sub exists in the Perl namespace, just can't be compiled to C.
                my $class_name = $self->_get_class_subs()->{$name}{class_name} // '';
                my $fq_name = $class_name ? "${class_name}::${name}" : $name;
                my $escaped_name = $self->_escape_c_string($fq_name);
                my @stmts;
                push @stmts, 'dSP', 'ENTER', 'SAVETMPS', 'PUSHMARK(SP)';
                for my $c_arg (@c_args) {
                    push @stmts, "XPUSHs($c_arg)";
                }
                push @stmts, 'PUTBACK';
                push @stmts, "call_pv(\"$escaped_name\", G_SCALAR)";
                push @stmts, 'SPAGAIN';
                push @stmts, 'SV *_cpv = SvREFCNT_inc(POPs)';
                push @stmts, 'PUTBACK', 'FREETMPS', 'LEAVE';
                push @stmts, '_cpv';
                return '({ ' . join('; ', @stmts) . '; })';
            }
        }

        # Fallback — preserve arguments via eval_pv with real Perl expression
        {
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my @arg_strs = map { $perl_target->_emit_expr($_) } $args->@*;
            my $perl_call = "$name(" . join(', ', @arg_strs) . ")";
            my $escaped = $self->_escape_c_string($perl_call);
            return "eval_pv(\"$escaped\", TRUE)";
        }
    }

    # Emit keys() in list context — returns AV ref of all hash keys.
    # Used when keys is argument to sort/map/grep (not standalone scalar context).

    # Emit backtick expression via eval_pv with actual command from IR

    # CompoundAssign as expression (e.g., $str .= "foo")

    # VarDecl as expression (my $x = ...)

    # Emit VarDecl as C statement (SV assignment)

    # Emit Return CFG node as RETVAL assignment.
    # Non-final returns jump to xsreturn: label before OUTPUT section.
    # Strips sv_2mortal() from the value expression since XS's OUTPUT
    # section applies sv_2mortal to ST(0) automatically. Double-mortal
    # causes "attempt to copy freed scalar" panics.
    # SvREFCNT_inc ensures proper ownership for borrowed references:
    # The OUTPUT section mortalises RETVAL (decrements refcount), so we
    # must increment to avoid freeing SVs still stored in containers.
    # For new* values (newSViv, newRV_noinc, etc.) the refcount is already
    # 1, so the mortalisation correctly consumes it. SvREFCNT_inc on these
    # would leak. To handle both cases, we skip SvREFCNT_inc for values
    # that are clearly newly-created (start with 'new' or '&PL_sv_').

    # Emit CompoundAssign as statement
    method _emit_interp_return($method_name, $interp_node) {
        my $parts = $interp_node->inputs()->[0];
        my $func_name = "${\  $self->_get_current_slug()}_${method_name}";

        my @body;
        # Build the result SV by concatenation
        my $first = true;
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                my $var = $part->value();
                $var =~ s/^\$//;
                my $src;
                if ($self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
                    my $idx = $self->_get_field_map()->{$var};
                    $src = "ObjectFIELDS(SvRV(self))[$idx]";
                } else {
                    # Fallback for non-field variables
                    my $escaped = $self->_escape_c_string($var);
                    $src = "get_sv(\"${\$self->module_name()}::$escaped\", GV_ADD)";
                }
                if ($first) {
                    push @body, "    SV *retval = newSVsv($src);";
                    $first = false;
                } else {
                    push @body, "    sv_catsv(retval, $src);";
                }
            } else {
                my $lit = $self->_escape_c_string($part->value());
                if ($first) {
                    push @body, "    SV *retval = newSVpvs(\"$lit\");";
                    $first = false;
                } else {
                    push @body, "    sv_catpvs(retval, \"$lit\");";
                }
            }
        }
        push @body, "    return retval;";

        my @helper;
        push @helper, "SV * ${func_name}(pTHX_ SV *self) {";
        push @helper, "    PERL_UNUSED_ARG(self);" unless grep { /ObjectFIELDS/ } @body;
        push @helper, @body;
        push @helper, "}";

        push @_exported_functions, {
            name        => $func_name,
            return_type => 'SV *',
            params      => 'pTHX_ SV *self',
        };

        return { helper => \@helper };
    }

    # Emit a C initializer expression for a class-scope variable declaration.
    # $init_node is the RHS of the `my $var = ...` declaration.
    # $sigil is $, @, or %.
    # Returns a C expression string, or undef if the init cannot be represented.
    method _emit_init_expr($init_node, $sigil) {
        return undef unless defined $init_node;
        return undef unless $init_node isa Chalk::IR::Node
                         || $init_node isa Chalk::Bootstrap::IR::Node::Constructor;

        # my $scalar = [] — empty array reference
        if ($init_node isa Chalk::IR::Node::ArrayRef) {
            my $elems = $init_node->inputs()->[0];
            if (!defined $elems || (ref($elems) eq 'ARRAY' && $elems->@* == 0)) {
                return 'newRV_noinc((SV*)newAV())';
            }
        }
        # my $scalar = {} — empty hash reference
        if ($init_node isa Chalk::IR::Node::HashRef) {
            my $elems = $init_node->inputs()->[0];
            if (!defined $elems || (ref($elems) eq 'ARRAY' && $elems->@* == 0)) {
                return 'newRV_noinc((SV*)newHV())';
            }
        }
        # my $scalar = literal constant
        if ($init_node isa Chalk::Bootstrap::IR::Node::Constant) {
            my $val = $init_node->value();
            return '&PL_sv_undef' if $val eq 'undef';
            return '&PL_sv_yes'   if $val eq '1' || $val eq 'true';
            return '&PL_sv_no'    if $val eq '0' || $val eq 'false' || $val eq '';
            if ($val =~ /\A-?\d+\z/) { return "newSViv($val)"; }
            my $esc = $self->_escape_c_string($val);
            return "newSVpvs(\"$esc\")";
        }
        return undef;
    }

    # Generate C source and header files from a Perl IR tree.
    # Stores $sa and $ctx for use by emission methods that need cfg_state.
    # Returns hashref: { files => { "slug.c" => ..., "slug.h" => ... },
    #                    exported_functions => [...],
    #                    skipped_methods => [...],
    #                    anon_sub_registrations => [...] }
    method generate_c_files($ir, $sa, $ctx) {
        $self->_set_sa($sa);
        $self->_set_ctx($ctx);

        # Reset per-generation state
        @_exported_functions    = ();
        @_skipped_methods       = ();
        @_anon_sub_registrations = ();
        @_anon_sub_helpers      = ();
        $_anon_sub_counter      = 0;
        $self->_reset_regex_statics();
        $self->_reset_regex_counter();
        $self->_reset_cfg_lookup();

        # Precompute field_name => C slug mapping for known-typed fields.
        # Used by _emit_method_call_expr to detect cross-class direct calls.
        {
            my %slugs;
            for my $fname (sort keys $field_types->%*) {
                my $target_class = $field_types->{$fname};
                $slugs{$fname} = $self->_class_slug_for($target_class);
            }
            $_field_type_slugs = \%slugs;
        }

        # Build method dispatch table from compiled_class_metadata.
        # For each method name that is unambiguous across all compiled classes,
        # map it to either a reader (ObjectFIELDS access) or a direct C call.
        if (keys $compiled_class_metadata->%*) {
            my %method_owners;  # method_name => [{ class_meta, type }]
            for my $class_name (sort keys $compiled_class_metadata->%*) {
                my $meta = $compiled_class_metadata->{$class_name};
                my $readers = $meta->{readers} // {};
                for my $rdr (sort keys $readers->%*) {
                    push $method_owners{$rdr}->@*, {
                        type       => 'reader',
                        slug       => $meta->{slug},
                        field_idx  => $readers->{$rdr},
                        class_name => $class_name,
                    };
                }
                my $methods = $meta->{methods} // {};
                for my $meth (sort keys $methods->%*) {
                    push $method_owners{$meth}->@*, {
                        type       => 'method',
                        slug       => $meta->{slug},
                        class_name => $class_name,
                    };
                }
            }
            my %dispatch;
            for my $mname (sort keys %method_owners) {
                my @owners = $method_owners{$mname}->@*;
                # Only use dispatch for unambiguous methods (single owner)
                if (scalar @owners == 1) {
                    $dispatch{$mname} = $owners[0];
                }
            }
            $_method_dispatch = \%dispatch;

            # Build polymorphic dispatch map: collect ALL classes per method name,
            # then keep only methods with multiple owners (single-owner methods are
            # already handled by $_method_dispatch with cheaper direct dispatch).
            # Exclude methods where any owner is a :reader — readers use
            # ObjectFIELDS access, not C function calls, so emitting
            # slug_readername() would produce an undefined symbol at link time.
            my %poly;
            for my $mname (sort keys %method_owners) {
                my @owners = $method_owners{$mname}->@*;
                # Skip single-owner methods — covered by $_method_dispatch
                next if scalar @owners == 1;
                # Skip methods where any owner is a reader (no C function exists)
                next if grep { $_->{type} eq 'reader' } @owners;
                $poly{$mname} = [
                    sort { $a->{slug} cmp $b->{slug} }
                    map { { slug => $_->{slug}, class_name => $_->{class_name} } }
                        @owners
                ];
            }
            $_polymorphic_dispatch = \%poly;
        }

        if (defined $sa) {
            $self->_build_cfg_lookup($sa, $ctx);
        }

        $self->_analyze_class($ir);

        my $slug     = $self->_get_current_slug();
        my $class_decl = $self->_find_class_decl($ir);

        my @static_lines;   # static file-scope variables and helpers
        my @func_lines;     # exported C functions (methods)

        if (defined $class_decl) {
            my $body = $class_decl isa Chalk::IR::ClassInfo
                ? $class_decl->body()
                : $class_decl->inputs()->[2];

            # Emit class-scope subs (static helpers) before methods.
            # Handles SubInfo structs and legacy Constructor:SubDecl nodes.
            for my $item ($body->@*) {
                # Handle SubInfo metadata structs
                if ($item isa Chalk::IR::SubInfo) {
                    my $sname   = $item->name();
                    my $sparams = $item->params();   # plain strings
                    my $sbody   = $item->body();
                    my $result = eval { $self->_emit_sub($sname, $sparams, $sbody) };
                    if (defined $result && ref $result eq 'HASH') {
                        push @static_lines, $result->{helper}->@*;
                        push @static_lines, '';
                        $self->_set_class_sub_compiled($sname, true);
                    } else {
                        $self->_set_class_sub_compiled($sname, false);
                    }
                    next;
                }

                next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;

                # Handle mis-parented SubDecl/SubInfo inside VarDecl
                if ($item->class() eq 'VarDecl') {
                    my $init = $item->inputs()->[1];
                    if (defined $init) {
                        my ($sname, $sparams, $sbody);
                        if ($init isa Chalk::IR::SubInfo) {
                            $sname  = $init->name();
                            $sparams = $init->params();   # plain strings
                            $sbody  = $init->body();
                        } elsif ($init isa Chalk::Bootstrap::IR::Node::Constructor
                                && $init->class() eq 'SubDecl') {
                            $sname   = $init->inputs()->[0]->value();
                            my $raw  = $init->inputs()->[1];
                            my @nodes;
                            for my $p ($raw->@*) { push @nodes, $p; }
                            $sparams = \@nodes;
                            $sbody   = $init->inputs()->[2];
                        }
                        if (defined $sname) {
                            my $result = eval { $self->_emit_sub($sname, $sparams, $sbody) };
                            if (defined $result && ref $result eq 'HASH') {
                                push @static_lines, $result->{helper}->@*;
                                push @static_lines, '';
                                $self->_set_class_sub_compiled($sname, true);
                            } else {
                                $self->_set_class_sub_compiled($sname, false);
                            }
                        }
                    }
                    next;
                }

                next unless $item->class() eq 'SubDecl';
                my $sname   = $item->inputs()->[0]->value();
                my $sparams = $item->inputs()->[1];
                my $sbody   = $item->inputs()->[2];
                my @param_nodes;
                for my $p ($sparams->@*) { push @param_nodes, $p; }
                my $result = eval { $self->_emit_sub($sname, \@param_nodes, $sbody) };
                if (defined $result && ref $result eq 'HASH') {
                    push @static_lines, $result->{helper}->@*;
                    push @static_lines, '';
                    $self->_set_class_sub_compiled($sname, true);
                } else {
                    $self->_set_class_sub_compiled($sname, false);
                }
            }

            # Emit MethodDecl/MethodInfo items as exported C functions
            for my $item ($body->@*) {
                my $mname;
                if ($item isa Chalk::IR::MethodInfo) {
                    $mname = $item->name();
                } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                        && $item->class() eq 'MethodDecl') {
                    $mname = $item->inputs()->[0]->value();
                } else {
                    next;
                }

                my $result = eval { $self->_emit_method($item) };
                if (!defined $result || $@) {
                    push @_skipped_methods, $mname;
                    next;
                }
                if (ref $result eq 'HASH' && defined $result->{helper}) {
                    push @func_lines, $result->{helper}->@*;
                    push @func_lines, '';
                } else {
                    # Unexpected return type — skip
                    push @_skipped_methods, $mname;
                }
            }
        }

        # Assemble the .c file
        my $class_full = $self->module_name();

        # Build deduplicated map: slug => class_name for all polymorphic-dispatch
        # candidates. Used for #include directives, static stash declarations,
        # and init_statics population below.
        my %poly_slug_to_class;
        if ($_polymorphic_dispatch && keys $_polymorphic_dispatch->%*) {
            for my $meth (keys $_polymorphic_dispatch->%*) {
                for my $cand ($_polymorphic_dispatch->{$meth}->@*) {
                    $poly_slug_to_class{ $cand->{slug} } = $cand->{class_name};
                }
            }
        }

        my @c_lines;
        push @c_lines, "/* ABOUTME: C implementation of $class_full (generated by Target::C). */";
        push @c_lines, "/* ABOUTME: Auto-generated from Perl source — do not edit. */";
        push @c_lines, "#include \"chalk.h\"";
        push @c_lines, "#include \"${slug}.h\"";
        # Include headers for cross-class direct calls when field_types is provided.
        my %included_slugs = ($slug => 1);  # track all emitted includes to prevent duplicates
        if ($_field_type_slugs && keys $_field_type_slugs->%*) {
            for my $target_slug (sort values $_field_type_slugs->%*) {
                next if $included_slugs{$target_slug}++;
                push @c_lines, "#include \"${target_slug}.h\"";
            }
        }
        # Include headers for polymorphic dispatch chains (cross-class stash compares).
        for my $poly_slug (sort keys %poly_slug_to_class) {
            next if $included_slugs{$poly_slug}++;
            push @c_lines, "#include \"${poly_slug}.h\"";
        }
        push @c_lines, '';

        # Emit struct typedefs for promoted schemas (if any)
        my $typedefs = $self->generate_typedefs();
        if (length $typedefs) {
            push @c_lines, "/* Struct promotion typedefs */";
            push @c_lines, $typedefs;
        }

        # Emit class-scope static variable declarations (e.g., my $ZERO = []).
        # These are process-global statics, initialised lazily or via a BOOT-like init.
        if (keys $self->_get_class_scope_vars()->%*) {
            push @c_lines, "/* File-scope statics (class-scope lexicals) */";
            for my $var (sort keys $self->_get_class_scope_vars()->%*) {
                my $info = $self->_get_class_scope_vars()->{$var};
                my $c_type = $info->{sigil} eq '%' ? 'HV *'
                           : $info->{sigil} eq '@' ? 'AV *'
                           :                         'SV *';
                push @c_lines, "static ${c_type}$info->{static_name} = NULL;";
            }
            push @c_lines, '';
        }

        # Emit stash pointer statics for polymorphic dispatch chains.
        # Each compiled class referenced in a poly-dispatch chain needs a cached
        # HV* stash pointer so _emit_method_call_expr can do a fast pointer compare.
        if (keys %poly_slug_to_class) {
            for my $poly_slug (sort keys %poly_slug_to_class) {
                push @c_lines, "static HV *_${poly_slug}_stash = NULL;";
            }
            push @c_lines, '';
        }

        # Emit regex statics (if any)
        if ($self->_get_regex_statics() && $self->_get_regex_statics()->@*) {
            for my $rx ($self->_get_regex_statics()->@*) {
                push @c_lines, "static REGEXP *$rx->{var} = NULL;";
            }
            push @c_lines, '';
        }

        # Emit anon sub CV statics (one per compiled anon sub).
        # Each cv_var is assigned in init_statics via newXS.
        if (@_anon_sub_registrations) {
            for my $reg (@_anon_sub_registrations) {
                next unless defined $reg->{cv_var};
                push @c_lines, "static SV *$reg->{cv_var} = NULL;";
            }
            push @c_lines, '';
        }

        # Emit static helpers (subs + anon subs)
        if (@static_lines) {
            push @c_lines, "/* Static helpers */";
            push @c_lines, @static_lines;
        }

        if (@_anon_sub_helpers) {
            push @c_lines, @_anon_sub_helpers;
            push @c_lines, '';
        }

        # Emit init_statics function to initialize class-scope vars.
        # Called from BOOT block of the generated .xs wrapper.
        # Uses a static guard to ensure one-time initialization (thread-unsafe,
        # but acceptable for single-interpreter proof of concept).
        my @init_lines;
        my $init_fn = "${slug}_init_statics";
        push @init_lines, "void ${init_fn}(pTHX) {";
        push @init_lines, "    static int _initialized = 0;";
        push @init_lines, "    if (_initialized) return;";
        push @init_lines, "    _initialized = 1;";
        if (defined $class_decl && keys $self->_get_class_scope_vars()->%*) {
            my $body = $class_decl isa Chalk::IR::ClassInfo
                ? $class_decl->body()
                : $class_decl->inputs()->[2];
            for my $item ($body->@*) {
                next unless $item isa Chalk::IR::Node::VarDecl;
                my $raw = $item->inputs()->[0]->value();
                my $var = $raw;
                $var =~ s/^[\$\@\%]//;
                next unless exists $self->_get_class_scope_vars()->{$var};
                my $info = $self->_get_class_scope_vars()->{$var};
                my $sname = $info->{static_name};
                my $init_node = $item->inputs()->[1];
                my $init_expr = $self->_emit_init_expr($init_node, $info->{sigil});
                push @init_lines, "    $sname = $init_expr;" if defined $init_expr;
            }
        }
        # Initialize anon sub CV statics via newXS.
        # Each registered anon sub gets its XSUB registered under a synthetic package
        # name so call_sv can dispatch to it; the resulting CV is cached in the static.
        for my $reg (@_anon_sub_registrations) {
            next unless defined $reg->{cv_var};
            my $pname = $reg->{name};   # e.g. "::_anon_earley_0"
            my $cname = $reg->{c_name}; # e.g. "XS__anon_earley_0"
            my $cvvar = $reg->{cv_var}; # e.g. "_cv__anon_earley_0"
            push @init_lines,
                "    $cvvar = (SV*)newXS(\"$pname\", $cname, __FILE__);";
        }
        # Populate stash pointer statics for polymorphic dispatch chains.
        # gv_stashpvn resolves the package stash by full class name; the resulting
        # HV* is stored in a file-scope static for O(1) pointer comparison at
        # each polymorphic call site.
        for my $poly_slug (sort keys %poly_slug_to_class) {
            my $class_name = $poly_slug_to_class{$poly_slug};
            my $escaped_class = $self->_escape_c_string($class_name);
            my $len        = length($class_name);
            push @init_lines,
                "    _${poly_slug}_stash = gv_stashpvn(\"${escaped_class}\", ${len}, GV_ADD);";
        }
        push @init_lines, "}";
        push @c_lines, "/* One-time static initializer — called from BOOT */";
        push @c_lines, @init_lines;
        push @c_lines, '';
        push @_exported_functions, {
            name        => $init_fn,
            return_type => 'void',
            params      => 'pTHX',
        };

        # Emit exported functions
        if (@func_lines) {
            push @c_lines, "/* Exported functions */";
            push @c_lines, @func_lines;
        }

        my $c_text = join("\n", @c_lines);
        # Remove trailing blank lines and ensure single newline at end
        $c_text =~ s/\n{3,}/\n\n/g;
        $c_text .= "\n" unless $c_text =~ /\n$/;

        # Assemble the .h file from @_exported_functions
        my $guard = "CHALK_\U${slug}\E_H";
        my @h_lines;
        push @h_lines, "/* ABOUTME: Function prototypes for $class_full (generated). */";
        push @h_lines, "/* ABOUTME: Included by other .c files for cross-class calls. */";
        push @h_lines, "#ifndef ${guard}";
        push @h_lines, "#define ${guard}";
        push @h_lines, "#include \"chalk.h\"";
        push @h_lines, '';
        for my $fn (sort { $a->{name} cmp $b->{name} } @_exported_functions) {
            my $ret   = $fn->{return_type};
            my $fname = $fn->{name};
            my $parms = $fn->{params};
            # Normalise params: ensure pTHX_ prefix for first param
            unless ($parms =~ /^pTHX/) {
                $parms = "pTHX_ $parms";
            }
            push @h_lines, "$ret ${fname}($parms);";
        }
        push @h_lines, '';
        push @h_lines, "#endif /* ${guard} */";

        my $h_text = join("\n", @h_lines) . "\n";

        return {
            files => {
                "${slug}.c" => $c_text,
                "${slug}.h" => $h_text,
            },
            exported_functions    => [@_exported_functions],
            skipped_methods       => [@_skipped_methods],
            anon_sub_registrations => [@_anon_sub_registrations],
        };
    }

    # Generate a thin .xs wrapper for the class.
    # Takes the IR tree, the exported_functions arrayref from generate_c_files,
    # and the anon_sub_registrations arrayref from generate_c_files.
    # Returns the .xs file content as a string.
    #
    # The generated .xs registers the class via the Perl 5.42 C API in BOOT,
    # emits one thin XSUB per exported function (delegating to the C impl),
    # handles _ADJUST as a void XSUB if present, and calls init_statics in BOOT.
    method generate_xs_wrapper($ir, $exported_functions, $anon_sub_registrations) {
        my $slug      = $self->_class_slug($self->module_name());
        my $class_decl = $self->_find_class_decl($ir);

        my @lines;

        # Preamble
        push @lines, "/* ABOUTME: Thin XS wrapper for ${\$self->module_name()} (generated by Target::C). */";
        push @lines, "/* ABOUTME: XSUBs delegate to ${slug}_*() functions in chalk.so. */";
        push @lines, '#include "EXTERN.h"';
        push @lines, '#include "perl.h"';
        push @lines, '#include "XSUB.h"';
        push @lines, "#include \"${slug}.h\"";
        push @lines, '';

        # Forward declarations for the Perl class C API functions.
        # These are in proto.h but guarded by PERL_IN_CLASS_C — declare externally.
        push @lines, '/* Perl_class_* functions are in proto.h but guarded by PERL_IN_CLASS_C. */';
        push @lines, '/* Forward-declare them so BOOT can call them from external XS code.    */';
        push @lines, 'extern void Perl_class_setup_stash(pTHX_ HV *stash);';
        push @lines, 'extern void Perl_class_prepare_initfield_parse(pTHX);';
        push @lines, 'extern void Perl_class_set_field_defop(pTHX_ PADNAME *pn, U32 flags, OP *defop);';
        push @lines, 'extern void Perl_class_apply_field_attributes(pTHX_ PADNAME *pn, OP *attr);';
        push @lines, 'extern void Perl_class_add_ADJUST(pTHX_ HV *stash, CV *cv);';
        push @lines, 'extern void Perl_class_apply_attributes(pTHX_ HV *stash, OP *attrlist);';
        push @lines, '';

        # Classify exported functions: skip init_statics and _ADJUST from regular XSUBs.
        # Match by suffix because class slug (from IR class name) may differ from
        # module slug (from module_name param) — e.g., class Node → slug "node" but
        # module Test::IRNode → slug "irnode". Exact match with $slug would miss.
        # NOTE: suffix matching could theoretically collide with a user method named
        # "init_statics" or "_ADJUST", but no bootstrap source uses these names.
        my $has_adjust = false;
        my $actual_init_fn;
        my $adjust_fn;
        my @xsub_fns;
        for my $fn ($exported_functions->@*) {
            if ($fn->{name} =~ /_init_statics$/) {
                $actual_init_fn = $fn->{name};
                next;  # called from BOOT, not exposed as XSUB
            }
            if ($fn->{name} =~ /_ADJUST$/) {
                $adjust_fn = $fn->{name};
                $has_adjust = true;
                next;  # emitted as void _ADJUST XSUB separately
            }
            push @xsub_fns, $fn;
        }

        # MODULE line
        my $escaped_module = $self->_escape_c_string($self->module_name());
        push @lines, "MODULE = ${\$self->module_name()}  PACKAGE = ${\$self->module_name()}";
        push @lines, '';
        push @lines, 'PROTOTYPES: DISABLE';
        push @lines, '';

        # Void _ADJUST XSUB (if the class has an ADJUST block compiled to C)
        if ($has_adjust) {
            push @lines, 'void';
            push @lines, '_ADJUST(self)';
            push @lines, '    SV *self';
            push @lines, '  CODE:';
            push @lines, "    ${adjust_fn}(aTHX_ self);";
            push @lines, '';
        }

        # One XSUB per exported function
        for my $fn (@xsub_fns) {
            my $fname       = $fn->{name};
            my $return_type = $fn->{return_type} // 'SV *';
            my $params_str  = $fn->{params} // '';

            # Strip pTHX_ prefix from params to get the C parameter list.
            # e.g. "pTHX_ SV *self, SV *value" => "SV *self, SV *value"
            $params_str =~ s/^pTHX_\s*//;
            # Also handle bare "pTHX" (void) case
            $params_str =~ s/^pTHX$//;
            $params_str =~ s/^\s+|\s+$//g;

            # Build the XSUB parameter name list (just the names, not types)
            my @param_names;
            for my $p (split /\s*,\s*/, $params_str) {
                # Each param is like "SV *self" or "SV *value" — extract name
                if ($p =~ /(\w+)\s*$/) {
                    push @param_names, $1;
                }
            }

            # Build the XSUB parameter declaration lines (name: type)
            my @param_decls;
            for my $p (split /\s*,\s*/, $params_str) {
                if ($p =~ /^((?:.*\s+)?\S+\s*\*?\s*)(\w+)\s*$/) {
                    my $type = $1;
                    my $name = $2;
                    $type =~ s/\s+$//;
                    push @param_decls, "    $type\n    $name";
                }
            }

            if ($return_type eq 'void') {
                push @lines, 'void';
            } else {
                push @lines, $return_type;
            }

            # Function signature line: name(param1, param2, ...)
            if (@param_names) {
                push @lines, "${\($fname =~ s/^${slug}_//r)}(" . join(', ', @param_names) . ')';
            } else {
                push @lines, "${\($fname =~ s/^${slug}_//r)}()";
            }

            # Parameter type declarations (XS format: type\nname per param, after self)
            for my $p (split /\s*,\s*/, $params_str) {
                next unless $p =~ /\S/;
                if ($p =~ /^(SV\s*\*)\s*(\w+)$/) {
                    push @lines, "    SV *$2";
                } elsif ($p =~ /^(IV)\s*(\w+)$/) {
                    push @lines, "    IV $2";
                } elsif ($p =~ /^(NV)\s*(\w+)$/) {
                    push @lines, "    NV $2";
                } else {
                    # Default to SV * for unknown types
                    if ($p =~ /(\w+)\s*$/) {
                        push @lines, "    SV *$1";
                    }
                }
            }

            my $call_args = @param_names
                ? 'aTHX_ ' . join(', ', @param_names)
                : 'aTHX';
            if ($return_type eq 'void') {
                push @lines, '  CODE:';
                push @lines, "    ${fname}(${call_args});";
            } else {
                push @lines, '  CODE:';
                push @lines, "    RETVAL = ${fname}(${call_args});";
                push @lines, '  OUTPUT:';
                push @lines, '    RETVAL';
            }
            push @lines, '';
        }

        # BOOT block
        push @lines, 'BOOT:';
        push @lines, '{';
        push @lines, "    HV *stash = gv_stashpv(\"$escaped_module\", GV_ADD);";
        push @lines, '    HV *old_stash = PL_curstash;';
        push @lines, '    PL_curstash = stash;';
        push @lines, '    ENTER;';
        push @lines, '    Perl_class_setup_stash(aTHX_ stash);';

        # Register :isa (parent class) if the ClassDecl has a parent
        if (defined $class_decl) {
            my $parent_name;
            if ($class_decl isa Chalk::IR::ClassInfo) {
                $parent_name = $class_decl->parent();
            } else {
                my $parent_node = $class_decl->inputs()->[1];
                $parent_name = defined $parent_node && $parent_node isa Chalk::Bootstrap::IR::Node::Constant
                    ? $parent_node->value()
                    : undef;
            }
            if (defined $parent_name) {
                my $escaped_parent = $self->_escape_c_string($parent_name);
                push @lines, "    {";
                push @lines, "        OP *isa_attr = newSVOP(OP_CONST, 0, newSVpvs(\"isa($escaped_parent)\"));";
                push @lines, "        Perl_class_apply_attributes(aTHX_ stash, isa_attr);";
                push @lines, "    }";
            }
        }
        push @lines, '';

        # Register fields (if the class has any FieldDecl nodes)
        if (defined $class_decl) {
            my $body = $class_decl isa Chalk::IR::ClassInfo
                ? $class_decl->body()
                : $class_decl->inputs()->[2];
            for my $item ($body->@*) {
                my ($field_name, $attrs, $default);
                if ($item isa Chalk::IR::FieldInfo) {
                    $field_name = $item->name();
                    $attrs      = $item->attributes();
                    $default    = $item->default_value();
                } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                         && $item->class() eq 'FieldDecl') {
                    $field_name = $item->inputs()->[0]->value();
                    $attrs      = $item->inputs()->[1];
                    $default    = $item->inputs()->[2];
                } else {
                    next;
                }
                # $field_name includes sigil
                my $escaped    = $self->_escape_c_string($field_name);

                push @lines, '    {';
                push @lines, '        ENTER;';
                push @lines, '        Perl_class_prepare_initfield_parse(aTHX);';
                push @lines, "        PADOFFSET padix = pad_add_name_pvs(\"$escaped\", padadd_FIELD, NULL, NULL);";
                push @lines, '        PADNAME *pn = PadnamelistARRAY(PadlistNAMES(CvPADLIST(PL_compcv)))[padix];';

                # Apply field attributes (:param, :reader, :writer)
                if (ref($attrs) eq 'ARRAY') {
                    for my $attr ($attrs->@*) {
                        my $attr_name;
                        if (ref($attr) eq 'HASH') {
                            $attr_name = $attr->{name};
                        } else {
                            # Legacy Constructor:_Attribute node
                            $attr_name = $attr->inputs()->[0]->value();
                        }
                        my $escaped_attr = $self->_escape_c_string($attr_name);
                        push @lines, '        {';
                        push @lines, "            OP *attr = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped_attr\"));";
                        push @lines, '            Perl_class_apply_field_attributes(aTHX_ pn, attr);';
                        push @lines, '        }';
                    }
                }

                # Emit defop for default value (if present)
                if (defined $default) {
                    my @defop_lines = $self->_emit_defop_for_xs_wrapper($default);
                    push @lines, @defop_lines;
                }

                push @lines, '        LEAVE;';
                push @lines, '    }';
            }
            push @lines, '';
        }

        # Register _ADJUST XSUB if one was compiled
        if ($has_adjust) {
            push @lines, '    /* Register _ADJUST XSUB as ADJUST block */';
            push @lines, '    {';
            push @lines, '        GV *adjust_gv = gv_fetchpvs("_ADJUST", 0, SVt_PVCV);';
            push @lines, '        if (adjust_gv && GvCV(adjust_gv)) {';
            push @lines, '            Perl_class_add_ADJUST(aTHX_ stash, GvCV(adjust_gv));';
            push @lines, '        }';
            push @lines, '    }';
            push @lines, '';
        }

        # Call init_statics to initialize class-scope static variables
        if (defined $actual_init_fn) {
            push @lines, "    ${actual_init_fn}(aTHX);";
        }
        push @lines, '';

        # LEAVE triggers SAVEDESTRUCTOR_X which calls class_seal_stash
        push @lines, '    LEAVE;';
        push @lines, '    PL_curstash = old_stash;';
        push @lines, '}';

        return join("\n", @lines) . "\n";
    }

    # Emit defop lines for a field default value in an XS wrapper BOOT block.
    # Returns a list of C lines (indented for the field registration block).
    # This handles the same IR node types as Target::XS's _emit_defop method.
    method _emit_defop_for_xs_wrapper($default) {
        my @lines;
        push @lines, '        {';

        if ($default isa Chalk::Bootstrap::IR::Node::Constant) {
            my $val = $default->value();
            if ($val eq 'undef') {
                push @lines, '            OP *defop = newSVOP(OP_CONST, 0, &PL_sv_undef);';
            } elsif ($val eq 'true') {
                push @lines, '            OP *defop = newSVOP(OP_CONST, 0, &PL_sv_yes);';
            } elsif ($val eq 'false') {
                push @lines, '            OP *defop = newSVOP(OP_CONST, 0, &PL_sv_no);';
            } elsif ($val =~ /^-?\d+$/) {
                push @lines, "            OP *defop = newSVOP(OP_CONST, 0, newSViv($val));";
            } elsif ($val =~ /^-?\d+\.\d+$/) {
                push @lines, "            OP *defop = newSVOP(OP_CONST, 0, newSVnv($val));";
            } else {
                my $escaped = $self->_escape_c_string($val);
                push @lines, "            OP *defop = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped\"));";
            }
        } elsif ($default isa Chalk::IR::Node::ArrayRef) {
            push @lines, '            OP *defop = newANONLIST(NULL);';
        } elsif ($default isa Chalk::IR::Node::HashRef) {
            push @lines, '            OP *defop = newANONHASH(NULL);';
        } else {
            # Unknown default — skip defop entirely
            return ();
        }

        push @lines, '            defop->op_next = NULL;';
        push @lines, '            Perl_class_set_field_defop(aTHX_ pn, 0, defop);';
        push @lines, '        }';

        return @lines;
    }
}

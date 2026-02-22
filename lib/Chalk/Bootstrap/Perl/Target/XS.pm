# ABOUTME: Walks Perl IR and emits XS/C code with bless-based OO wrapper.
# ABOUTME: Generates .xs, .pm stub, and Build.PL for Tier A-C classes via Perl API.
use 5.42.0;
use utf8;
use experimental 'class';

use bytes ();
use Chalk::Bootstrap::Target;

class Chalk::Bootstrap::Perl::Target::XS :isa(Chalk::Bootstrap::Target) {
    field $module_name :param :reader;

    ADJUST {
        die "Invalid module name: $module_name"
            unless $module_name =~ /^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$/;
    }

    method generate($ir) {
        die "generate() requires a Constructor:Program IR node"
            unless defined($ir)
            && $ir isa Chalk::Bootstrap::IR::Node::Constructor
            && $ir->class() eq 'Program';

        return $self->_emit_xs($ir);
    }

    method generate_distribution($ir) {
        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $pm_path = $self->_module_path_prefix() . '.pm';

        return {
            $xs_path   => $self->_emit_xs($ir),
            $pm_path   => $self->_emit_pm_stub($ir),
            'Build.PL' => $self->_emit_build_pl(),
        };
    }

    # Convert module name to file path prefix
    method _module_path_prefix() {
        my $path = $module_name;
        $path =~ s{::}{/}g;
        return "lib/$path";
    }

    # Extract ClassDecl from Program IR
    method _find_class_decl($ir) {
        my $stmts = $ir->inputs()->[0];
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && $stmt->class() eq 'ClassDecl') {
                return $stmt;
            }
        }
        return undef;
    }

    # Build field index map from ClassDecl IR.
    # Returns hashref mapping field name (without sigil) to integer index.
    # Fields are numbered in declaration order starting from 0.
    method _build_field_index_map($class_decl) {
        my $body = $class_decl->inputs()->[2];
        my %field_map;
        my $index = 0;

        for my $item ($body->@*) {
            if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'FieldDecl') {
                my $name_node = $item->inputs()->[0];
                my $field_name = $name_node->value();
                $field_name =~ s/^\$//;  # Strip sigil
                $field_map{$field_name} = $index++;
            }
        }

        return \%field_map;
    }

    # Emit BOOT block for feature class setup.
    # Generates class_setup_stash, field registration, class_seal_stash,
    # and new() re-installation sequence using Perl 5.42.0 C API.
    # Note: new() re-installation is commented out for now - will be implemented
    # in a later component when shadow constructor XSUB is added.
    method _emit_xs_boot_block($class_decl, $field_map) {
        my @lines;
        push @lines, 'BOOT:';
        push @lines, '{';

        # Get stash and save PL_curstash
        my $escaped_module = $self->_escape_c_string($module_name);
        push @lines, "    HV *stash = gv_stashpv(\"$escaped_module\", GV_ADD);";
        push @lines, '    HV *old_stash = PL_curstash;';
        push @lines, '    PL_curstash = stash;';
        push @lines, '';

        # 1. Create class
        push @lines, '    Perl_class_setup_stash(aTHX_ stash);';
        push @lines, '';

        # 2. Add fields in order
        my $body = $class_decl->inputs()->[2];
        for my $item ($body->@*) {
            if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'FieldDecl') {
                my $name_node = $item->inputs()->[0];
                my $field_name = $name_node->value();  # Includes sigil
                my $escaped = $self->_escape_c_string($field_name);
                push @lines, '    Perl_class_prepare_initfield_parse(aTHX);';
                push @lines, "    pad_add_name_pvs(\"$escaped\", padadd_FIELD, NULL, NULL);";
            }
        }
        push @lines, '';

        # 3. Seal class (generates auto new())
        push @lines, '    Perl_class_seal_stash(aTHX_ stash);';
        push @lines, '';

        # 4. Grab auto new(), clear GV, install shadow
        # TODO: Implement shadow constructor XSUB in Component B
        # For now, we rely on the auto-generated new() from class_seal_stash
        my $sanitized = $module_name;
        $sanitized =~ s/::/_/g;
        my $xs_func_name = $module_name;
        $xs_func_name =~ s/::/double_underscore_temp/g;
        $xs_func_name =~ s/double_underscore_temp/__/g;
        push @lines, '    GV *gv = gv_fetchmethod(stash, "new");';
        push @lines, "    ${sanitized}_original_new = GvCV(gv);";
        push @lines, "    SvREFCNT_inc((SV*)${sanitized}_original_new);";
        push @lines, '    GvCV_set(gv, NULL);';
        push @lines, "    newXS(\"${module_name}::new\", XS_${xs_func_name}_new, __FILE__);";
        push @lines, '';

        # Restore PL_curstash
        push @lines, '    PL_curstash = old_stash;';
        push @lines, '}';

        return \@lines;
    }

    # Escape a string for C double-quoted literal
    method _escape_c_string($str) {
        $str =~ s/\\/\\\\/g;
        $str =~ s/"/\\"/g;
        $str =~ s/\n/\\n/g;
        $str =~ s/\t/\\t/g;
        $str =~ s/\r/\\r/g;
        $str =~ s/\0/\\0/g;
        $str =~ s/([^\x20-\x7E])/sprintf("\\x%02x", ord($1))/ge;
        return $str;
    }

    # Emit shadow constructor XSUB with param extraction and defaults.
    # This XSUB calls the auto-generated new() to allocate the PVOBJ,
    # then extracts named params from @_, validates required params,
    # and applies defaults for optional params.
    method _emit_xs_shadow_constructor($class_decl, $sanitized, $field_map) {
        my @lines;
        my $body = $class_decl->inputs()->[2];

        # Collect param fields with their metadata
        my @param_fields;
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor
                     && $item->class() eq 'FieldDecl';

            my $name_node = $item->inputs()->[0];
            my $attrs = $item->inputs()->[1];
            my $default = $item->inputs()->[2];

            # Check for :param attribute
            my $has_param = false;
            if (ref($attrs) eq 'ARRAY') {
                for my $attr ($attrs->@*) {
                    if ($attr->inputs()->[0]->value() eq 'param') {
                        $has_param = true;
                        last;
                    }
                }
            }
            next unless $has_param;

            my $field_name = $name_node->value();
            $field_name =~ s/^\$//;  # Strip sigil
            my $index = $field_map->{$field_name};
            my $is_required = !defined $default;

            push @param_fields, {
                name => $field_name,
                index => $index,
                required => $is_required,
                default => $default,
            };
        }

        # Emit XSUB signature
        push @lines, 'SV *';
        push @lines, 'new(class, ...)';
        push @lines, '    SV *class';
        push @lines, '  CODE:';

        # Call auto-generated new() to allocate PVOBJ
        push @lines, '    {';
        push @lines, "        if (!${sanitized}_original_new) {";
        push @lines, '            croak("BOOT block has not run yet");';
        push @lines, '        }';
        push @lines, '        dSP;';
        push @lines, '        ENTER; SAVETMPS;';
        push @lines, '        PUSHMARK(SP);';
        push @lines, '        XPUSHs(class);';
        push @lines, '        PUTBACK;';
        push @lines, "        call_sv((SV*)${sanitized}_original_new, G_SCALAR);";
        push @lines, '        SPAGAIN;';
        push @lines, '        RETVAL = SvREFCNT_inc(POPs);';
        push @lines, '        PUTBACK; FREETMPS; LEAVE;';
        push @lines, '    }';

        # Extract named params and apply defaults
        if (@param_fields) {
            push @lines, '    {';
            push @lines, '        SV *obj = SvRV(RETVAL);';
            push @lines, '        SV **fields = ObjectFIELDS(obj);';
            push @lines, '        int i;';

            # Declare got_* flags for each param
            for my $field (@param_fields) {
                push @lines, "        bool got_$field->{name} = FALSE;";
            }

            # Check for odd number of arguments
            push @lines, '        if ((items - 1) % 2 != 0) croak("Odd number of arguments");';

            # Iterate @_ and match params
            push @lines, '        for (i = 1; i < items; i += 2) {';
            push @lines, '            const char *key = SvPV_nolen(ST(i));';

            for my $field (@param_fields) {
                my $name = $field->{name};
                my $idx = $field->{index};
                push @lines, "            if (strEQ(key, \"$name\")) { sv_setsv(fields[$idx], ST(i+1)); got_$name = TRUE; }";
            }

            push @lines, '            else { croak("Unknown parameter \'%s\'", key); }';
            push @lines, '        }';

            # Validate required params
            for my $field (@param_fields) {
                next unless $field->{required};
                my $name = $field->{name};
                push @lines, "        if (!got_$name) croak(\"Required parameter '$name' is missing\");";
            }

            # Apply defaults for optional params
            for my $field (@param_fields) {
                next if $field->{required};
                my $name = $field->{name};
                my $idx = $field->{index};
                my $default = $field->{default};

                if (defined $default && $default isa Chalk::Bootstrap::IR::Node::Constant) {
                    my $val = $default->value();
                    if ($val =~ /^-?\d+$/) {
                        # Integer default
                        push @lines, "        if (!got_$name) { sv_setiv(fields[$idx], $val); }";
                    } elsif ($val =~ /^-?\d+\.\d+$/) {
                        # Float default
                        push @lines, "        if (!got_$name) { sv_setnv(fields[$idx], $val); }";
                    } else {
                        # String default
                        my $escaped = $self->_escape_c_string($val);
                        push @lines, "        if (!got_$name) { sv_setpv(fields[$idx], \"$escaped\"); }";
                    }
                }
            }

            push @lines, '    }';
        }

        push @lines, '  OUTPUT:';
        push @lines, '    RETVAL';

        return \@lines;
    }

    # Emit the .xs file
    method _emit_xs($ir) {
        my $class_decl = $self->_find_class_decl($ir);
        my @lines;

        # XS preamble
        push @lines, '#include "EXTERN.h"';
        push @lines, '#include "perl.h"';
        push @lines, '#include "XSUB.h"';
        push @lines, '';

        # Forward declarations for feature class C API
        push @lines, 'extern void Perl_class_setup_stash(pTHX_ HV *stash);';
        push @lines, 'extern void Perl_class_seal_stash(pTHX_ HV *stash);';
        push @lines, 'extern void Perl_class_prepare_initfield_parse(pTHX);';
        push @lines, 'extern void Perl_class_apply_attributes(pTHX_ HV *stash, OP *attrlist);';
        push @lines, '';

        # Static variable for original new() CV
        if (defined $class_decl) {
            my $sanitized = $module_name;
            $sanitized =~ s/::/_/g;
            push @lines, "static CV *${sanitized}_original_new = NULL;";
            push @lines, '';
        }

        push @lines, "MODULE = $module_name  PACKAGE = $module_name";
        push @lines, '';

        if (defined $class_decl) {
            # Build field map once for use in constructor and BOOT block
            my $field_map = $self->_build_field_index_map($class_decl);

            # Emit shadow new() XSUB with param extraction and defaults
            my $sanitized = $module_name;
            $sanitized =~ s/::/_/g;
            push @lines, $self->_emit_xs_shadow_constructor($class_decl, $sanitized, $field_map)->@*;
            push @lines, '';

            my $body = $class_decl->inputs()->[2];
            for my $item ($body->@*) {
                if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                        && $item->class() eq 'FieldDecl') {
                    my @reader_lines = $self->_emit_xs_field_reader($item)->@*;
                    if (@reader_lines) {
                        push @lines, @reader_lines;
                        push @lines, '';
                    }
                } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                        && $item->class() eq 'MethodDecl') {
                    push @lines, $self->_emit_xs_method($item)->@*;
                    push @lines, '';
                }
            }

            # Emit BOOT block after XSUBs
            push @lines, $self->_emit_xs_boot_block($class_decl, $field_map)->@*;
        }

        return join("\n", @lines) . "\n";
    }

    # Emit a single XSUB for a MethodDecl
    method _emit_xs_method($method_decl) {
        my $name   = $method_decl->inputs()->[0]->value();
        my $params = $method_decl->inputs()->[1];
        my $body   = $method_decl->inputs()->[2];

        my @lines;

        # Check for simple single-statement bodies first (Tier A/B patterns)
        if (scalar $body->@* == 1) {
            my $body_item = $body->[0];
            my $returns_value = (defined $body_item
                && $body_item isa Chalk::Bootstrap::IR::Node::Constructor
                && $body_item->class() eq 'ReturnStmt');
            my $dies = (defined $body_item
                && $body_item isa Chalk::Bootstrap::IR::Node::Constructor
                && $body_item->class() eq 'DieCall');

            if ($returns_value) {
                my $value = $body_item->inputs()->[0];

                if ($value isa Chalk::Bootstrap::IR::Node::Constructor
                        && $value->class() eq 'InterpolatedString') {
                    push @lines, $self->_emit_xs_interp_return($name, $value)->@*;
                    return \@lines;
                } elsif ($value isa Chalk::Bootstrap::IR::Node::Constant
                         && ($value->const_type() // '') ne 'variable'
                         && $value->value() !~ /^[\$\@\%]/) {
                    my $str = $self->_escape_c_string($value->value());
                    push @lines, 'SV *';
                    push @lines, "${name}(self, ...)";
                    push @lines, '    SV *self';
                    push @lines, '  CODE:';
                    push @lines, "    RETVAL = newSVpvs(\"$str\");";
                    push @lines, '  OUTPUT:';
                    push @lines, '    RETVAL';
                    return \@lines;
                }
                # Non-trivial return value — fall through to complex handler
            }

            if ($dies) {
                my $args = $body_item->inputs()->[0];
                my $msg = '';
                if (ref($args) eq 'ARRAY' && $args->@*) {
                    $msg = $self->_escape_c_string($args->[0]->value());
                }

                my @xs_params = ('SV *self');
                for my $p ($params->@*) {
                    my $pname = $p->value();
                    $pname =~ s/^\$//;
                    push @xs_params, "SV *$pname";
                }

                push @lines, 'void';
                push @lines, "${name}(" . join(', ', @xs_params) . ")";
                for my $p (@xs_params) {
                    push @lines, "    $p";
                }
                push @lines, '  CODE:';
                push @lines, "    croak(\"%s\", \"$msg\");";
                return \@lines;
            }
        }

        # Multi-statement body or empty body — use general body emitter
        if ($body->@* == 0) {
            push @lines, 'void';
            push @lines, "${name}(self)";
            push @lines, '    SV *self';
            push @lines, '  CODE:';
            push @lines, '    /* empty */';
            return \@lines;
        }

        return $self->_emit_xs_complex_method($name, $params, $body);
    }

    # Emit a multi-statement method body as an XSUB using Perl API calls.
    # Collects variable declarations into PREINIT section and body statements
    # into CODE section. Uses eval_pv() for constructs too complex for pure C
    # (regex, backticks, complex interpolation).
    method _emit_xs_complex_method($name, $params, $body) {
        my @lines;
        my @code;

        # Determine if the method returns a value (last item is ReturnStmt)
        my $last_item = $body->[-1];
        my $has_return = (defined $last_item
            && $last_item isa Chalk::Bootstrap::IR::Node::Constructor
            && $last_item->class() eq 'ReturnStmt');

        # Track C variable declarations needed
        my %declared_vars;
        $declared_vars{hash} = true;  # always need hash for self access

        # Track method parameters as declared vars before body emission,
        # so _emit_xs_const_expr can resolve them as C parameters
        my @xs_params = ('SV *self');
        for my $p ($params->@*) {
            my $pname = $p->value();
            $pname =~ s/^\$//;
            push @xs_params, "SV *$pname";
            $declared_vars{"param:$pname"} = true;
        }

        # Recursively collect all variable declarations from the body,
        # including those in nested scopes (if/foreach/etc.)
        $self->_collect_var_decls($body, \%declared_vars);

        # Detect early returns (ReturnStmt inside IfStmt or non-final position)
        my $has_early_return = $self->_has_early_return($body);

        # Emit each body item as C code, marking the last statement
        for my $idx (0 .. $body->@* - 1) {
            my $is_last = ($idx == $body->@* - 1);
            my $stmt = $self->_emit_xs_stmt($body->[$idx], \%declared_vars, $is_last);
            push @code, $stmt if defined $stmt;
        }

        if ($has_return) {
            push @lines, 'SV *';
        } else {
            push @lines, 'void';
        }
        # XS signature line uses bare names; typed declarations go below
        my @bare_params = map { /^SV \*(.*)/ ? $1 : $_ } @xs_params;
        push @lines, "${name}(" . join(', ', @bare_params) . ")";
        for my $p (@xs_params) {
            push @lines, "    $p";
        }

        # PREINIT section for variable declarations
        push @lines, '  PREINIT:';
        push @lines, '    HV *hash;';
        push @lines, '    SV **svp;';
        for my $var (sort keys %declared_vars) {
            next if $var eq 'hash';
            next if $var =~ /^param:/;  # method params are XS parameters, not PREINIT vars
            push @lines, "    SV *${var}_sv = NULL;";
        }

        # CODE section
        push @lines, '  CODE:';
        push @lines, '    hash = (HV*)SvRV(self);';
        for my $stmt (@code) {
            for my $line (split /\n/, $stmt) {
                push @lines, "    $line";
            }
        }

        if ($has_return) {
            # Label for early returns to jump to before OUTPUT section
            if ($has_early_return) {
                push @lines, '    xsreturn:';
            }
            push @lines, '  OUTPUT:';
            push @lines, '    RETVAL';
        }

        return \@lines;
    }

    # Check if a body contains early returns (ReturnStmt inside IfStmt)
    method _has_early_return($nodes) {
        for my $item ($nodes->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            my $class = $item->class();
            if ($class eq 'IfStmt') {
                my $then_body = $item->inputs()->[1];
                if ($self->_body_contains_return($then_body)) {
                    return true;
                }
                my $else_body = $item->inputs()->[2];
                if (defined($else_body) && ref($else_body) eq 'ARRAY'
                        && $self->_body_contains_return($else_body)) {
                    return true;
                }
            }
        }
        return false;
    }

    # Check if a body array contains any ReturnStmt
    method _body_contains_return($body) {
        return false unless ref($body) eq 'ARRAY';
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            return true if $item->class() eq 'ReturnStmt';
            if ($item->class() eq 'IfStmt') {
                my $then = $item->inputs()->[1];
                return true if $self->_body_contains_return($then);
                my $else = $item->inputs()->[2];
                return true if defined($else) && $self->_body_contains_return($else);
            }
        }
        return false;
    }

    # Recursively collect VarDecl and ForeachLoop iterator names from IR
    # nodes at any nesting depth, so PREINIT has all needed declarations.
    method _collect_var_decls($nodes, $declared_vars) {
        for my $item ($nodes->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            my $class = $item->class();

            if ($class eq 'VarDecl') {
                my $var = $item->inputs()->[0]->value();
                $var =~ s/^[\$\@\%]//;
                $declared_vars->{$var} = true;
            }
            if ($class eq 'ForeachLoop') {
                # Iterator variable
                my $iter = $item->inputs()->[0]->value();
                $iter =~ s/^[\$\@\%]//;
                $declared_vars->{$iter} = true;
                # Recurse into loop body
                my $body = $item->inputs()->[2];
                $self->_collect_var_decls($body, $declared_vars) if ref($body) eq 'ARRAY';
            }
            if ($class eq 'IfStmt') {
                my $then_body = $item->inputs()->[1];
                $self->_collect_var_decls($then_body, $declared_vars) if ref($then_body) eq 'ARRAY';
                my $else_body = $item->inputs()->[2];
                $self->_collect_var_decls($else_body, $declared_vars) if defined($else_body) && ref($else_body) eq 'ARRAY';
            }
            if ($class eq 'PostfixLoop') {
                my $body = $item->inputs()->[1];
                $self->_collect_var_decls($body, $declared_vars) if ref($body) eq 'ARRAY';
            }
        }
    }

    # Emit a single IR node as a C statement line.
    # $is_last indicates whether this is the final statement in the method body.
    method _emit_xs_stmt($node, $declared_vars, $is_last = true) {
        return undef unless defined $node;

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();

            if ($class eq 'VarDecl')         { return $self->_emit_xs_var_decl($node, $declared_vars); }
            if ($class eq 'ReturnStmt')      { return $self->_emit_xs_return_stmt($node, $declared_vars, $is_last); }
            if ($class eq 'DieCall')         { return $self->_emit_xs_die_call($node); }
            if ($class eq 'IfStmt')          { return $self->_emit_xs_if_stmt($node, $declared_vars); }
            if ($class eq 'ForeachLoop')     { return $self->_emit_xs_foreach_loop($node, $declared_vars); }
            if ($class eq 'CompoundAssign')  { return $self->_emit_xs_compound_assign_stmt($node, $declared_vars); }
            if ($class eq 'PostfixLoop')     { return $self->_emit_xs_postfix_loop($node, $declared_vars); }
            if ($class eq 'NextUnless')      { return $self->_emit_xs_next_unless($node, $declared_vars); }

            # Expression types used as statements (side effects)
            return $self->_emit_xs_expr($node, $declared_vars) . ";";
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            return $self->_emit_xs_expr($node, $declared_vars) . ";";
        }

        return "/* unknown node */";
    }

    # Emit a C expression for an IR node
    method _emit_xs_expr($node, $declared_vars) {
        return 'NULL' unless defined $node;

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            return $self->_emit_xs_const_expr($node, $declared_vars);
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();

            if ($class eq 'InterpolatedString') { return $self->_emit_xs_interp_expr($node, $declared_vars); }
            if ($class eq 'BinaryExpr')         { return $self->_emit_xs_binary_expr($node, $declared_vars); }
            if ($class eq 'UnaryExpr')          { return $self->_emit_xs_unary_expr($node, $declared_vars); }
            if ($class eq 'MethodCallExpr')     { return $self->_emit_xs_method_call_expr($node, $declared_vars); }
            if ($class eq 'SubscriptExpr')      { return $self->_emit_xs_subscript_expr($node, $declared_vars); }
            if ($class eq 'PostfixDerefExpr')   { return $self->_emit_xs_postfix_deref_expr($node, $declared_vars); }
            if ($class eq 'TernaryExpr')        { return $self->_emit_xs_ternary_expr($node, $declared_vars); }
            if ($class eq 'HashRefExpr')        { return $self->_emit_xs_hash_ref_expr($node, $declared_vars); }
            if ($class eq 'ArrayRefExpr')       { return $self->_emit_xs_array_ref_expr($node, $declared_vars); }
            if ($class eq 'AnonSubExpr')        { return $self->_emit_xs_anon_sub_expr($node, $declared_vars); }
            if ($class eq 'RegexMatch')         { return $self->_emit_xs_regex_match($node, $declared_vars); }
            if ($class eq 'RegexSubst')         { return $self->_emit_xs_regex_subst($node, $declared_vars); }
            if ($class eq 'BuiltinCall')        { return $self->_emit_xs_builtin_call($node, $declared_vars); }
            if ($class eq 'BacktickExpr')       { return $self->_emit_xs_backtick_expr($node, $declared_vars); }
            if ($class eq 'CompoundAssign')     { return $self->_emit_xs_compound_assign_expr($node, $declared_vars); }
            if ($class eq 'VarDecl')            { return $self->_emit_xs_var_decl_expr($node, $declared_vars); }
        }

        return "NULL /* unsupported */";
    }

    # Emit a Constant IR node as a C expression
    method _emit_xs_const_expr($node, $declared_vars) {
        my $val = $node->value();
        my $ct  = $node->const_type();

        # Variable reference — look up from hash or local C var
        if ($ct eq 'variable' || $val =~ /^[\$\@\%]/) {
            my $var = $val;
            $var =~ s/^[\$\@\%]//;
            # $self is the XS method receiver — use the C parameter directly
            if ($var eq 'self') {
                return 'self';
            }
            # Regex capture variables ($1, $2, ...) — fetch from package
            # globals set by _emit_xs_regex_match wrapper
            if ($var =~ /^\d+$/) {
                return "get_sv(\"::_c$var\", GV_ADD)";
            }
            if ($declared_vars && $declared_vars->{$var}) {
                return "${var}_sv";
            }
            # Method parameters are bare C variables (no _sv suffix)
            if ($declared_vars && $declared_vars->{"param:$var"}) {
                return $var;
            }
            # Field access: fetch from self hash
            my $escaped = $self->_escape_c_string($var);
            return "((svp = hv_fetch(hash, \"$escaped\", " . bytes::length($var) . ", 0)) ? *svp : &PL_sv_undef)";
        }

        # Numeric values — sv_2mortal prevents leaks when used as sub-expressions
        if ($val =~ /^-?[0-9]+$/) {
            return "sv_2mortal(newSViv($val))";
        }
        if ($val =~ /^-?[0-9]+\.[0-9]+$/) {
            return "sv_2mortal(newSVnv($val))";
        }

        # Boolean/special
        if ($val eq 'true')  { return '&PL_sv_yes'; }
        if ($val eq 'false') { return '&PL_sv_no'; }
        if ($val eq 'undef') { return '&PL_sv_undef'; }

        # String literal — sv_2mortal prevents leaks when used as sub-expressions
        my $escaped = $self->_escape_c_string($val);
        return "sv_2mortal(newSVpvs(\"$escaped\"))";
    }

    # Emit an InterpolatedString as a C expression building an SV via
    # sv_catpvs/sv_catsv. Variables are resolved from the declared_vars
    # (local C vars) or the blessed hash (field access).
    method _emit_xs_interp_expr($node, $declared_vars) {
        my $parts = $node->inputs()->[0];
        return '&PL_sv_undef' unless $parts->@*;

        # Build a series of newSVpvs + sv_cat* operations.
        # Since C can't do this in a single expression, we use a GCC
        # statement expression ({...}) to keep it as an expression.
        my @stmts;
        my $first = true;

        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                my $var = $part->value();
                $var =~ s/^\$//;
                my $src;
                # Regex capture variables ($1, $2, ...) — fetch from package
                # globals set by _emit_xs_regex_match wrapper
                if ($var =~ /^\d+$/) {
                    $src = "get_sv(\"::_c$var\", GV_ADD)";
                } elsif ($declared_vars && $declared_vars->{$var}) {
                    $src = "${var}_sv ? ${var}_sv : &PL_sv_undef";
                } else {
                    my $escaped = $self->_escape_c_string($var);
                    $src = "(svp = hv_fetch(hash, \"$escaped\", " . bytes::length($var) . ", 0)) ? *svp : &PL_sv_undef";
                }
                if ($first) {
                    push @stmts, "SV *_r = newSVsv($src)";
                    $first = false;
                } else {
                    push @stmts, "sv_catsv(_r, $src)";
                }
            } else {
                my $lit = $self->_escape_c_string($part->value());
                if ($first) {
                    push @stmts, "SV *_r = newSVpvs(\"$lit\")";
                    $first = false;
                } else {
                    push @stmts, "sv_catpvs(_r, \"$lit\")";
                }
            }
        }

        push @stmts, '_r';
        return '({ ' . join('; ', @stmts) . '; })';
    }

    # Emit binary expression as C code using Perl API
    method _emit_xs_binary_expr($node, $declared_vars) {
        my $op    = $node->inputs()->[0]->value();
        my $left  = $self->_emit_xs_expr($node->inputs()->[1], $declared_vars);
        my $right = $self->_emit_xs_expr($node->inputs()->[2], $declared_vars);

        # String comparison ops
        if ($op eq 'eq') { return "(sv_eq($left, $right) ? &PL_sv_yes : &PL_sv_no)"; }
        if ($op eq 'ne') { return "(!sv_eq($left, $right) ? &PL_sv_yes : &PL_sv_no)"; }
        if ($op eq '.') {
            return "({ SV *_c = sv_2mortal(newSVsv($left)); sv_catsv(_c, $right); _c; })";
        }
        # Short-circuit — evaluate $left once into temp to avoid double evaluation
        if ($op eq '&&' || $op eq 'and') { return "({ SV *_l = $left; SvTRUE(_l) ? $right : _l; })"; }
        if ($op eq '||' || $op eq 'or')  { return "({ SV *_l = $left; SvTRUE(_l) ? _l : $right; })"; }
        if ($op eq '//')                  { return "({ SV *_l = $left; SvOK(_l) ? _l : $right; })"; }

        # Numeric ops — sv_2mortal prevents leaks when used as sub-expressions
        if ($op eq '+')  { return "sv_2mortal(newSVnv(SvNV($left) + SvNV($right)))"; }
        if ($op eq '-')  { return "sv_2mortal(newSVnv(SvNV($left) - SvNV($right)))"; }
        if ($op eq '*')  { return "sv_2mortal(newSVnv(SvNV($left) * SvNV($right)))"; }
        if ($op eq '/')  { return "sv_2mortal(newSVnv(SvNV($left) / SvNV($right)))"; }
        if ($op eq '==') { return "(SvNV($left) == SvNV($right) ? &PL_sv_yes : &PL_sv_no)"; }
        if ($op eq '!=') { return "(SvNV($left) != SvNV($right) ? &PL_sv_yes : &PL_sv_no)"; }
        if ($op eq '<')  { return "(SvNV($left) < SvNV($right) ? &PL_sv_yes : &PL_sv_no)"; }
        if ($op eq '>')  { return "(SvNV($left) > SvNV($right) ? &PL_sv_yes : &PL_sv_no)"; }
        if ($op eq '<=') { return "(SvNV($left) <= SvNV($right) ? &PL_sv_yes : &PL_sv_no)"; }
        if ($op eq '>=') { return "(SvNV($left) >= SvNV($right) ? &PL_sv_yes : &PL_sv_no)"; }

        # isa — check if left derives from the class named in right
        if ($op eq 'isa') {
            return "(sv_derived_from_sv($left, $right, 0) ? &PL_sv_yes : &PL_sv_no)";
        }

        # Range operator — construct an AV from integer start to end
        if ($op eq '..') {
            return "({ AV *_av = newAV(); SSize_t _s = SvIV($left); SSize_t _e = SvIV($right); SSize_t _j; for (_j = _s; _j <= _e; _j++) av_push(_av, newSViv(_j)); newRV_noinc((SV*)_av); })";
        }

        # Assignment — sv_setsv returns void, wrap in GCC stmt expr
        if ($op eq '=') { return "({ sv_setsv($left, $right); $left; })"; }

        # Regex binding — set $_ to target, then eval_pv
        if ($op eq '=~') {
            my $escaped = $self->_escape_c_string("\$_ =~ $right");
            return "({ sv_setsv(DEFSV, $left); eval_pv(\"$escaped\", TRUE); })";
        }

        # Fallback
        return "NULL /* unsupported op: $op */";
    }

    # Emit unary expression
    method _emit_xs_unary_expr($node, $declared_vars) {
        my $op      = $node->inputs()->[0]->value();
        my $operand = $self->_emit_xs_expr($node->inputs()->[1], $declared_vars);

        if ($op eq '!')   { return "(SvTRUE($operand) ? &PL_sv_no : &PL_sv_yes)"; }
        if ($op eq 'not') { return "(SvTRUE($operand) ? &PL_sv_no : &PL_sv_yes)"; }
        if ($op eq '-')   { return "sv_2mortal(newSVnv(-SvNV($operand)))"; }
        if ($op eq '\\')  { return "newRV_inc($operand)"; }
        if ($op eq '$#')  { return "sv_2mortal(newSViv(av_len((AV*)SvRV($operand))))"; }

        return "NULL /* unsupported unary: $op */";
    }

    # Emit method call using dSP/PUSHMARK/call_method/SPAGAIN stack protocol.
    # Uses GCC statement expression to return the method's scalar result.
    method _emit_xs_method_call_expr($node, $declared_vars) {
        my $invocant_node = $node->inputs()->[0];
        my $method_name   = $node->inputs()->[1]->value();
        my $args          = $node->inputs()->[2];

        # Determine invocant C expression ($self if undef)
        my $invocant_expr;
        if (defined $invocant_node) {
            $invocant_expr = $self->_emit_xs_expr($invocant_node, $declared_vars);
        } else {
            $invocant_expr = 'self';
        }

        my $escaped_name = $self->_escape_c_string($method_name);

        my @stmts;
        push @stmts, 'dSP';
        push @stmts, 'ENTER; SAVETMPS';
        push @stmts, 'PUSHMARK(SP)';
        push @stmts, "XPUSHs($invocant_expr)";
        for my $arg ($args->@*) {
            my $arg_expr = $self->_emit_xs_expr($arg, $declared_vars);
            push @stmts, "XPUSHs($arg_expr)";
        }
        push @stmts, 'PUTBACK';
        push @stmts, "call_method(\"$escaped_name\", G_SCALAR)";
        push @stmts, 'SPAGAIN';
        push @stmts, 'SV *_mcr = SvREFCNT_inc(POPs)';
        push @stmts, 'PUTBACK; FREETMPS; LEAVE';
        push @stmts, '_mcr';

        return '({ ' . join('; ', @stmts) . '; })';
    }

    # Emit subscript access (hash or array)
    method _emit_xs_subscript_expr($node, $declared_vars) {
        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2]->value();

        # Handle broken coderef call IR: SubscriptExpr with undef index
        # comes from $f->($self) where parser loses the argument
        if (!defined $index) {
            my $tgt = defined $target
                ? $self->_emit_xs_expr($target, $declared_vars)
                : 'self';
            return "({ dSP; ENTER; SAVETMPS; PUSHMARK(SP); PUTBACK; "
                 . "call_sv($tgt, G_SCALAR); SPAGAIN; SV *_cr = SvREFCNT_inc(POPs); "
                 . "PUTBACK; FREETMPS; LEAVE; _cr; })";
        }

        my $tgt = defined $target
            ? $self->_emit_xs_expr($target, $declared_vars)
            : 'self';

        if ($style eq 'array') {
            my $idx = $self->_emit_xs_expr($index, $declared_vars);
            return "(*av_fetch((AV*)SvRV($tgt), SvIV($idx), 0))";
        }
        # Hash access
        my $key = $self->_emit_xs_expr($index, $declared_vars);
        return "(*hv_fetch((HV*)SvRV($tgt), SvPV_nolen($key), SvCUR($key), 0))";
    }

    # Emit postfix deref (->@*, ->%*, ->$*)
    method _emit_xs_postfix_deref_expr($node, $declared_vars) {
        my $target = $node->inputs()->[0];
        my $sigil  = $node->inputs()->[1]->value();

        my $tgt = defined $target
            ? $self->_emit_xs_expr($target, $declared_vars)
            : 'self';

        if ($sigil eq '@') { return "(AV*)SvRV($tgt)"; }
        if ($sigil eq '%') { return "(HV*)SvRV($tgt)"; }
        return "SvRV($tgt)";
    }

    # Emit ternary expression
    method _emit_xs_ternary_expr($node, $declared_vars) {
        my $cond  = $self->_emit_xs_expr($node->inputs()->[0], $declared_vars);
        my $true  = $self->_emit_xs_expr($node->inputs()->[1], $declared_vars);
        my $false = $self->_emit_xs_expr($node->inputs()->[2], $declared_vars);

        return "(SvTRUE($cond) ? $true : $false)";
    }

    # Emit hash ref constructor
    method _emit_xs_hash_ref_expr($node, $declared_vars) {
        my $pairs = $node->inputs()->[0];
        if (!$pairs->@*) {
            return "newRV_noinc((SV*)newHV())";
        }
        # TODO: populate hash with pairs via hv_store. Currently only
        # empty hashes are generated correctly — non-empty hashes from
        # fragmented method bodies are structurally incomplete anyway.
        return "newRV_noinc((SV*)newHV()) /* non-empty hash: elements dropped */";
    }

    # Emit array ref constructor
    method _emit_xs_array_ref_expr($node, $declared_vars) {
        my $elements = $node->inputs()->[0];
        if (!$elements->@*) {
            return "newRV_noinc((SV*)newAV())";
        }
        # TODO: populate array with elements via av_push. Currently only
        # empty arrays are generated correctly — non-empty arrays from
        # fragmented method bodies are structurally incomplete anyway.
        return "newRV_noinc((SV*)newAV()) /* non-empty array: elements dropped */";
    }

    # Emit anonymous sub — TODO: capture params and body for full codegen.
    # Currently emits empty sub placeholder since anon subs in Tier C
    # come from fragmented method bodies and lack complete IR.
    method _emit_xs_anon_sub_expr($node, $declared_vars) {
        return "eval_pv(\"sub { }\", TRUE)";
    }

    # Emit regex match via eval_pv, setting $_ to target first.
    # Saves capture variables ($1-$3) into package globals so they
    # persist after eval_pv returns (captures are scoped to eval).
    method _emit_xs_regex_match($node, $declared_vars) {
        my $target  = $node->inputs()->[0];
        my $pattern = $node->inputs()->[1]->value();
        # Wrap match to save captures into package globals before returning
        my $match_perl = '$_ =~ ' . $pattern
            . ' and do { $::_c1=$1; $::_c2=$2; $::_c3=$3; 1 }';
        my $escaped = $self->_escape_c_string($match_perl);
        if (defined $target) {
            my $tgt = $self->_emit_xs_expr($target, $declared_vars);
            return "({ sv_setsv(DEFSV, $tgt); eval_pv(\"$escaped\", TRUE); })";
        }
        return "eval_pv(\"$escaped\", TRUE)";
    }

    # Emit regex substitution via eval_pv, setting $_ to target first
    method _emit_xs_regex_subst($node, $declared_vars) {
        my $target      = $node->inputs()->[0];
        my $pattern     = $node->inputs()->[1]->value();
        my $replacement = $node->inputs()->[2]->value();
        my $flags       = $node->inputs()->[3]->value();

        my $escaped = $self->_escape_c_string("\$_ =~ s/$pattern/$replacement/$flags");
        if (defined $target) {
            my $tgt = $self->_emit_xs_expr($target, $declared_vars);
            return "({ sv_setsv(DEFSV, $tgt); eval_pv(\"$escaped\", TRUE); sv_setsv($tgt, DEFSV); $tgt; })";
        }
        return "eval_pv(\"$escaped\", TRUE)";
    }

    # Emit builtin call as C expression
    method _emit_xs_builtin_call($node, $declared_vars) {
        my $name = $node->inputs()->[0]->value();
        my $args = $node->inputs()->[1];

        # defined() — check SvOK
        if ($name eq 'defined' && $args->@* == 1) {
            my $arg = $self->_emit_xs_expr($args->[0], $declared_vars);
            return "(SvOK($arg) ? &PL_sv_yes : &PL_sv_no)";
        }

        # ref() — check SvROK
        if ($name eq 'ref' && $args->@* == 1) {
            my $arg = $self->_emit_xs_expr($args->[0], $declared_vars);
            return "(SvROK($arg) ? sv_2mortal(newSVpv(sv_reftype(SvRV($arg), TRUE), 0)) : sv_2mortal(newSVpvs(\"\")))";
        }

        # scalar() — for arrays, return count
        if ($name eq 'scalar' && $args->@* == 1) {
            my $arg = $self->_emit_xs_expr($args->[0], $declared_vars);
            return "sv_2mortal(newSViv(av_len((AV*)$arg) + 1))";
        }

        # push — av_push
        if ($name eq 'push' && $args->@* >= 2) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_xs_expr($arr_node, $declared_vars);
            my $val = $self->_emit_xs_expr($args->[1], $declared_vars);
            # PostfixDerefExpr ->@* already returns (AV*)SvRV(...), no need to double-deref
            if ($arr_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $arr_node->class() eq 'PostfixDerefExpr') {
                return "av_push($arr, SvREFCNT_inc($val))";
            }
            return "av_push((AV*)SvRV($arr), SvREFCNT_inc($val))";
        }

        # sprintf, split, join — delegate to eval_pv
        if ($name eq 'sprintf' || $name eq 'split' || $name eq 'join') {
            my $escaped = $self->_escape_c_string("$name()");
            return "eval_pv(\"$escaped\", TRUE)";
        }

        # Fallback
        my $escaped = $self->_escape_c_string("$name()");
        return "eval_pv(\"$escaped\", TRUE)";
    }

    # Emit backtick expression — TODO: extract actual command from IR for
    # full codegen. Currently a placeholder since backtick expressions in
    # Tier C come from Oracle.pm's fragmented method bodies.
    method _emit_xs_backtick_expr($node, $declared_vars) {
        return "eval_pv(\"`cmd`\", TRUE) /* TODO: extract command from IR */";
    }

    # CompoundAssign as expression (e.g., $str .= "foo")
    method _emit_xs_compound_assign_expr($node, $declared_vars) {
        my $op     = $node->inputs()->[0]->value();
        my $target = $node->inputs()->[1];
        my $value  = $node->inputs()->[2];

        my $tgt = $self->_emit_xs_expr($target, $declared_vars);
        my $val = $self->_emit_xs_expr($value, $declared_vars);

        if ($op eq '.=') {
            return "sv_catsv($tgt, $val)";
        }
        if ($op eq '+=') {
            return "sv_setiv($tgt, SvIV($tgt) + SvIV($val))";
        }
        if ($op eq '-=') {
            return "sv_setiv($tgt, SvIV($tgt) - SvIV($val))";
        }

        return "/* $op not supported */";
    }

    # VarDecl as expression (my $x = ...)
    method _emit_xs_var_decl_expr($node, $declared_vars) {
        my $var  = $node->inputs()->[0]->value();
        $var =~ s/^[\$\@\%]//;
        my $init = $node->inputs()->[1];

        if (defined $init) {
            return $self->_emit_xs_expr($init, $declared_vars);
        }
        return '&PL_sv_undef';
    }

    # Emit VarDecl as C statement (SV assignment)
    method _emit_xs_var_decl($node, $declared_vars) {
        my $var  = $node->inputs()->[0]->value();
        $var =~ s/^[\$\@\%]//;
        my $init = $node->inputs()->[1];

        if (defined $init) {
            my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
            return "${var}_sv = $init_expr;";
        }
        return "${var}_sv = &PL_sv_undef;";
    }

    # Emit ReturnStmt as RETVAL assignment.
    # Non-final returns jump to xsreturn: label before OUTPUT section.
    method _emit_xs_return_stmt($node, $declared_vars, $is_last = true) {
        my $value = $node->inputs()->[0];
        my $val_expr = $self->_emit_xs_expr($value, $declared_vars);
        if ($is_last) {
            return "RETVAL = $val_expr;";
        }
        return "RETVAL = $val_expr; goto xsreturn;";
    }

    # Emit DieCall as croak
    method _emit_xs_die_call($node) {
        my $args = $node->inputs()->[0];
        my $msg = '';
        if (ref($args) eq 'ARRAY' && $args->@*) {
            $msg = $self->_escape_c_string($args->[0]->value());
        }
        return "croak(\"%s\", \"$msg\");";
    }

    # Emit IfStmt as C if/else
    method _emit_xs_if_stmt($node, $declared_vars) {
        my $cond      = $node->inputs()->[0];
        my $then_body = $node->inputs()->[1];
        my $else_body = $node->inputs()->[2];

        my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
        my @lines;
        push @lines, "if (SvTRUE($cond_expr)) {";
        for my $stmt ($then_body->@*) {
            # Returns inside if blocks are always early (non-final)
            my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
            push @lines, "    $code" if defined $code;
        }

        if (defined $else_body) {
            if (scalar $else_body->@* == 1
                    && $else_body->[0] isa Chalk::Bootstrap::IR::Node::Constructor
                    && $else_body->[0]->class() eq 'IfStmt') {
                my $elsif = $self->_emit_xs_if_stmt($else_body->[0], $declared_vars);
                $elsif =~ s/^if/} else if/;
                push @lines, $elsif;
                return join("\n", @lines);
            }

            push @lines, "} else {";
            for my $stmt ($else_body->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
                push @lines, "    $code" if defined $code;
            }
        }

        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit ForeachLoop as C for loop over AV, or integer for loop for ranges
    method _emit_xs_foreach_loop($node, $declared_vars) {
        my $iter = $node->inputs()->[0]->value();
        $iter =~ s/^[\$\@\%]//;
        my $list = $node->inputs()->[1];
        my $body = $node->inputs()->[2];

        # Detect range operator (..) and emit optimized integer for loop
        if ($list isa Chalk::Bootstrap::IR::Node::Constructor
                && $list->class() eq 'BinaryExpr'
                && $list->inputs()->[0]->value() eq '..') {
            my $range_left  = $self->_emit_xs_expr($list->inputs()->[1], $declared_vars);
            my $range_right = $self->_emit_xs_expr($list->inputs()->[2], $declared_vars);

            my @lines;
            push @lines, "{";
            push @lines, "    SSize_t _start = SvIV($range_left);";
            push @lines, "    SSize_t _end = SvIV($range_right);";
            push @lines, "    SSize_t _i;";
            push @lines, "    for (_i = _start; _i <= _end; _i++) {";
            push @lines, "        ${iter}_sv = sv_2mortal(newSViv(_i));";
            for my $stmt ($body->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars);
                push @lines, "        $code" if defined $code;
            }
            push @lines, "    }";
            push @lines, "}";
            return join("\n", @lines);
        }

        my $list_expr = $self->_emit_xs_expr($list, $declared_vars);

        my @lines;
        push @lines, "{";
        push @lines, "    AV *av = (AV*)SvRV($list_expr);";
        push @lines, "    SSize_t len = av_len(av) + 1;";
        push @lines, "    SSize_t i;";
        push @lines, "    for (i = 0; i < len; i++) {";
        push @lines, "        SV **elem = av_fetch(av, i, 0);";
        push @lines, "        ${iter}_sv = (elem && *elem) ? *elem : &PL_sv_undef;";
        for my $stmt ($body->@*) {
            my $code = $self->_emit_xs_stmt($stmt, $declared_vars);
            push @lines, "        $code" if defined $code;
        }
        push @lines, "    }";
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit CompoundAssign as statement
    method _emit_xs_compound_assign_stmt($node, $declared_vars) {
        return $self->_emit_xs_compound_assign_expr($node, $declared_vars) . ";";
    }

    # Emit PostfixLoop (e.g., "expr for ...") — TODO: implement as C
    # for loop. Currently a placeholder since postfix loops in Tier C
    # come from fragmented method bodies.
    method _emit_xs_postfix_loop($node, $declared_vars) {
        return "/* TODO: postfix loop not yet implemented */";
    }

    # Emit NextUnless (next unless cond)
    method _emit_xs_next_unless($node, $declared_vars) {
        my $cond = $self->_emit_xs_expr($node->inputs()->[0], $declared_vars);
        return "if (!SvTRUE($cond)) continue;";
    }

    # Emit an XSUB field reader for a FieldDecl with :reader attribute
    method _emit_xs_field_reader($field_decl) {
        my $name_node = $field_decl->inputs()->[0];
        my $attrs     = $field_decl->inputs()->[1];

        # Only emit reader if :reader attribute present
        my $has_reader = false;
        if (ref($attrs) eq 'ARRAY') {
            for my $attr ($attrs->@*) {
                if ($attr->inputs()->[0]->value() eq 'reader') {
                    $has_reader = true;
                    last;
                }
            }
        }
        return [] unless $has_reader;

        my $var_name = $name_node->value();
        $var_name =~ s/^\$//;  # Strip sigil for hash key and method name
        my $escaped_key = $self->_escape_c_string($var_name);

        my @lines;
        push @lines, 'SV *';
        push @lines, "${var_name}(self)";
        push @lines, '    SV *self';
        push @lines, '  CODE:';
        push @lines, '    {';
        push @lines, '        HV *hash = (HV*)SvRV(self);';
        push @lines, "        SV **svp = hv_fetch(hash, \"$escaped_key\", " . bytes::length($var_name) . ", 0);";
        push @lines, '        RETVAL = (svp && *svp) ? SvREFCNT_inc(*svp) : &PL_sv_undef;';
        push @lines, '    }';
        push @lines, '  OUTPUT:';
        push @lines, '    RETVAL';

        return \@lines;
    }

    # Emit an XSUB that returns an InterpolatedString via C string concatenation.
    # Variables are read from the blessed hash via hv_fetch.
    method _emit_xs_interp_return($method_name, $interp_node) {
        my $parts = $interp_node->inputs()->[0];
        my @lines;

        push @lines, 'SV *';
        push @lines, "${method_name}(self)";
        push @lines, '    SV *self';
        push @lines, '  CODE:';
        push @lines, '    {';
        push @lines, '        HV *hash = (HV*)SvRV(self);';

        # Declare SV* variables for each field reference
        my %seen_vars;
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                my $var = $part->value();
                $var =~ s/^\$//;
                next if $seen_vars{$var}++;
                my $escaped = $self->_escape_c_string($var);
                push @lines, "        SV **${var}_svp = hv_fetch(hash, \"$escaped\", " . bytes::length($var) . ", 0);";
            }
        }

        # Build the result SV by concatenation
        my $first = true;
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                my $var = $part->value();
                $var =~ s/^\$//;
                if ($first) {
                    push @lines, "        RETVAL = newSVsv(${var}_svp ? *${var}_svp : &PL_sv_undef);";
                    $first = false;
                } else {
                    push @lines, "        sv_catsv(RETVAL, ${var}_svp ? *${var}_svp : &PL_sv_undef);";
                }
            } else {
                my $lit = $self->_escape_c_string($part->value());
                if ($first) {
                    push @lines, "        RETVAL = newSVpvs(\"$lit\");";
                    $first = false;
                } else {
                    push @lines, "        sv_catpvs(RETVAL, \"$lit\");";
                }
            }
        }

        push @lines, '    }';
        push @lines, '  OUTPUT:';
        push @lines, '    RETVAL';

        return \@lines;
    }

    # Convert an IR default value node to a Perl literal string for PM stub
    method _ir_default_to_perl($node) {
        return undef unless defined $node;

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();
            if ($class eq 'ArrayRefExpr') {
                my $elements = $node->inputs()->[0];
                return '[]' if !$elements->@*;
            }
            if ($class eq 'HashRefExpr') {
                my $pairs = $node->inputs()->[0];
                return '{}' if !$pairs->@*;
            }
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            my $val = $node->value();
            # undef is already Perl's default — skip
            return undef if $val eq 'undef';
            # Numeric literal
            return $val if $val =~ /^-?[0-9]+(?:\.[0-9]+)?$/;
            # String literal
            return "'$val'";
        }

        return undef;
    }

    # Emit the .pm stub using dl_* API for XS loading
    method _emit_pm_stub($ir) {
        my @lines;
        push @lines, "# Generated by Chalk::Bootstrap compiler";
        push @lines, 'use 5.42.0;';
        push @lines, 'use utf8;';
        push @lines, "package $module_name;";
        push @lines, 'use strict;';
        push @lines, 'use warnings;';
        push @lines, 'require DynaLoader;';
        push @lines, '';

        # Use raw dl_* API to bypass XSLoader's @ISA pollution
        # which conflicts with feature class sealed stashes

        # Compute .so path: auto/Foo/Bar/Baz/Baz.so for Foo::Bar::Baz
        my $dir_path = $module_name;
        $dir_path =~ s/::/\//g;
        my $filename = $module_name;
        $filename =~ s/^.*:://;  # Get last component
        my $so_rel_path = "auto/$dir_path/$filename.so";

        my $boot_name = $module_name;
        $boot_name =~ s/::/double_underscore_temp/g;
        $boot_name =~ s/double_underscore_temp/__/g;

        push @lines, '# Search @INC for the .so file';
        push @lines, 'my $so;';
        push @lines, 'for my $dir (@INC) {';
        push @lines, '    next if ref $dir;';
        push @lines, "    my \$path = \"\$dir/$so_rel_path\";";
        push @lines, '    if (-f $path) { $so = $path; last; }';
        push @lines, '}';
        push @lines, 'die "Cannot locate .so file" unless defined $so;';
        push @lines, '';
        push @lines, 'my $libref = DynaLoader::dl_load_file($so, 0)';
        push @lines, '    or die "dl_load_file: " . DynaLoader::dl_error();';
        push @lines, "my \$boot = DynaLoader::dl_find_symbol(\$libref, 'boot_${boot_name}')";
        push @lines, '    or die "dl_find_symbol: " . DynaLoader::dl_error();';
        push @lines, "DynaLoader::dl_install_xsub('${module_name}::_bootstrap', \$boot, \$so);";
        push @lines, "${module_name}->_bootstrap();";
        push @lines, '';
        push @lines, '1;';

        return join("\n", @lines) . "\n";
    }

    # Emit Build.PL
    method _emit_build_pl() {
        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $lib_path = $self->_module_path_prefix();
        return qq[use Module::Build;

Module::Build->new(
    module_name    => '$module_name',
    dist_version   => '0.01',
    dist_abstract  => 'Generated by Chalk::Bootstrap compiler',
    needs_compiler => 1,
    xs_files       => { '$xs_path'
                        => '$lib_path' },
)->create_build_script;
];
    }
}

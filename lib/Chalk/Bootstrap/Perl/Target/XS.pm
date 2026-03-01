# ABOUTME: Walks Perl IR and emits XS/C code using Perl 5.42 feature class API.
# ABOUTME: Generates .xs with BOOT block, .pm dl_* loader stub, and Build.PL.
use 5.42.0;
use utf8;
use experimental 'class';

use bytes ();
use Chalk::Bootstrap::Target;
use Chalk::Bootstrap::Perl::Target::Perl;

class Chalk::Bootstrap::Perl::Target::XS :isa(Chalk::Bootstrap::Target) {
    field $module_name :param :reader;
    field $field_map;  # hashref: field name => index (set during _emit_xs)
    field %_cfg_lookup;  # IR node refaddr → cfg_state entry, built by generate_with_cfg

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

    # Generate XS code with cfg_state-aware dispatch for control flow.
    method generate_with_cfg($ir, $sa, $ctx) {
        die "generate_with_cfg() requires a Constructor:Program IR node"
            unless defined($ir)
            && $ir isa Chalk::Bootstrap::IR::Node::Constructor
            && $ir->class() eq 'Program';

        %_cfg_lookup = ();
        $self->_build_cfg_lookup($sa, $ctx);
        my $code = $self->_emit_xs($ir);
        %_cfg_lookup = ();
        return $code;
    }

    # Generate distribution with cfg_state-aware dispatch.
    method generate_distribution_with_cfg($ir, $sa, $ctx) {
        %_cfg_lookup = ();
        $self->_build_cfg_lookup($sa, $ctx);

        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $pm_path = $self->_module_path_prefix() . '.pm';
        my $result = {
            $xs_path   => $self->_emit_xs($ir),
            $pm_path   => $self->_emit_pm_stub($ir),
            'Build.PL' => $self->_emit_build_pl(),
        };

        %_cfg_lookup = ();
        return $result;
    }

    # First-found wins: parent rules that wire body expressions take priority
    method _build_cfg_lookup($sa, $ctx) {
        my @stack = ($ctx);
        while (@stack) {
            my $node = pop @stack;
            my $state = $sa->cfg_state($node);
            if (defined $state && (defined $state->{if_node} || defined $state->{loop} || defined $state->{try_node})) {
                my $ir_node = $node->extract();
                if (defined $ir_node && ref($ir_node) && !exists $_cfg_lookup{refaddr($ir_node)}) {
                    $_cfg_lookup{refaddr($ir_node)} = $state;
                }
            }
            push @stack, reverse $node->children()->@*;
        }
        return;
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

    # Emit BOOT block for feature class setup using defop-based field initialization.
    # Uses ENTER/LEAVE scoping so SAVEDESTRUCTOR_X handles class sealing automatically.
    # Field attributes (:param, :reader, :writer) are applied via class_apply_field_attributes.
    # Field defaults are set via class_set_field_defop with op_next cleared.
    # Also emits eval_pv fallback calls for methods that can't be compiled to XS.
    method _emit_xs_boot_block($class_decl, $field_map, $fallback_methods = []) {
        my @lines;
        push @lines, 'BOOT:';
        push @lines, '{';

        # Get stash and save PL_curstash
        my $escaped_module = $self->_escape_c_string($module_name);
        push @lines, "    HV *stash = gv_stashpv(\"$escaped_module\", GV_ADD);";
        push @lines, '    HV *old_stash = PL_curstash;';
        push @lines, '    PL_curstash = stash;';
        push @lines, '';

        # Outer ENTER — SAVEDESTRUCTOR_X registered by class_setup_stash
        # will call class_seal_stash when this scope exits via LEAVE
        push @lines, '    ENTER;';
        push @lines, '';

        # 1. Create class (registers SAVEDESTRUCTOR_X for seal)
        push @lines, '    Perl_class_setup_stash(aTHX_ stash);';
        push @lines, '';

        # 2. Apply :isa inheritance if parent class exists
        my $parent = $class_decl->inputs()->[1];
        if (defined $parent) {
            my $parent_name = $parent->value();
            my $isa_attr = "isa($parent_name)";
            my $escaped_attr = $self->_escape_c_string($isa_attr);
            push @lines, '    {';
            push @lines, "        OP *attr = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped_attr\"));";
            push @lines, '        OP *list = newLISTOP(OP_LIST, 0, attr, NULL);';
            push @lines, '        Perl_class_apply_attributes(aTHX_ stash, list);';
            push @lines, '    }';
            push @lines, '';
        }

        # 3. Register fields with attributes and defaults via C API
        my $body = $class_decl->inputs()->[2];
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor
                     && $item->class() eq 'FieldDecl';

            my $name_node = $item->inputs()->[0];
            my $attrs = $item->inputs()->[1];
            my $default = $item->inputs()->[2];
            my $field_name = $name_node->value();  # Includes sigil
            my $escaped = $self->_escape_c_string($field_name);

            push @lines, '    {';
            push @lines, '        ENTER;';
            push @lines, '        Perl_class_prepare_initfield_parse(aTHX);';
            push @lines, "        PADOFFSET padix = pad_add_name_pvs(\"$escaped\", padadd_FIELD, NULL, NULL);";
            push @lines, '        PADNAME *pn = PadnamelistARRAY(PadlistNAMES(CvPADLIST(PL_compcv)))[padix];';

            # Apply field attributes (:param, :reader, :writer)
            if (ref($attrs) eq 'ARRAY') {
                for my $attr ($attrs->@*) {
                    my $attr_name = $attr->inputs()->[0]->value();
                    my $escaped_attr = $self->_escape_c_string($attr_name);
                    push @lines, '        {';
                    push @lines, "            OP *attr = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped_attr\"));";
                    push @lines, '            Perl_class_apply_field_attributes(aTHX_ pn, attr);';
                    push @lines, '        }';
                }
            }

            # Set default value via defop
            if (defined $default) {
                push @lines, $self->_emit_defop($default);
            }

            push @lines, '        LEAVE;';
            push @lines, '    }';
        }
        push @lines, '';

        # Outer LEAVE triggers SAVEDESTRUCTOR_X which calls class_seal_stash
        push @lines, '    LEAVE;';
        push @lines, '';

        # Emit eval_pv fallback for unsupported methods
        if ($fallback_methods->@*) {
            push @lines, '    /* eval_pv fallback for unsupported methods */';
            for my $method ($fallback_methods->@*) {
                push @lines, $self->_emit_xs_eval_fallback($method);
            }
            push @lines, '';
        }

        # Restore PL_curstash
        push @lines, '    PL_curstash = old_stash;';
        push @lines, '}';

        return \@lines;
    }

    # Emit C code for a field default op (defop) to be set via class_set_field_defop.
    # Returns array of C lines with proper indentation for the BOOT block context.
    method _emit_defop($default) {
        my @lines;
        push @lines, '        {';

        if ($default isa Chalk::Bootstrap::IR::Node::Constant) {
            my $val = $default->value();
            if ($val eq 'undef') {
                # Explicit undef default — still need defop for :param to mark as optional
                push @lines, '            OP *defop = newSVOP(OP_CONST, 0, &PL_sv_undef);';
            } elsif ($val =~ /^-?\d+$/) {
                push @lines, "            OP *defop = newSVOP(OP_CONST, 0, newSViv($val));";
            } elsif ($val =~ /^-?\d+\.\d+$/) {
                push @lines, "            OP *defop = newSVOP(OP_CONST, 0, newSVnv($val));";
            } else {
                my $escaped = $self->_escape_c_string($val);
                push @lines, "            OP *defop = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped\"));";
            }
        } elsif ($default isa Chalk::Bootstrap::IR::Node::Constructor
                && $default->class() eq 'ArrayRefExpr') {
            push @lines, '            OP *defop = newANONLIST(NULL);';
        } elsif ($default isa Chalk::Bootstrap::IR::Node::Constructor
                && $default->class() eq 'HashRefExpr') {
            push @lines, '            OP *defop = newANONHASH(NULL);';
        } else {
            # Unknown default type — skip defop
            return;
        }

        push @lines, '            defop->op_next = NULL;';
        push @lines, '            Perl_class_set_field_defop(aTHX_ pn, 0, defop);';
        push @lines, '        }';

        return @lines;
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

    # Check if a method's XS output contains unsupported constructs
    # that require eval_pv fallback instead of XSUB emission.
    method _needs_eval_fallback($xs_output) {
        return $xs_output =~ /NULL \/\* unsupported \*\// || $xs_output =~ /\/\* unknown node \*\//;
    }

    # Emit eval_pv fallback for a method that can't be compiled to XS.
    # Returns a single eval_pv() call that defines the method as a Perl sub.
    # For now, emits a stub that dies - full Perl code generation comes later.
    method _emit_xs_eval_fallback($method_decl) {
        my $name = $method_decl->inputs()->[0]->value();
        my $params = $method_decl->inputs()->[1];

        # Build parameter list for Perl sub signature
        my @param_names;
        for my $p ($params->@*) {
            my $pname = $p->value();
            push @param_names, $pname;
        }

        # Generate Perl sub stub that indicates it needs implementation
        my $param_list = join(', ', '$self', @param_names);
        my $perl_code = "sub ${module_name}::${name} { my ($param_list) = \@_; die 'eval_pv fallback not yet implemented for $name' }";
        my $escaped = $self->_escape_c_string($perl_code);

        return "    eval_pv(\"$escaped\", TRUE);";
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
        push @lines, 'extern void Perl_class_prepare_initfield_parse(pTHX);';
        push @lines, 'extern void Perl_class_set_field_defop(pTHX_ PADNAME *pn, int defmode, OP *defop);';
        push @lines, 'extern void Perl_class_apply_attributes(pTHX_ HV *stash, OP *attrlist);';
        push @lines, 'extern void Perl_class_apply_field_attributes(pTHX_ PADNAME *pn, OP *attrlist);';
        push @lines, '';

        push @lines, "MODULE = $module_name  PACKAGE = $module_name";
        push @lines, '';

        my @fallback_methods;  # Collect methods needing eval_pv fallback

        if (defined $class_decl) {
            # Build field map once and store it for use throughout code generation
            $field_map = $self->_build_field_index_map($class_decl);

            # Field readers/writers are auto-generated by seal_stash via :reader/:writer
            # attributes applied in the BOOT block — no need for XSUB readers/writers.

            my $body = $class_decl->inputs()->[2];
            for my $item ($body->@*) {
                if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                        && $item->class() eq 'MethodDecl') {
                    # Try to emit as XSUB
                    my $method_lines = $self->_emit_xs_method($item);
                    my $xs_output = join("\n", $method_lines->@*);

                    # Check if XSUB contains unsupported constructs
                    if ($self->_needs_eval_fallback($xs_output)) {
                        # Collect for eval_pv fallback in BOOT block
                        push @fallback_methods, $item;
                    } else {
                        # Emit as XSUB
                        push @lines, $method_lines->@*;
                        push @lines, '';
                    }
                }
            }

            # Emit BOOT block after XSUBs (includes eval_pv fallbacks)
            push @lines, $self->_emit_xs_boot_block($class_decl, $field_map, \@fallback_methods)->@*;
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

        # Detect early returns (ReturnStmt inside If CFG node or non-final position)
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

    # Check if a body contains early returns (ReturnStmt inside if body)
    method _has_early_return($nodes) {
        for my $item ($nodes->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node;
            # Check CFG If nodes via cfg_lookup
            if (%_cfg_lookup && ref($item)) {
                my $state = $_cfg_lookup{refaddr($item)};
                if (defined $state && defined $state->{if_node}) {
                    my $then = $state->{then_stmts};
                    return true if $self->_body_contains_return($then);
                    my $else = $state->{else_stmts};
                    return true if defined($else) && ref($else) eq 'ARRAY'
                        && $self->_body_contains_return($else);
                }
            }
        }
        return false;
    }

    # Check if a body array contains any ReturnStmt
    method _body_contains_return($body) {
        return false unless ref($body) eq 'ARRAY';
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node;
            # Check CFG If nodes via cfg_lookup
            if (%_cfg_lookup && ref($item)) {
                my $state = $_cfg_lookup{refaddr($item)};
                if (defined $state && defined $state->{if_node}) {
                    my $then = $state->{then_stmts};
                    return true if $self->_body_contains_return($then);
                    my $else = $state->{else_stmts};
                    return true if defined($else) && $self->_body_contains_return($else);
                }
            }
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            return true if $item->class() eq 'ReturnStmt';
        }
        return false;
    }

    # Recursively collect VarDecl and iterator names from IR nodes at any
    # nesting depth, so PREINIT has all needed declarations. Handles both
    # legacy Constructor types and CFG nodes via cfg_lookup.
    method _collect_var_decls($nodes, $declared_vars) {
        for my $item ($nodes->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node;

            # Check if this is a CFG node with associated cfg_state
            if (%_cfg_lookup && ref($item)) {
                my $state = $_cfg_lookup{refaddr($item)};
                if (defined $state) {
                    if (defined $state->{if_node}) {
                        # Recurse into if/else bodies
                        my $then = $state->{then_stmts};
                        $self->_collect_var_decls($then, $declared_vars) if ref($then) eq 'ARRAY';
                        my $else = $state->{else_stmts};
                        $self->_collect_var_decls($else, $declared_vars) if defined($else) && ref($else) eq 'ARRAY';
                    }
                    if (defined $state->{loop}) {
                        # Iterator variable
                        my $iter = $state->{iterator};
                        if (defined $iter && $iter isa Chalk::Bootstrap::IR::Node::Constant) {
                            my $iter_name = $iter->value();
                            $iter_name =~ s/^[\$\@\%]//;
                            $declared_vars->{$iter_name} = true;
                        }
                        # Recurse into loop body
                        my $body = $state->{body_stmts};
                        $self->_collect_var_decls($body, $declared_vars) if ref($body) eq 'ARRAY';
                    }
                    next;
                }
            }

            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            my $class = $item->class();

            if ($class eq 'VarDecl') {
                my $var = $item->inputs()->[0]->value();
                $var =~ s/^[\$\@\%]//;
                $declared_vars->{$var} = true;
            }
        }
    }

    # Emit a single IR node as a C statement line.
    # $is_last indicates whether this is the final statement in the method body.
    method _emit_xs_stmt($node, $declared_vars, $is_last = true) {
        return undef unless defined $node;

        # Check cfg_state lookup for control flow dispatch
        if (%_cfg_lookup && ref($node)) {
            my $state = $_cfg_lookup{refaddr($node)};
            if (defined $state) {
                if (defined $state->{if_node}) {
                    # loop_jump: emit 'if (!cond) continue;' instead of block
                    if (defined $state->{loop_jump}) {
                        return $self->_emit_xs_loop_jump(
                            $state->{loop_jump},
                            $state->{if_node},
                            $declared_vars,
                        );
                    }
                    return $self->emit_cfg_if(
                        $state->{if_node},
                        $state->{true_proj},
                        $state->{false_proj},
                        $declared_vars,
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
                        $declared_vars,
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
                        $declared_vars,
                    );
                }
            }
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
            my $class = $node->class();

            if ($class eq 'VarDecl')         { return $self->_emit_xs_var_decl($node, $declared_vars); }
            if ($class eq 'ReturnStmt')      { return $self->_emit_xs_return_stmt($node, $declared_vars, $is_last); }
            if ($class eq 'DieCall')         { return $self->_emit_xs_die_call($node); }
            if ($class eq 'CompoundAssign')  { return $self->_emit_xs_compound_assign_stmt($node, $declared_vars); }

            # Expression types used as statements (side effects)
            return $self->_emit_xs_expr($node, $declared_vars) . ";";
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            # Loop control keywords: next→continue, last→break in C
            my $val = $node->value() // '';
            if ($val eq 'next') { return "continue;"; }
            if ($val eq 'last') { return "break;"; }
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

            # ReturnStmt used as expression: stale-value merge artifact from Earley parser.
            # Unwrap and emit the inner value as an expression.
            if ($class eq 'ReturnStmt') {
                my $inner = $node->inputs()->[0];
                return $self->_emit_xs_expr($inner, $declared_vars);
            }
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
            # Field access: use ObjectFIELDS indexed access if this is a field
            if ($field_map && exists $field_map->{$var}) {
                my $idx = $field_map->{$var};
                return "ObjectFIELDS(SvRV(self))[$idx]";
            }
            # Package global or unknown variable — use old hv_fetch pattern
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
    # (local C vars) or ObjectFIELDS (field access).
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
                } elsif ($field_map && exists $field_map->{$var}) {
                    my $idx = $field_map->{$var};
                    $src = "ObjectFIELDS(SvRV(self))[$idx]";
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
        # Populate hash with key/value pairs via hv_store
        my @stores;
        for (my $i = 0; $i < $pairs->@*; $i += 2) {
            my $key = $self->_emit_xs_expr($pairs->[$i], $declared_vars);
            my $val = $self->_emit_xs_expr($pairs->[$i + 1], $declared_vars);
            push @stores, "hv_store(_hv, SvPV_nolen($key), SvCUR($key), SvREFCNT_inc($val), 0)";
        }
        return "({ HV *_hv = newHV(); " . join("; ", @stores) . "; newRV_noinc((SV*)_hv); })";
    }

    # Emit array ref constructor
    method _emit_xs_array_ref_expr($node, $declared_vars) {
        my $elements = $node->inputs()->[0];
        if (!$elements->@*) {
            return "newRV_noinc((SV*)newAV())";
        }
        # Populate array with elements via av_push
        my @pushes;
        for my $elem ($elements->@*) {
            my $val = $self->_emit_xs_expr($elem, $declared_vars);
            push @pushes, "av_push(_av, SvREFCNT_inc($val))";
        }
        return "({ AV *_av = newAV(); " . join("; ", @pushes) . "; newRV_noinc((SV*)_av); })";
    }

    # Emit anonymous sub via eval_pv with real params and body.
    # Uses the Perl target to generate the source, then wraps in eval_pv.
    method _emit_xs_anon_sub_expr($node, $declared_vars) {
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $perl_src = $perl_target->_emit_anon_sub_expr($node);
        my $escaped = $self->_escape_c_string($perl_src);
        return "eval_pv(\"$escaped\", TRUE)";
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

        # push — av_push wrapped in statement expression (av_push returns void)
        if ($name eq 'push' && $args->@* >= 2) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_xs_expr($arr_node, $declared_vars);
            my $val = $self->_emit_xs_expr($args->[1], $declared_vars);
            # PostfixDerefExpr ->@* already returns (AV*)SvRV(...), no need to double-deref
            my $av_expr;
            if ($arr_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $arr_node->class() eq 'PostfixDerefExpr') {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            return "({ av_push($av_expr, SvREFCNT_inc($val)); $arr; })";
        }

        # sprintf — native C via Perl_sv_setpvf
        if ($name eq 'sprintf' && $args->@* >= 1) {
            my $fmt = $self->_emit_xs_expr($args->[0], $declared_vars);
            my @c_args = map { $self->_emit_xs_expr($_, $declared_vars) } $args->@[1 .. $#$args];
            my $args_str = join(', ', $fmt, map { "SvPV_nolen($_)" } @c_args);
            return "({ SV *_sv = sv_2mortal(newSVpvs(\"\")); Perl_sv_setpvf(aTHX_ _sv, SvPV_nolen($fmt)" .
                (@c_args ? ", " . join(", ", map { "SvPV_nolen($_)" } @c_args) : "") .
                "); _sv; })";
        }

        # join — native C via sv_catsv loop
        if ($name eq 'join' && $args->@* >= 2) {
            my $sep = $self->_emit_xs_expr($args->[0], $declared_vars);
            my $arr = $self->_emit_xs_expr($args->[1], $declared_vars);
            return "({ SV *_result = sv_2mortal(newSVpvs(\"\")); " .
                "AV *_items = (AV*)SvRV($arr); " .
                "I32 _len = av_len(_items); " .
                "I32 _i; " .
                "for (_i = 0; _i <= _len; _i++) { " .
                "if (_i > 0) sv_catsv(_result, $sep); " .
                "sv_catsv(_result, *av_fetch(_items, _i, 0)); " .
                "} _result; })";
        }

        # split — eval_pv with actual args from IR
        if ($name eq 'split' && $args->@* >= 2) {
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my @arg_strs = map { $perl_target->_emit_expr($_) } $args->@*;
            my $perl_call = "split(" . join(', ', @arg_strs) . ")";
            my $escaped = $self->_escape_c_string($perl_call);
            return "eval_pv(\"$escaped\", TRUE)";
        }

        # Fallback
        my $escaped = $self->_escape_c_string("$name()");
        return "eval_pv(\"$escaped\", TRUE)";
    }

    # Emit backtick expression via eval_pv with actual command from IR
    method _emit_xs_backtick_expr($node, $declared_vars) {
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $cmd = $perl_target->_emit_expr($node->inputs()->[0]);
        my $escaped = $self->_escape_c_string("`$cmd`");
        return "eval_pv(\"$escaped\", TRUE)";
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
        if ($op eq '//=') {
            return "({ if (!SvOK($tgt)) sv_setsv($tgt, $val); $tgt; })";
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
    # Strips sv_2mortal() from the value expression since XS's OUTPUT
    # section applies sv_2mortal to ST(0) automatically. Double-mortal
    # causes "attempt to copy freed scalar" panics.
    method _emit_xs_return_stmt($node, $declared_vars, $is_last = true) {
        my $value = $node->inputs()->[0];
        my $val_expr = $self->_emit_xs_expr($value, $declared_vars);
        $val_expr =~ s/^sv_2mortal\((.+)\)$/$1/;
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

    # Emit CompoundAssign as statement
    method _emit_xs_compound_assign_stmt($node, $declared_vars) {
        return $self->_emit_xs_compound_assign_expr($node, $declared_vars) . ";";
    }

    # Emit C continue/break from an If CFG node with loop_jump marker.
    # The If node's condition is already the correct test (negated for unless).
    # 'next' maps to C 'continue', 'last' maps to C 'break'.
    method _emit_xs_loop_jump($jump_keyword, $if_node, $declared_vars) {
        my $cond = $if_node->inputs()->[1];
        my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
        my $c_keyword = $jump_keyword eq 'last' ? 'break' : 'continue';
        return "if (SvTRUE($cond_expr)) $c_keyword;";
    }

    # Emit C if/else from an If CFG node with true/false Proj branches.
    # The If node's condition is emitted as a SvTRUE test. Body statements
    # for each branch are provided by the caller as arrayrefs.
    # $true_proj/$false_proj: retained for future GCM/peephole passes
    # that schedule data-flow nodes relative to Proj control anchors.
    method emit_cfg_if($if_node, $true_proj, $false_proj, $declared_vars,
                       $true_stmts = [], $false_stmts = [],
                       $prefix = 'if') {
        my $cond = $if_node->inputs()->[1];  # condition input
        my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);

        my @lines;
        push @lines, "$prefix (SvTRUE($cond_expr)) {";
        for my $stmt ($true_stmts->@*) {
            my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
            push @lines, "    $code" if defined $code;
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
                        $declared_vars,
                        $elsif_state->{then_stmts} // [],
                        $elsif_state->{else_stmts} // [],
                        '} else if',
                    );
                    push @lines, $elsif_code;
                    return join("\n", @lines);
                }
            }
            push @lines, "} else {";
            for my $stmt ($false_stmts->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
                push @lines, "    $code" if defined $code;
            }
        }
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit C if/else with Phi variable declaration.
    # Phi(Region, val_a, val_b) becomes a C variable declared before the if,
    # assigned in each branch.
    method emit_cfg_phi_if($if_node, $phi, $declared_vars) {
        my $cond = $if_node->inputs()->[1];
        my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);

        my $region = $phi->inputs()->[0];
        my $values = $phi->inputs()->[1];  # arrayref of [val_a, val_b]
        my $val_a_expr = $self->_emit_xs_expr($values->[0], $declared_vars);
        my $val_b_expr = $self->_emit_xs_expr($values->[1], $declared_vars);

        # Generate a unique variable name from the Phi node ID
        my $phi_var = '_phi_' . $phi->id();

        my @lines;
        push @lines, "SV *$phi_var;";
        push @lines, "if (SvTRUE($cond_expr)) {";
        push @lines, "    $phi_var = sv_2mortal($val_a_expr);";
        push @lines, "} else {";
        push @lines, "    $phi_var = sv_2mortal($val_b_expr);";
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit C loop from a Loop CFG node.
    # Loop → If → Proj(body) / Proj(exit) structure becomes a while loop.
    # $loop/$body_proj/$exit_proj: retained for future GCM/peephole passes.
    method emit_cfg_loop($loop, $loop_if, $body_proj, $exit_proj, $declared_vars,
                         $body_stmts = [], $iterator = undef, $list = undef) {
        my @lines;

        if (defined $iterator && defined $list) {
            # Foreach: emit C-style AV iteration
            my $iter_name = $iterator->value();
            $iter_name =~ s/^[\$\@\%]//;

            if (ref($list) eq 'ARRAY') {
                # Literal list: build temp AV, iterate with av_fetch
                # Mortalize AV so it is cleaned up on croak/exception
                push @lines, "{";
                push @lines, "    AV *_tmp_av = (AV*)sv_2mortal((SV*)newAV());";
                for my $item ($list->@*) {
                    my $val = $self->_emit_xs_expr($item, $declared_vars);
                    push @lines, "    av_push(_tmp_av, SvREFCNT_inc($val));";
                }
                push @lines, "    SSize_t _len = av_len(_tmp_av) + 1;";
                push @lines, "    SSize_t _i;";
                push @lines, "    for (_i = 0; _i < _len; _i++) {";
                push @lines, "        SV **_elem = av_fetch(_tmp_av, _i, 0);";
                push @lines, "        SV *${iter_name}_sv = (_elem && *_elem) ? *_elem : &PL_sv_undef;";
            } else {
                # Variable list: iterate existing AV
                my $list_expr = $self->_emit_xs_expr($list, $declared_vars);
                push @lines, "{";
                push @lines, "    SV *_list_sv = $list_expr;";
                push @lines, "    if (!SvROK(_list_sv)) croak(\"Not an ARRAY reference\");";
                push @lines, "    AV *_av = (AV*)SvRV(_list_sv);";
                push @lines, "    SSize_t _len = av_len(_av) + 1;";
                push @lines, "    SSize_t _i;";
                push @lines, "    for (_i = 0; _i < _len; _i++) {";
                push @lines, "        SV **_elem = av_fetch(_av, _i, 0);";
                push @lines, "        SV *${iter_name}_sv = (_elem && *_elem) ? *_elem : &PL_sv_undef;";
            }

            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
                push @lines, "        $code" if defined $code;
            }
            push @lines, "    }";
            # No explicit SvREFCNT_dec needed — sv_2mortal handles cleanup
            push @lines, "}";
        } else {
            # While loop: while (cond) { ... }
            my $cond = $loop_if->inputs()->[1];
            my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
            push @lines, "while (SvTRUE($cond_expr)) {";

            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
                push @lines, "    $code" if defined $code;
            }
            push @lines, "}";
        }

        return join("\n", @lines);
    }

    # Emit an XSUB that returns an InterpolatedString via C string concatenation.
    # Variables are read from ObjectFIELDS for field access.
    method _emit_xs_interp_return($method_name, $interp_node) {
        my $parts = $interp_node->inputs()->[0];
        my @lines;

        push @lines, 'SV *';
        push @lines, "${method_name}(self)";
        push @lines, '    SV *self';
        push @lines, '  CODE:';

        # Build the result SV by concatenation
        my $first = true;
        for my $part ($parts->@*) {
            if ($part->const_type() eq 'variable') {
                my $var = $part->value();
                $var =~ s/^\$//;
                my $src;
                if ($field_map && exists $field_map->{$var}) {
                    my $idx = $field_map->{$var};
                    $src = "ObjectFIELDS(SvRV(self))[$idx]";
                } else {
                    # Fallback for non-field variables (shouldn't happen in simple cases)
                    my $escaped = $self->_escape_c_string($var);
                    $src = "get_sv(\"${module_name}::$escaped\", GV_ADD)";
                }
                if ($first) {
                    push @lines, "    RETVAL = newSVsv($src);";
                    $first = false;
                } else {
                    push @lines, "    sv_catsv(RETVAL, $src);";
                }
            } else {
                my $lit = $self->_escape_c_string($part->value());
                if ($first) {
                    push @lines, "    RETVAL = newSVpvs(\"$lit\");";
                    $first = false;
                } else {
                    push @lines, "    sv_catpvs(RETVAL, \"$lit\");";
                }
            }
        }

        push @lines, '  OUTPUT:';
        push @lines, '    RETVAL';

        return \@lines;
    }

    # Emit C try/catch using JMPENV_PUSH/POP (setjmp/longjmp).
    # try body runs when ret == 0, catch body runs when ret != 0.
    # The catch variable is bound to ERRSV (Perl's $@).
    method emit_cfg_try_catch($try_stmts, $catch_var, $catch_stmts, $declared_vars) {
        my @lines;
        push @lines, "{";
        push @lines, "    dJMPENV;";
        push @lines, "    int ret;";
        push @lines, "    JMPENV_PUSH(ret);";
        push @lines, "    if (ret == 0) {";
        for my $stmt ($try_stmts->@*) {
            my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
            push @lines, "        $code" if defined $code;
        }
        push @lines, "        JMPENV_POP;";
        push @lines, "    }";
        push @lines, "    if (ret != 0) {";
        push @lines, "        JMPENV_POP;";
        # Bind catch variable to ERRSV
        my $var_name = $catch_var;
        $var_name =~ s/^\$//;
        push @lines, "        SV *${var_name} = ERRSV;";
        for my $stmt ($catch_stmts->@*) {
            my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
            push @lines, "        $code" if defined $code;
        }
        push @lines, "    }";
        push @lines, "}";
        return join("\n", @lines);
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

    # Emit C code from a cfg_state entry.
    # Dispatches to emit_cfg_if or emit_cfg_loop based on which CFG node
    # references are present in the state.
    # Returns undef if the state has no control flow structure to emit.
    method emit_from_cfg_state($sa, $ctx, $declared_vars) {
        my $state = $sa->cfg_state($ctx);
        return unless defined $state;

        # If/else: cfg_state has if_node
        if (defined $state->{if_node}) {
            return $self->emit_cfg_if(
                $state->{if_node},
                $state->{true_proj},
                $state->{false_proj},
                $declared_vars,
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
                $declared_vars,
                $state->{body_stmts} // [],
                $state->{iterator},
                $state->{list},
            );
        }

        # Try/catch: emit JMPENV_PUSH/POP C code
        if (defined $state->{try_node}) {
            return $self->emit_cfg_try_catch(
                $state->{try_stmts}   // [],
                $state->{catch_var},
                $state->{catch_stmts} // [],
                $declared_vars,
            );
        }

        return;
    }
}

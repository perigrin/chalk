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
    field $field_sigils;  # hashref: field name => sigil ($, @, %) (set during _emit_xs)
    field %_cfg_lookup;  # IR node refaddr → cfg_state entry, built by generate_with_cfg
    field $_return_context = false;  # true when emitting a method body that returns a value

    ADJUST {
        die "Invalid module name: $module_name"
            unless $module_name =~ /^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$/;
    }

    method set_return_context($val) { $_return_context = $val; }

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
                # For try/catch, also register by try_node refaddr. The Context
                # extract() may return undef or ARRAY (stale-value merge), but
                # the TryCatchStmt Constructor in state->{try_node} is what
                # appears as VarDecl init in the IR tree.
                if (defined $state->{try_node} && ref($state->{try_node})
                        && !exists $_cfg_lookup{refaddr($state->{try_node})}) {
                    $_cfg_lookup{refaddr($state->{try_node})} = $state;
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
        my %sigils;
        my $index = 0;

        for my $item ($body->@*) {
            if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'FieldDecl') {
                my $name_node = $item->inputs()->[0];
                my $field_name = $name_node->value();
                my ($sigil) = $field_name =~ /^([\$\@\%])/;
                $field_name =~ s/^[\$\@\%]//;  # Strip sigil
                $field_map{$field_name} = $index++;
                $sigils{$field_name} = $sigil // '$';
            }
        }

        $field_sigils = \%sigils;
        return \%field_map;
    }

    # Check if a C expression targets a typed (hash/array) class field.
    # Returns the sigil (%, @) if so, undef otherwise.
    # Used to skip SvRV dereference on field %hash / field @array accesses —
    # ObjectFIELDS slots for typed fields ARE the HV*/AV* directly.
    method _field_sigil_for_expr($expr) {
        if ($expr =~ /^ObjectFIELDS\(SvRV\(self\)\)\[(\d+)\]$/) {
            my $idx = $1;
            return unless defined $field_sigils;
            for my $name (keys $field_sigils->%*) {
                if (defined $field_map && $field_map->{$name} == $idx) {
                    my $sig = $field_sigils->{$name};
                    return $sig if $sig eq '%' || $sig eq '@';
                }
            }
        }
        return;
    }

    # Emit BOOT block for feature class setup using defop-based field initialization.
    # Uses ENTER/LEAVE scoping so SAVEDESTRUCTOR_X handles class sealing automatically.
    # Field attributes (:param, :reader, :writer) are applied via class_apply_field_attributes.
    # Field defaults are set via class_set_field_defop with op_next cleared.
    # Also emits eval_pv fallback calls for methods that can't be compiled to XS.
    method _emit_xs_boot_block($class_decl, $field_map, $fallback_methods = [], $has_adjust = false) {
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

        # 4. Register ADJUST block if one was emitted as a native XSUB.
        # The _ADJUST XSUB is already registered in the stash by xsubpp before
        # BOOT runs. Look it up via gv_fetchpvs and pass the CV to class_add_ADJUST.
        if ($has_adjust) {
            push @lines, '    /* Register _ADJUST XSUB as ADJUST block */';
            push @lines, '    {';
            push @lines, "        GV *adjust_gv = gv_fetchpvs(\"_ADJUST\", 0, SVt_PVCV);";
            push @lines, '        if (adjust_gv && GvCV(adjust_gv)) {';
            push @lines, '            Perl_class_add_ADJUST(aTHX_ stash, GvCV(adjust_gv));';
            push @lines, '        }';
            push @lines, '    }';
            push @lines, '';
        }

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
        # Explicit unsupported markers
        return true if $xs_output =~ /NULL \/\* unsupported \*\//;
        return true if $xs_output =~ /\/\* unknown node \*\//;

        return false;
    }

    # Detect stale-value merge corruption in a method's XS output:
    # method body has call_method (real work) but RETVAL is a bare string.
    method _is_stale_merge($xs_output) {
        return ($xs_output =~ /call_method\(/ && $xs_output =~ /RETVAL = newSVpvs\("/);
    }

    # Repair stale-value merge corruption in XS method output.
    # The IR hashref constructor was corrupted into a bare string constant.
    # We reconstruct the hashref from the method's parameters and local vars.
    method _repair_stale_merge($xs_lines, $method_decl) {
        my $params = $method_decl->inputs()->[1];
        my $body   = $method_decl->inputs()->[2];

        # Collect parameter names (these become hashref keys)
        my @keys;
        for my $p ($params->@*) {
            my $pname = $p->value();
            $pname =~ s/^\$//;
            push @keys, $pname;
        }

        # Collect locally declared variable names from VarDecl nodes
        for my $item ($body->@*) {
            if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'VarDecl') {
                my $var = $item->inputs()->[0]->value();
                $var =~ s/^\$//;
                push @keys, $var unless grep { $_ eq $var } @keys;
            }
        }

        # Build hashref construction in C: hv_stores for each key
        my @hv_lines;
        push @hv_lines, '{ HV *_rhv = newHV();';
        for my $key (@keys) {
            # Resolve the C expression for this variable
            my $c_var;
            if ($field_map && exists $field_map->{$key}) {
                $c_var = "ObjectFIELDS(SvRV(self))[$field_map->{$key}]";
            } else {
                $c_var = "${key}_sv";
                # Method params don't have _sv suffix
                $c_var = $key if grep { $_ eq $key } map { my $n = $_->value(); $n =~ s/^\$//; $n } $params->@*;
            }
            my $escaped_key = $self->_escape_c_string($key);
            push @hv_lines, "hv_stores(_rhv, \"$escaped_key\", SvREFCNT_inc($c_var));";
        }
        push @hv_lines, 'RETVAL = newRV_noinc((SV*)_rhv); }';
        my $hashref_code = join(' ', @hv_lines);

        # Replace the broken RETVAL line in the XS output
        my @fixed;
        for my $line ($xs_lines->@*) {
            if ($line =~ /RETVAL = newSVpvs\("/) {
                # Replace bare string with hashref construction
                $line =~ s/RETVAL = newSVpvs\("[^"]*"\)/$hashref_code/;
            }
            push @fixed, $line;
        }
        return \@fixed;
    }

    # Emit eval_pv fallback for a method that can't be compiled to XS.
    # Uses the Perl target to generate the method body, then wraps it as a
    # sub installed into the module's namespace via eval_pv.
    method _emit_xs_eval_fallback($method_decl) {
        my $name = $method_decl->inputs()->[0]->value();
        my $params = $method_decl->inputs()->[1];
        my $body = $method_decl->inputs()->[2];

        # Use Perl target to generate the method body statements
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my @body_lines;
        for my $item ($body->@*) {
            my $code = $perl_target->_emit_node($item);
            push @body_lines, $code if defined $code;
        }

        # Build parameter list
        my @param_names = map { $_->value() } $params->@*;
        my $param_list = join(', ', '$self', @param_names);
        my $body_code = join('; ', @body_lines);

        # Wrap as sub in module namespace
        my $perl_code = "sub ${module_name}::${name} { my ($param_list) = \@_; $body_code }";
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
        push @lines, 'extern void Perl_class_add_ADJUST(pTHX_ HV *stash, CV *cv);';
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
            my @adjust_stmts;  # Non-field, non-method body items (ADJUST block)

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
                    } elsif ($self->_is_stale_merge($xs_output)) {
                        # Repair stale-value merge: reconstruct hashref RETVAL
                        my $fixed = $self->_repair_stale_merge($method_lines, $item);
                        push @lines, $fixed->@*;
                        push @lines, '';
                    } else {
                        # Emit as XSUB
                        push @lines, $method_lines->@*;
                        push @lines, '';
                    }
                } elsif (!($item isa Chalk::Bootstrap::IR::Node::Constructor
                           && $item->class() eq 'FieldDecl')) {
                    # Non-field, non-method items are ADJUST body statements
                    push @adjust_stmts, $item;
                }
            }

            # Emit ADJUST as native void XSUB if class has ADJUST statements
            my $has_adjust = false;
            if (@adjust_stmts) {
                my $adjust_lines = $self->_emit_xs_complex_method('_ADJUST', [], \@adjust_stmts);
                my $xs_output = join("\n", $adjust_lines->@*);
                if (!$self->_needs_eval_fallback($xs_output)) {
                    push @lines, $adjust_lines->@*;
                    push @lines, '';
                    $has_adjust = true;
                }
            }

            # Emit BOOT block after XSUBs (includes eval_pv fallbacks)
            push @lines, $self->_emit_xs_boot_block($class_decl, $field_map, \@fallback_methods, $has_adjust)->@*;
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

        # Determine if the method returns a value.
        # Check last item directly, but also check for returns anywhere
        # in the body (e.g., early returns inside if-blocks).
        my $last_item = $body->[-1];
        my $last_is_return = (defined $last_item
            && $last_item isa Chalk::Bootstrap::IR::Node::Constructor
            && $last_item->class() eq 'ReturnStmt');
        # Detect tail-position expressions: a bare expression as the final
        # body item is treated as a return value (stale-merge strips explicit
        # return in tail position). Uses _is_bare_return_expr for detection.
        my $tail_expr_return = (!$last_is_return
            && defined $last_item
            && $self->_is_bare_return_expr($last_item)
            );
        my $has_return = $last_is_return || $tail_expr_return || $self->_body_contains_return($body);

        # Track C variable declarations needed
        my %declared_vars;

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
        # Also collect all variable references to catch vars from list
        # destructuring and other patterns that don't produce VarDecl nodes
        $self->_collect_all_var_refs($body, \%declared_vars);

        # Detect early returns (ReturnStmt inside If CFG node or non-final position)
        my $has_early_return = $self->_has_early_return($body);

        # Set return context so nested emit_cfg_if can reconstruct stripped
        # ReturnStmt nodes as RETVAL assignments (stale-merge workaround)
        my $prev_return_context = $_return_context;
        $_return_context = $has_return;

        # Emit each body item as C code, marking the last statement
        for my $idx (0 .. $body->@* - 1) {
            my $is_last = ($idx == $body->@* - 1);
            my $stmt = $self->_emit_xs_stmt($body->[$idx], \%declared_vars, $is_last);
            push @code, $stmt if defined $stmt;
        }

        # When the method has returns (from early return branches) but the
        # last statement is a bare expression, wrap it as RETVAL assignment
        # so the XS OUTPUT section can return it.
        if ($has_return && !$last_is_return && @code) {
            my $last_code = $code[-1];
            # Strip trailing semicolon from bare expression statement
            if ($last_code =~ s/;\s*$//) {
                $code[-1] = "RETVAL = $last_code;";
            }
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
        for my $var (sort keys %declared_vars) {
            next if $var eq 'hash';
            next if $var =~ /^param:/;  # method params are XS parameters, not PREINIT vars
            push @lines, "    SV *${var}_sv = NULL;";
        }

        # CODE section
        push @lines, '  CODE:';
        for my $stmt (@code) {
            for my $line (split /\n/, $stmt) {
                push @lines, "    $line";
            }
        }

        # Restore previous return context
        $_return_context = $prev_return_context;

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
                    # Stale-merge can strip ReturnStmt leaving bare expressions
                    return true if $self->_body_contains_bare_return($then);
                    my $else = $state->{else_stmts};
                    return true if defined($else) && ref($else) eq 'ARRAY'
                        && $self->_body_contains_return($else);
                    return true if defined($else) && ref($else) eq 'ARRAY'
                        && $self->_body_contains_bare_return($else);
                }
                # Recurse into loop body_stmts
                if (defined $state && defined $state->{loop}) {
                    my $loop_body = $state->{body_stmts};
                    return true if defined($loop_body) && ref($loop_body) eq 'ARRAY'
                        && $self->_has_early_return($loop_body);
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

    # Check if a body array's last item is a bare return expression (stale-merge)
    method _body_contains_bare_return($body) {
        return false unless ref($body) eq 'ARRAY' && $body->@*;
        my $last = $body->[-1];
        return $self->_is_bare_return_expr($last);
    }

    # Detect if an IR node is a bare expression that was likely a return value
    # stripped by the Earley stale-value merge. Used in emit_cfg_if to
    # reconstruct RETVAL assignment when in return context.
    method _is_bare_return_expr($node) {
        return false unless defined $node;
        return false unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
        my $class = $node->class();
        # Void statement types are never bare return expressions
        my %void = map { $_ => 1 } qw(VarDecl DieCall CompoundAssign ReturnStmt
                                        BuiltinCall BinaryExpr);
        return false if $void{$class};
        # SubscriptExpr and MethodCallExpr are common return-value patterns
        return true if $class eq 'SubscriptExpr';
        return true if $class eq 'MethodCallExpr';
        return true if $class eq 'TernaryExpr';
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
                    if (defined $state->{try_node}) {
                        # Recurse into try and catch bodies
                        my $try = $state->{try_stmts};
                        $self->_collect_var_decls($try, $declared_vars) if ref($try) eq 'ARRAY';
                        my $catch = $state->{catch_stmts};
                        $self->_collect_var_decls($catch, $declared_vars) if ref($catch) eq 'ARRAY';
                        # Register catch variable
                        my $catch_var = $state->{catch_var};
                        if (defined $catch_var) {
                            my $cv = $catch_var;
                            $cv =~ s/^[\$\@\%]//;
                            $declared_vars->{$cv} = true;
                        }
                    }
                    next;
                }
            }

            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            my $class = $item->class();

            if ($class eq 'VarDecl') {
                my $var = $item->inputs()->[0]->value();
                $var =~ s/^[\$\@\%]//;
                # Skip field variables — they use ObjectFIELDS, not PREINIT locals
                next if defined $field_map && exists $field_map->{$var};
                $declared_vars->{$var} = true;
                # Recurse into chained VarDecl init to collect inner variables
                my $init = $item->inputs()->[1];
                if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                        && $init->class() eq 'VarDecl') {
                    $self->_collect_var_decls([$init], $declared_vars);
                }
                # VarDecl with TryCatchStmt init: recurse into try/catch bodies
                if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                        && $init->class() eq 'TryCatchStmt') {
                    my $state = $_cfg_lookup{refaddr($init)};
                    if (defined $state) {
                        my $try = $state->{try_stmts};
                        $self->_collect_var_decls($try, $declared_vars) if ref($try) eq 'ARRAY';
                        my $catch = $state->{catch_stmts};
                        $self->_collect_var_decls($catch, $declared_vars) if ref($catch) eq 'ARRAY';
                        my $catch_var = $state->{catch_var};
                        if (defined $catch_var) {
                            my $cv = $catch_var;
                            $cv =~ s/^[\$\@\%]//;
                            $declared_vars->{$cv} = true;
                        }
                    }
                }
            }
        }
    }

    # Walk the IR tree to find all variable references (Constant nodes whose
    # value looks like $var, @var, %var) and register them in declared_vars.
    # This catches variables from list destructuring and other patterns where
    # the IR doesn't produce explicit VarDecl nodes for all variables.
    method _collect_all_var_refs($nodes, $declared_vars) {
        my @queue = grep { defined $_ } $nodes->@*;
        my %visited;
        while (my $node = shift @queue) {
            next unless ref($node);
            my $addr = refaddr($node);
            next if $visited{$addr}++;

            if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
                my $val = $node->value() // '';
                if ($val =~ /^\$([\w]+)$/) {
                    my $bare = $1;
                    next if defined $field_map && exists $field_map->{$bare};
                    # Skip method parameters — they use bare C names, not _sv locals
                    next if $declared_vars->{"param:$bare"};
                    $declared_vars->{$bare} = true;
                }
            } elsif ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
                push @queue, grep { defined $_ && ref($_) } $node->inputs()->@*;
            }

            # Recurse into cfg_state bodies
            if (%_cfg_lookup) {
                my $state = $_cfg_lookup{$addr};
                if (defined $state) {
                    for my $key (qw(body_stmts then_stmts else_stmts try_stmts catch_stmts)) {
                        my $stmts = $state->{$key};
                        push @queue, grep { defined $_ } $stmts->@* if ref($stmts) eq 'ARRAY';
                    }
                }
            }

            # Recurse into ARRAY refs (arg lists)
            if (ref($node) eq 'ARRAY') {
                push @queue, grep { defined $_ && ref($_) } $node->@*;
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
            if ($class eq 'DieCall')         { return $self->_emit_xs_die_call($node, $declared_vars); }
            if ($class eq 'CompoundAssign')  { return $self->_emit_xs_compound_assign_stmt($node, $declared_vars); }

            # Expression types used as statements (side effects)
            return $self->_emit_xs_expr($node, $declared_vars) . ";";
        }

        if ($node isa Chalk::Bootstrap::IR::Node::Constant) {
            # Loop control keywords: next→continue, last→break, return→return in C
            my $val = $node->value() // '';
            if ($val eq 'next')   { return "continue;"; }
            if ($val eq 'last')   { return "break;"; }
            if ($val eq 'return') { return "return;"; }
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

            # DieCall used as expression: stale-value merge artifact.
            # Emit croak in a statement expression — croak never returns.
            if ($class eq 'DieCall') {
                my $croak = $self->_emit_xs_die_call($node, $declared_vars);
                return "({ $croak &PL_sv_undef; })";
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
            # Package global or unknown variable — use get_sv for package lookup
            my $escaped = $self->_escape_c_string($var);
            return "get_sv(\"${module_name}::$escaped\", GV_ADD)";
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
                } elsif ($declared_vars && $declared_vars->{"param:$var"}) {
                    $src = "$var ? $var : &PL_sv_undef";
                } elsif ($field_map && exists $field_map->{$var}) {
                    my $idx = $field_map->{$var};
                    $src = "ObjectFIELDS(SvRV(self))[$idx]";
                } else {
                    my $escaped = $self->_escape_c_string($var);
                    $src = "get_sv(\"${module_name}::$escaped\", GV_ADD)";
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

        # Range operator — construct an AV from integer start to end.
        # Guard against arrayrefs: stale-value merge in the IR can replace
        # `$obj->method()->@* - 1` with just `$obj->method()` which returns
        # an arrayref. SvIV on a reference gives a pointer address (huge),
        # causing infinite for loops. Use av_len(SvRV(x)) for references.
        if ($op eq '..') {
            return "({ AV *_av = newAV(); "
                . "SV *_rs = $left; SV *_re = $right; "
                . "SSize_t _s = SvROK(_rs) ? av_len((AV*)SvRV(_rs)) : SvIV(_rs); "
                . "SSize_t _e = SvROK(_re) ? av_len((AV*)SvRV(_re)) : SvIV(_re); "
                . "SSize_t _j; "
                . "for (_j = _s; _j <= _e; _j++) av_push(_av, newSViv(_j)); "
                . "newRV_noinc((SV*)_av); })";
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
    # Arguments containing nested method calls (dSP) are pre-evaluated into
    # temp variables before any XPUSHs — nested dSP reads PL_stack_sp which
    # would clobber the outer stack entries if evaluated inline.
    method _emit_xs_method_call_expr($node, $declared_vars) {
        my $invocant_node = $node->inputs()->[0];
        my $method_name   = $node->inputs()->[1]->value();
        my $args          = $node->inputs()->[2];

        # Determine invocant C expression ($self if undef).
        # If the invocant is wrapped in PostfixDerefExpr('$'), unwrap it:
        # call_method needs the blessed reference on the stack, not SvRV(ref).
        my $invocant_expr;
        if (defined $invocant_node) {

            if ($invocant_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $invocant_node->class() eq 'PostfixDerefExpr') {
                # Unwrap any PostfixDerefExpr sigil ($, $#, @, %) — call_method
                # needs the blessed object reference, not a dereferenced value.
                $invocant_expr = $self->_emit_xs_expr($invocant_node->inputs()->[0], $declared_vars);
            } else {
                $invocant_expr = $self->_emit_xs_expr($invocant_node, $declared_vars);
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
            my $arg_expr = $self->_emit_xs_expr($arg, $declared_vars);
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

    # Walk a SubscriptExpr chain to find a BuiltinCall(exists/delete) at the root.
    # Returns the BuiltinCall node if found, undef otherwise.
    method _find_exists_delete_in_chain($node) {
        my $cur = $node;
        while (defined $cur && $cur isa Chalk::Bootstrap::IR::Node::Constructor) {
            if ($cur->class() eq 'BuiltinCall') {
                my $name = $cur->inputs()->[0]->value() // '';
                return $cur if $name eq 'exists' || $name eq 'delete';
                return;
            }
            if ($cur->class() eq 'SubscriptExpr') {
                $cur = $cur->inputs()->[0];
                next;
            }
            # Unwrap ReturnStmt/DieCall wrappers (stale-value merge artifacts)
            if ($cur->class() eq 'ReturnStmt' || $cur->class() eq 'DieCall') {
                $cur = $cur->inputs()->[0];
                next;
            }
            return;
        }
        return;
    }

    # Build native C code for exists/delete with subscript chain.
    # Walks from the outermost SubscriptExpr inward, collecting subscripts,
    # then emits av_fetch/hv_fetch chain with av_exists/hv_exists for last element.
    method _build_exists_delete_native($node, $declared_vars) {
        my @subscripts;  # [index_node, style] from innermost to outermost
        my $cur = $node;
        my $builtin_name;
        my $base_node;

        # Collect subscript chain (outermost first, then reverse)
        while (defined $cur && $cur isa Chalk::Bootstrap::IR::Node::Constructor) {
            if ($cur->class() eq 'SubscriptExpr') {
                push @subscripts, [$cur->inputs()->[1], $cur->inputs()->[2]->value()];
                $cur = $cur->inputs()->[0];
                next;
            }
            if ($cur->class() eq 'ReturnStmt' || $cur->class() eq 'DieCall') {
                $cur = $cur->inputs()->[0];
                next;
            }
            if ($cur->class() eq 'BuiltinCall') {
                $builtin_name = $cur->inputs()->[0]->value();
                my $args = $cur->inputs()->[1];
                $base_node = $args->[0] if $args->@* > 0;
                last;
            }
            last;
        }

        return unless defined $builtin_name && defined $base_node;

        # @subscripts is outermost-first; reverse to get innermost-first
        @subscripts = reverse @subscripts;

        my $base = $self->_emit_xs_expr($base_node, $declared_vars);

        if ($builtin_name eq 'exists') {
            # Build chain: intermediate subscripts use av_fetch/hv_fetch,
            # last subscript uses av_exists/hv_exists_ent.
            # Typed fields (field %hash, field @array) ARE the HV*/AV* directly
            # in ObjectFIELDS — skip SvRV for them.
            my $expr = $base;
            for my $i (0 .. $#subscripts) {
                my ($idx_node, $sty) = $subscripts[$i]->@*;
                my $idx = $self->_emit_xs_expr($idx_node, $declared_vars);
                my $is_last = ($i == $#subscripts);
                my $field_sig = $self->_field_sigil_for_expr($expr);

                if ($sty eq 'array') {
                    my $av = (defined $field_sig && $field_sig eq '@')
                        ? "(AV*)$expr" : "(AV*)SvRV($expr)";
                    if ($is_last) {
                        $expr = "av_exists($av, SvIV($idx))";
                    } else {
                        $expr = "(*av_fetch($av, SvIV($idx), 0))";
                    }
                } else {
                    my $hv = (defined $field_sig && $field_sig eq '%')
                        ? "(HV*)$expr" : "(HV*)SvRV($expr)";
                    if ($is_last) {
                        $expr = "hv_exists_ent($hv, $idx, 0)";
                    } else {
                        $expr = "({ SV *_hk = $idx; STRLEN _hkl; char *_hkp = SvPV(_hk, _hkl); (*hv_fetch($hv, _hkp, _hkl, 0)); })";
                    }
                }
            }
            # av_exists/hv_exists_ent returns bool (int), wrap in SV
            return "($expr ? &PL_sv_yes : &PL_sv_no)";
        }

        if ($builtin_name eq 'delete') {
            # Build chain: intermediate subscripts use av_fetch/hv_fetch,
            # last subscript uses av_delete/hv_delete_ent.
            # Typed fields skip SvRV — see exists chain above.
            my $expr = $base;
            for my $i (0 .. $#subscripts) {
                my ($idx_node, $sty) = $subscripts[$i]->@*;
                my $idx = $self->_emit_xs_expr($idx_node, $declared_vars);
                my $is_last = ($i == $#subscripts);
                my $field_sig = $self->_field_sigil_for_expr($expr);

                if ($sty eq 'array') {
                    my $av = (defined $field_sig && $field_sig eq '@')
                        ? "(AV*)$expr" : "(AV*)SvRV($expr)";
                    if ($is_last) {
                        $expr = "av_delete($av, SvIV($idx), 0)";
                    } else {
                        $expr = "(*av_fetch($av, SvIV($idx), 0))";
                    }
                } else {
                    my $hv = (defined $field_sig && $field_sig eq '%')
                        ? "(HV*)$expr" : "(HV*)SvRV($expr)";
                    if ($is_last) {
                        $expr = "hv_delete_ent($hv, $idx, 0, 0)";
                    } else {
                        $expr = "({ SV *_hk = $idx; STRLEN _hkl; char *_hkp = SvPV(_hk, _hkl); (*hv_fetch($hv, _hkp, _hkl, 0)); })";
                    }
                }
            }
            return $expr;
        }

        return;
    }

    # Emit subscript access (hash or array)
    method _emit_xs_subscript_expr($node, $declared_vars) {
        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2]->value();

        # Handle exists/delete with misparented subscript chain:
        # IR produces SubscriptExpr(BuiltinCall(exists, [$var]), $key) or
        # SubscriptExpr(ReturnStmt(BuiltinCall(exists, [$var])), $key)
        # Collect the full subscript chain and emit native C exists/delete.
        {
            my $builtin = $self->_find_exists_delete_in_chain($node);
            if (defined $builtin) {
                my $native = $self->_build_exists_delete_native($node, $declared_vars);
                return $native if defined $native;
            }
        }

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

        # For typed class fields (field %hash, field @array), the ObjectFIELDS
        # slot IS the HV*/AV* directly — skip SvRV dereference.
        my $field_sig = $self->_field_sigil_for_expr($tgt);

        if ($style eq 'array') {
            my $idx = $self->_emit_xs_expr($index, $declared_vars);
            my $av = (defined $field_sig && $field_sig eq '@')
                ? "(AV*)$tgt" : "(AV*)SvRV($tgt)";
            # av_fetch with lval=1 auto-vivifies missing slots (returns writable
            # SV* for new indices). This matches Perl semantics and is safe for
            # both read and write (assignment target) contexts.
            return "(*av_fetch($av, SvIV($idx), 1))";
        }
        # Hash access — use lval=1 so hv_fetch creates missing keys (avoids NULL deref
        # when used as assignment target). Compute key once via SvPV to avoid
        # double-evaluation of side effects in key expressions.
        #
        # Auto-vivification: when the target is itself a hash subscript result
        # (nested hash like $hash{k1}{k2}), the intermediate hv_fetch(lval=1)
        # may create an undef entry. SvRV(undef) returns NULL, causing segfault.
        # Detect this case and emit an auto-vivification guard.
        my $needs_autoviv = (!defined $field_sig || $field_sig ne '%')
            && $tgt =~ /hv_fetch/;
        my $hv;
        if (defined $field_sig && $field_sig eq '%') {
            $hv = "(HV*)$tgt";
        } elsif ($needs_autoviv) {
            $hv = "({ SV *_av_tgt = $tgt; "
                . "if (!SvROK(_av_tgt)) sv_setsv(_av_tgt, newRV_noinc((SV*)newHV())); "
                . "(HV*)SvRV(_av_tgt); })";
        } else {
            $hv = "(HV*)SvRV($tgt)";
        }
        my $key = $self->_emit_xs_expr($index, $declared_vars);
        # SvPV atomically stringifies and returns both pointer and length.
        # SvPV_nolen + SvCUR is unsafe: SvCUR on a pure IV reads garbage memory.
        return "({ SV *_hk = $key; STRLEN _hkl; char *_hkp = SvPV(_hk, _hkl); (*hv_fetch($hv, _hkp, _hkl, 1)); })";
    }

    # Emit postfix deref (->@*, ->%*, ->$*)
    method _emit_xs_postfix_deref_expr($node, $declared_vars) {
        my $target = $node->inputs()->[0];
        my $sigil  = $node->inputs()->[1]->value();

        my $tgt = defined $target
            ? $self->_emit_xs_expr($target, $declared_vars)
            : 'self';

        # For typed class fields (field %hash, field @array), the ObjectFIELDS
        # slot IS the HV*/AV* directly — skip SvRV dereference.
        my $field_sig = $self->_field_sigil_for_expr($tgt);

        # Check if this deref is used in AV/HV context (push, foreach, etc.)
        # vs SV context (variable assignment). Callers that need AV*/HV*
        # explicitly check for the cast prefix and handle it.
        if ($sigil eq '@') {
            return (defined $field_sig && $field_sig eq '@')
                ? "(AV*)$tgt" : "(AV*)SvRV($tgt)";
        }
        if ($sigil eq '%') {
            return (defined $field_sig && $field_sig eq '%')
                ? "(HV*)$tgt" : "(HV*)SvRV($tgt)";
        }
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
            my $key_node = $pairs->[$i];
            # Detect hash spread: %$var as a key means copy all entries from var
            if ($key_node isa Chalk::Bootstrap::IR::Node::Constant
                    && defined $key_node->value()
                    && $key_node->value() =~ /^%\$(\w+)$/) {
                my $src_var = $1;
                my $src_expr;
                if (exists $declared_vars->{$src_var}) {
                    $src_expr = "${src_var}_sv";
                } elsif (defined $field_map && exists $field_map->{$src_var}) {
                    $src_expr = "ObjectFIELDS(SvRV(self))[$field_map->{$src_var}]";
                } else {
                    $src_expr = "${src_var}_sv";
                }
                push @stores, "{ HV *_src = (HV*)SvRV($src_expr); hv_iterinit(_src); HE *_he; while ((_he = hv_iternext(_src))) { STRLEN _kl; char *_kp = HePV(_he, _kl); hv_store(_hv, _kp, _kl, SvREFCNT_inc(HeVAL(_he)), 0); } }";
                # Spread occupies 1 slot (not a key-value pair). Compensate for
                # the for-loop's $i += 2 so the next iteration lands on the
                # correct key-value pair.
                $i--;
                next;
            }
            my $key = $self->_emit_xs_expr($key_node, $declared_vars);
            my $val = $self->_emit_xs_expr($pairs->[$i + 1], $declared_vars);
            # SvPV atomically stringifies: SvPV_nolen + SvCUR is unsafe on pure IVs
            push @stores, "{ SV *_hk = $key; STRLEN _hkl; char *_hkp = SvPV(_hk, _hkl); hv_store(_hv, _hkp, _hkl, SvREFCNT_inc($val), 0); }";
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

    # Emit anonymous sub by binding C-local variables to package globals,
    # then using eval_pv to create a closure over those globals.
    method _emit_xs_anon_sub_expr($node, $declared_vars) {
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $perl_src = $perl_target->_emit_anon_sub_expr($node);

        # Extract the sub's own parameter names to avoid rewriting them.
        # Parameters in the signature (sub ($x, $y)) must keep their names.
        my %sub_params;
        my $sub_params_node = $node->inputs()->[0];
        for my $p ($sub_params_node->@*) {
            my $pname = $p->value();
            $pname =~ s/^\$//;
            $sub_params{$pname} = true;
        }

        # Scan the sub body for variable references that are C locals.
        # Bind them as package globals before eval_pv so the closure works.
        my @bindings;
        my %bound;
        while ($perl_src =~ /\$(\w+)/g) {
            my $var = $1;
            next if $bound{$var}++;
            # Skip the sub's own parameters and special variables
            next if $var =~ /^_$/;
            next if $sub_params{$var};
            # Check if this is a C-local variable or method parameter
            my $bare = $var;
            if (exists $declared_vars->{"param:$bare"}) {
                # Method parameter: XS declares as bare name, not _sv suffix
                push @bindings, "sv_setsv(get_sv(\"::_anon_$bare\", GV_ADD), $bare)";
            } elsif (exists $declared_vars->{$bare}) {
                push @bindings, "sv_setsv(get_sv(\"::_anon_$bare\", GV_ADD), ${bare}_sv)";
            } elsif (defined $field_map && exists $field_map->{$bare}) {
                my $idx = $field_map->{$bare};
                push @bindings, "sv_setsv(get_sv(\"::_anon_$bare\", GV_ADD), ObjectFIELDS(SvRV(self))[$idx])";
            }
        }

        # Rewrite variable references in the sub BODY to use package globals.
        # Split at the first '{' to avoid rewriting the signature line.
        my $rewritten = $perl_src;
        if ($perl_src =~ /^(sub\s*\([^)]*\)\s*\{)(.*)$/s) {
            my ($sig_line, $body) = ($1, $2);
            for my $var (keys %bound) {
                next if $sub_params{$var};
                next unless exists $declared_vars->{$var}
                    || exists $declared_vars->{"param:$var"}
                    || (defined $field_map && exists $field_map->{$var});
                $body =~ s/\$\Q$var\E/\$::_anon_$var/g;
            }
            $rewritten = $sig_line . $body;
        }

        # Prepend 'use feature "signatures"; no warnings "experimental::signatures";'
        # because eval_pv runs in a bare scope without feature bundles.
        my $prefix = 'use feature "signatures"; no warnings "experimental::signatures"; ';
        my $escaped = $self->_escape_c_string($prefix . $rewritten);
        if (@bindings) {
            return '({ ' . join('; ', @bindings) . '; '
                . "eval_pv(\"$escaped\", TRUE); })";
        }
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
            # PostfixDerefExpr ->@* already returns (AV*)SvRV(...), no need to double-deref
            my $av_expr;
            if ($arr_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $arr_node->class() eq 'PostfixDerefExpr') {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            # Flatten list-producing value arguments (values %hash) into
            # individual av_push calls instead of wrapping in an extra AV.
            my $val_node = $args->[1];
            if ($val_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $val_node->class() eq 'BuiltinCall') {
                my $val_name_node = $val_node->inputs()->[0];
                my $val_name = $val_name_node->value() // '';
                if ($val_name eq 'values') {
                    my $val_args = $val_node->inputs()->[1];
                    my $hash_expr = $self->_emit_xs_expr($val_args->[0], $declared_vars);
                    my $hv_expr;
                    if ($val_args->[0] isa Chalk::Bootstrap::IR::Node::Constructor
                            && $val_args->[0]->class() eq 'PostfixDerefExpr') {
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
            }
            my $val = $self->_emit_xs_expr($val_node, $declared_vars);
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

        # length($str) — native string byte length via SvCUR
        if ($name eq 'length' && $args->@* == 1) {
            my $arg = $self->_emit_xs_expr($args->[0], $declared_vars);
            return "sv_2mortal(newSViv(SvCUR($arg)))";
        }

        # shift(@arr) — native array shift via av_shift
        if ($name eq 'shift' && $args->@* == 1) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_xs_expr($arr_node, $declared_vars);
            my $av_expr;
            if ($arr_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $arr_node->class() eq 'PostfixDerefExpr') {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            return "av_shift($av_expr)";
        }

        # keys(%hash) — native hash key count via HvUSEDKEYS
        if ($name eq 'keys' && $args->@* == 1) {
            my $hash_node = $args->[0];
            my $hash = $self->_emit_xs_expr($hash_node, $declared_vars);
            my $hv_expr;
            if ($hash_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $hash_node->class() eq 'PostfixDerefExpr') {
                $hv_expr = $hash;
            } else {
                $hv_expr = "(HV*)SvRV($hash)";
            }
            return "sv_2mortal(newSViv(HvUSEDKEYS($hv_expr)))";
        }

        # values(%hash) — native hash value iteration via hv_iternext
        if ($name eq 'values' && $args->@* == 1) {
            my $hash_node = $args->[0];
            my $hash = $self->_emit_xs_expr($hash_node, $declared_vars);
            my $hv_expr;
            if ($hash_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $hash_node->class() eq 'PostfixDerefExpr') {
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
            my ($block_node, $list_node);
            if ($args->@* == 2) {
                $block_node = $args->[0];
                $list_node  = $args->[1];
            } else {
                # Single arg: range only, block was lost in parsing.
                # Default to empty hashref (map { {} } RANGE pattern).
                $list_node = $args->[0];
            }

            # Emit the block body — simplified: evaluate the last expression
            my $block_body;
            if (defined $block_node && $block_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $block_node->class() eq 'AnonSubExpr') {
                my $body = $block_node->inputs()->[1] // [];
                if ($body->@*) {
                    $block_body = $self->_emit_xs_expr($body->[-1], $declared_vars);
                }
            }
            $block_body //= 'newRV_noinc((SV*)newHV())';

            # If list is a range (BinaryExpr with '..'), emit integer for loop
            if ($list_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $list_node->class() eq 'BinaryExpr'
                    && defined $list_node->inputs()->[0]
                    && $list_node->inputs()->[0] isa Chalk::Bootstrap::IR::Node::Constant
                    && $list_node->inputs()->[0]->value() eq '..') {
                my $range_left  = $self->_emit_xs_expr($list_node->inputs()->[1], $declared_vars);
                my $range_right = $self->_emit_xs_expr($list_node->inputs()->[2], $declared_vars);
                return "({ AV *_mav = newAV(); "
                    . "SV *_mrs = $range_left; SV *_mre = $range_right; "
                    . "SSize_t _ms = SvROK(_mrs) ? av_len((AV*)SvRV(_mrs)) : SvIV(_mrs); "
                    . "SSize_t _me = SvROK(_mre) ? av_len((AV*)SvRV(_mre)) : SvIV(_mre); "
                    . "SSize_t _mi; "
                    . "for (_mi = _ms; _mi <= _me; _mi++) "
                    . "av_push(_mav, SvREFCNT_inc($block_body)); "
                    . "newRV_noinc((SV*)_mav); })";
            }

            # Generic: iterate over AV
            my $list_expr = $self->_emit_xs_expr($list_node, $declared_vars);
            return "({ AV *_mav = newAV(); AV *_msrc = (AV*)SvRV($list_expr); "
                . "SSize_t _mlen = av_len(_msrc) + 1; SSize_t _mi; "
                . "for (_mi = 0; _mi < _mlen; _mi++) "
                . "av_push(_mav, SvREFCNT_inc($block_body)); "
                . "newRV_noinc((SV*)_mav); })";
        }

        # delete($hash{$key}) — native hash entry removal via hv_delete_ent
        if ($name eq 'delete' && $args->@* == 1) {
            my $sub_node = $args->[0];
            if ($sub_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $sub_node->class() eq 'SubscriptExpr') {
                my $target = $self->_emit_xs_expr($sub_node->inputs()->[0], $declared_vars);
                my $key = $self->_emit_xs_expr($sub_node->inputs()->[1], $declared_vars);
                my $field_sig = $self->_field_sigil_for_expr($target);
                my $hv = (defined $field_sig && $field_sig eq '%')
                    ? "(HV*)$target" : "(HV*)SvRV($target)";
                return "hv_delete_ent($hv, $key, G_DISCARD, 0)";
            }
        }

        # exists($hash{$key}) — native hash key existence check via hv_exists_ent
        if ($name eq 'exists' && $args->@* == 1) {
            my $sub_node = $args->[0];
            if ($sub_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $sub_node->class() eq 'SubscriptExpr') {
                my $target = $self->_emit_xs_expr($sub_node->inputs()->[0], $declared_vars);
                my $key = $self->_emit_xs_expr($sub_node->inputs()->[1], $declared_vars);
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
                    my $a = $self->_emit_xs_expr($args->[1], $declared_vars);
                    my $b = $self->_emit_xs_expr($args->[2], $declared_vars);
                    return "({ U32 _pa = htonl((U32)SvUV($a)); U32 _pb = htonl((U32)SvUV($b)); "
                        . "SV *_pk = sv_2mortal(newSVpvn(\"\", 0)); "
                        . "sv_catpvn(_pk, (char*)&_pa, sizeof(U32)); "
                        . "sv_catpvn(_pk, (char*)&_pb, sizeof(U32)); "
                        . "_pk; })";
                }
            }
        }

        # substr — native C via SvPV + pointer arithmetic
        if ($name eq 'substr' && $args->@* >= 2) {
            my $str = $self->_emit_xs_expr($args->[0], $declared_vars);
            my $off = $self->_emit_xs_expr($args->[1], $declared_vars);
            if ($args->@* >= 3) {
                my $len = $self->_emit_xs_expr($args->[2], $declared_vars);
                return "({ STRLEN _sl; char *_sp = SvPV($str, _sl); "
                    . "SSize_t _so = SvIV($off); SSize_t _sn = SvIV($len); "
                    . "sv_2mortal(newSVpvn(_sp + _so, _sn)); })";
            }
            return "({ STRLEN _sl; char *_sp = SvPV($str, _sl); "
                . "SSize_t _so = SvIV($off); "
                . "sv_2mortal(newSVpvn(_sp + _so, _sl - _so)); })";
        }

        # Qualified function call (e.g., Chalk::Bootstrap::Terminal::match) —
        # use call_pv with C-local args on the stack instead of eval_pv
        if ($name =~ /::/) {
            my @arg_exprs = map { $self->_emit_xs_expr($_, $declared_vars) } $args->@*;
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

        # Fallback — preserve arguments via eval_pv with real Perl expression
        {
            my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
            my @arg_strs = map { $perl_target->_emit_expr($_) } $args->@*;
            my $perl_call = "$name(" . join(', ', @arg_strs) . ")";
            my $escaped = $self->_escape_c_string($perl_call);
            return "eval_pv(\"$escaped\", TRUE)";
        }
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

        # Field variables use ObjectFIELDS accessor with sv_setsv,
        # locals use direct C pointer assignment
        if (defined $field_map && exists $field_map->{$var}) {
            my $idx = $field_map->{$var};
            my $accessor = "ObjectFIELDS(SvRV(self))[$idx]";
            if (defined $init) {
                my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
                return "({ sv_setsv($accessor, $init_expr); $accessor; })";
            }
            return "({ sv_setsv($accessor, &PL_sv_undef); $accessor; })";
        }

        my $c_var = "${var}_sv";
        if (defined $init) {
            my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
            return "({ $c_var = $init_expr; $c_var; })";
        }
        return "({ $c_var = &PL_sv_undef; $c_var; })";
    }

    # Emit VarDecl as C statement (SV assignment)
    method _emit_xs_var_decl($node, $declared_vars) {
        my $raw_var = $node->inputs()->[0]->value();
        my ($sigil) = $raw_var =~ /^([\$\@\%])/;
        my $var = $raw_var;
        $var =~ s/^[\$\@\%]//;
        my $init = $node->inputs()->[1];

        # Default value for uninitialized variables depends on sigil:
        # %hash → empty hashref, @array → empty arrayref, $scalar → undef
        my $default_val = '&PL_sv_undef';
        if (defined $sigil && $sigil eq '%') {
            $default_val = 'newRV_noinc((SV*)newHV())';
        } elsif (defined $sigil && $sigil eq '@') {
            $default_val = 'newRV_noinc((SV*)newAV())';
        }

        # Chained VarDecl: %hash_a = %hash_b = () is an IR artifact where
        # consecutive hash/array resets are merged into a linked list of VarDecl
        # nodes. Split into separate statements: emit inner first, then outer
        # with its sigil-appropriate default.
        if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                && $init->class() eq 'VarDecl') {
            my $inner_stmt = $self->_emit_xs_var_decl($init, $declared_vars);
            # Fall through to emit this variable with its sigil default
            $init = undef;
            my $this_stmt;
            if (defined $field_map && exists $field_map->{$var}) {
                my $idx = $field_map->{$var};
                my $fs = $field_sigils ? ($field_sigils->{$var} // '$') : '$';
                if ($fs eq '%') {
                    $this_stmt = "hv_clear((HV*)ObjectFIELDS(SvRV(self))[$idx]);";
                } elsif ($fs eq '@') {
                    $this_stmt = "av_clear((AV*)ObjectFIELDS(SvRV(self))[$idx]);";
                } else {
                    $this_stmt = "sv_setsv(ObjectFIELDS(SvRV(self))[$idx], $default_val);";
                }
            } else {
                $this_stmt = "${var}_sv = $default_val;";
            }
            return "$inner_stmt\n$this_stmt";
        }

        # Field variables are stored in ObjectFIELDS, not local C variables.
        # In ADJUST bodies, VarDecl for field names emits an ObjectFIELDS write.
        # Hash/array fields (field %h, field @a) are typed containers in Perl 5.42 —
        # reset with hv_clear/av_clear, not sv_setsv with a new ref.
        if (defined $field_map && exists $field_map->{$var}) {
            my $idx = $field_map->{$var};
            my $fs = $field_sigils ? ($field_sigils->{$var} // '$') : '$';
            if (defined $init) {
                my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
                return "sv_setsv(ObjectFIELDS(SvRV(self))[$idx], $init_expr);";
            }
            if ($fs eq '%') {
                return "hv_clear((HV*)ObjectFIELDS(SvRV(self))[$idx]);";
            }
            if ($fs eq '@') {
                return "av_clear((AV*)ObjectFIELDS(SvRV(self))[$idx]);";
            }
            return "sv_setsv(ObjectFIELDS(SvRV(self))[$idx], $default_val);";
        }

        if (defined $init) {
            # TryCatchStmt as VarDecl init is a stale-value merge artifact.
            # The variable is declared with undef, then assigned inside the
            # try block. Split into: declare var, then emit try/catch statement.
            if ($init isa Chalk::Bootstrap::IR::Node::Constructor
                    && $init->class() eq 'TryCatchStmt') {
                my $try_stmt = $self->_emit_xs_stmt($init, $declared_vars);
                return "${var}_sv = $default_val;\n$try_stmt";
            }
            my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
            # PostfixDerefExpr ->@* returns (AV*)SvRV(...). In list context
            # (my ($x) = $ref->@*), the scalar LHS gets element [0], not the
            # AV* itself. Detect this and emit av_fetch for proper indexing.
            if ($init_expr =~ /^\(AV\*\)SvRV\((.+)\)$/) {
                my $rv_expr = $1;
                return "${var}_sv = (*av_fetch((AV*)SvRV($rv_expr), 0, 0));";
            }
            # PostfixDerefExpr ->%* returns (HV*) casts.
            # VarDecl targets are SV*, so cast to avoid type mismatch.
            if ($init_expr =~ /^\(HV\*\)/) {
                $init_expr = "(SV*)$init_expr";
            }
            return "${var}_sv = $init_expr;";
        }
        return "${var}_sv = $default_val;";
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
    method _emit_xs_die_call($node, $declared_vars = undef) {
        my $args = $node->inputs()->[0];
        my $msg = '';
        if (ref($args) eq 'ARRAY' && $args->@*) {
            my $first = $args->[0];
            if ($first isa Chalk::Bootstrap::IR::Node::Constant) {
                $msg = $self->_escape_c_string($first->value());
            } elsif (defined $declared_vars) {
                # Non-constant arg (e.g. string interpolation): emit as expression
                my $expr = $self->_emit_xs_expr($first, $declared_vars);
                return "croak(\"%s\", SvPV_nolen($expr));";
            }
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
        for my $idx (0 .. $true_stmts->@* - 1) {
            my $stmt = $true_stmts->[$idx];
            my $is_last_in_then = ($idx == $true_stmts->@* - 1);
            # Stale-merge can strip ReturnStmt leaving a bare expression.
            # When in return context (method has returns), detect the last
            # bare expression and emit it as RETVAL assignment + goto.
            if ($_return_context && $is_last_in_then
                    && $self->_is_bare_return_expr($stmt)) {
                my $val_expr = $self->_emit_xs_expr($stmt, $declared_vars);
                $val_expr =~ s/^sv_2mortal\((.+)\)$/$1/;
                push @lines, "    RETVAL = $val_expr; goto xsreturn;";
                next;
            }
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
                # PostfixDerefExpr ->@* already returns (AV*)SvRV(...),
                # so skip the SV* intermediate to avoid type mismatch.
                if ($list_expr =~ /^\(AV\*\)/) {
                    push @lines, "    AV *_av = $list_expr;";
                } else {
                    push @lines, "    SV *_list_sv = $list_expr;";
                    push @lines, "    if (!SvROK(_list_sv)) croak(\"Not an ARRAY reference\");";
                    push @lines, "    AV *_av = (AV*)SvRV(_list_sv);";
                }
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

            # Detect while (my $var = shift @array) pattern:
            # VarDecl($var, BuiltinCall(shift, @array))
            # Emit: while ((var_sv = av_shift(...)) != &PL_sv_undef)
            if ($cond isa Chalk::Bootstrap::IR::Node::Constructor
                    && $cond->class() eq 'VarDecl') {
                my $var_name = $cond->inputs()->[0]->value();
                $var_name =~ s/^[\$\@\%]//;
                my $init = $cond->inputs()->[1];
                if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                        && $init->class() eq 'BuiltinCall'
                        && $init->inputs()->[0]->value() eq 'shift') {
                    my $shift_args = $init->inputs()->[1];
                    my $arr_arg = (ref($shift_args) eq 'ARRAY') ? $shift_args->[0] : $shift_args;
                    my $arr_expr = $self->_emit_xs_expr($arr_arg, $declared_vars);
                    my $av_expr = ($arr_expr =~ /^\(AV\*\)/) ? $arr_expr : "(AV*)SvRV($arr_expr)";
                    $declared_vars->{$var_name} = true;
                    push @lines, "while ((${var_name}_sv = av_shift($av_expr)) != &PL_sv_undef) {";
                } else {
                    my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
                    push @lines, "while (SvTRUE($cond_expr)) {";
                }
            } else {
                my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
                push @lines, "while (SvTRUE($cond_expr)) {";
            }

            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
                push @lines, "    $code" if defined $code;
            }
            # Inject chart re-read for while-shift loops that destructure entries.
            # The IR loses list destructuring: my ($item, $alt_idx) = $entry->@*
            # becomes my $item = $entry->@* (alt_idx lost). Also the chart re-read
            # ($item, $alt_idx) = $self->_chart_get(...)->@* is lost entirely.
            # Detect this by checking if the while condition created an entry var
            # and the body uses alt_idx_sv without setting it.
            if ($cond isa Chalk::Bootstrap::IR::Node::Constructor
                    && $cond->class() eq 'VarDecl') {
                my $entry_var = $cond->inputs()->[0]->value();
                $entry_var =~ s/^[\$\@\%]//;
                my $body_code = join("\n", @lines);
                # If body references alt_idx_sv but never assigns it,
                # and there's an entry variable from the while-shift,
                # inject extraction of element [1] from the entry array
                if ($body_code =~ /alt_idx_sv/ && $body_code !~ /alt_idx_sv\s*=/) {
                    # Find the first av_fetch line for element 0 and add element 1 after it
                    my @new_lines;
                    for my $line (@lines) {
                        push @new_lines, $line;
                        if ($line =~ /(\w+)_sv = \(\*av_fetch\(\(AV\*\)SvRV\((\w+_sv)\), 0, 0\)\)/) {
                            my $src_var = $2;
                            push @new_lines, "    alt_idx_sv = (*av_fetch((AV*)SvRV($src_var), 1, 0));";
                        }
                    }
                    @lines = @new_lines;
                }
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

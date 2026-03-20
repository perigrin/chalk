# ABOUTME: Walks Perl IR and emits XS/C code using Perl 5.42 feature class API.
# ABOUTME: Generates .xs with BOOT block, .pm dl_* loader stub, and Build.PL.
use 5.42.0;
use utf8;
use experimental 'class';

use bytes ();
use Chalk::Bootstrap::Perl::Target::EmitHelpers;
use Chalk::Bootstrap::Perl::Target::Perl;

class Chalk::Bootstrap::Perl::Target::XS :isa(Chalk::Bootstrap::Perl::Target::EmitHelpers) {
    field $_cv_cache;  # hashref: "fieldname_methodname" => { field_name, field_idx, method_name }
    field $_semiring_intrinsics :param(semiring_intrinsics) = undef;  # hashref: field_name => { components => [...] }
    field $_class_registry :param(class_registry) = undef;  # ClassRegistry for multi-class compilation
    field $_composite_field_types;  # hashref: field_name => [component_class_slug, ...] for dispatch unrolling
    field %_multi_class_methods;  # class_slug => { method_name => { params => [...] } } across all compiled classes
    field %_fallback_method_slugs;  # "slug:method" => 1 for methods that fell to eval_pv fallback
    field @_anon_sub_fwd_decls;  # forward declarations for anonymous sub CV statics
    field @_anon_sub_helpers;  # accumulated static C functions for anonymous subs
    field @_anon_sub_boot;  # BOOT lines to register anonymous sub CVs via newXS
    field $_anon_sub_counter = 0;  # monotonic counter for unique anonymous sub names

    # Map a TypeInference return type to a C type for XS output.
    # Conservative: all non-void types emit SV*. Extension point for
    # future typed returns (Int → IV, Num → NV, etc.).
    my sub _xs_c_type_for($ti_type) {
        return 'void' if !defined $ti_type || $ti_type eq 'Void';
        return 'SV *';
    }

    method set_return_context($val) { $self->_set_return_context($val); }

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

        $self->_reset_cfg_lookup();
        $self->_build_cfg_lookup($sa, $ctx);
        my $code = $self->_emit_xs($ir);
        $self->_reset_cfg_lookup();
        return $code;
    }

    # Generate distribution with cfg_state-aware dispatch.
    method generate_distribution_with_cfg($ir, $sa, $ctx) {
        $self->_reset_cfg_lookup();
        $self->_build_cfg_lookup($sa, $ctx);

        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $pm_path = $self->_module_path_prefix() . '.pm';
        my $result = {
            $xs_path   => $self->_emit_xs($ir),
            $pm_path   => $self->_emit_pm_stub($ir),
            'Build.PL' => $self->_emit_build_pl(),
        };

        $self->_reset_cfg_lookup();
        return $result;
    }

    # Generate a full distribution from multi-class XS compilation.
    # $entries is an arrayref of { class_name, ir, sa, ctx, cfg_snapshot? } hashrefs.
    # cfg_snapshot is optional; when present, it preserves cfg_state from parse time
    # (needed because SemanticAction's %_cfg_state is shared and gets wiped by reset_cache).
    method generate_distribution_multi_class($entries) {
        # Build cfg_lookup for all entries
        $self->_reset_cfg_lookup();
        for my $entry ($entries->@*) {
            $self->_build_cfg_lookup($entry->{sa}, $entry->{ctx}, $entry->{cfg_snapshot});
        }

        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $pm_path = $self->_module_path_prefix() . '.pm';

        my $xs_content = $self->generate_multi_class($entries);

        # Collect compiled class names for dep detection
        my @compiled_classes = map { $_->{class_name} } $entries->@*;

        my $result = {
            $xs_path   => $xs_content,
            $pm_path   => $self->_emit_pm_stub_with_deps($xs_content, \@compiled_classes),
            'Build.PL' => $self->_emit_build_pl(),
        };

        $self->_reset_cfg_lookup();
        return $result;
    }

    # Convert module name to file path prefix
    method _module_path_prefix() {
        my $path = $self->module_name();
        $path =~ s{::}{/}g;
        return "lib/$path";
    }

    # Emit a static C function that inlines FilterComposite is_zero logic.
    # Takes a semiring_intrinsics component spec and generates short-circuit
    # checks for each component position. Returns arrayref of C source lines.
    method _emit_inline_is_zero($field_name, $spec) {
        my $slug = $self->_get_current_slug();
        my $components = $spec->{components};
        my $field_idx = $self->_get_field_map()->{$field_name};
        my @lines;

        push @lines, "static int _inline_${slug}_is_zero(pTHX_ SV *semiring_field, SV *value) {";
        push @lines, '    if (!value) return 1;';
        # Non-reference values can't be FilterComposite tuples.
        # Fall back to method dispatch for non-tuple semiring values
        # (e.g., Boolean semiring uses plain SVs, not arrayrefs).
        push @lines, '    if (!SvROK(value)) {';
        push @lines, '        dSP; ENTER; SAVETMPS; PUSHMARK(SP);';
        push @lines, '        XPUSHs(semiring_field); XPUSHs(value);';
        push @lines, '        PUTBACK; call_method("is_zero", G_SCALAR);';
        push @lines, '        SPAGAIN; int r = SvTRUE(POPs); PUTBACK;';
        push @lines, '        FREETMPS; LEAVE; return r;';
        push @lines, '    }';
        push @lines, '    if (SvTYPE(SvRV(value)) != SVt_PVAV) {';
        push @lines, '        dSP; ENTER; SAVETMPS; PUSHMARK(SP);';
        push @lines, '        XPUSHs(semiring_field); XPUSHs(value);';
        push @lines, '        PUTBACK; call_method("is_zero", G_SCALAR);';
        push @lines, '        SPAGAIN; int r = SvTRUE(POPs); PUTBACK;';
        push @lines, '        FREETMPS; LEAVE; return r;';
        push @lines, '    }';
        push @lines, '    AV *tuple = (AV*)SvRV(value);';
        # Guard: tuple must have the expected number of components.
        # A FilterComposite with fewer components (e.g., 2-element BNF
        # pipeline vs 5-element Perl pipeline) falls back to method dispatch.
        push @lines, "    if (av_len(tuple) + 1 != ${\scalar $components->@*}) {";
        push @lines, '        dSP; ENTER; SAVETMPS; PUSHMARK(SP);';
        push @lines, '        XPUSHs(semiring_field); XPUSHs(value);';
        push @lines, '        PUTBACK; call_method("is_zero", G_SCALAR);';
        push @lines, '        SPAGAIN; int r = SvTRUE(POPs); PUTBACK;';
        push @lines, '        FREETMPS; LEAVE; return r;';
        push @lines, '    }';
        push @lines, '    SV **p;';
        push @lines, '';

        for my $i (0 .. $components->$#*) {
            my $comp = $components->[$i];
            my $type = $comp->{type};

            push @lines, "    /* Component [$i]: $type */";

            if ($type eq 'boolean_refaddr') {
                # Boolean values: zero = [] (empty AV, a reference),
                # non-zero = true (a non-reference SV). So is_zero is simply
                # SvROK — if it's a reference, it's the zero sentinel.
                push @lines, "    p = av_fetch(tuple, $i, 0);";
                push @lines, '    if (p && SvROK(*p)) return 1;';
            } elsif ($type eq 'hash_valid') {
                push @lines, "    p = av_fetch(tuple, $i, 0);";
                push @lines, '    if (p && SvROK(*p)) {';
                push @lines, '        SV **vp = hv_fetchs((HV*)SvRV(*p), "valid", 0);';
                push @lines, '        if (!vp || !SvTRUE(*vp)) return 1;';
                push @lines, '    }';
            } elsif ($type eq 'defined') {
                push @lines, "    p = av_fetch(tuple, $i, 0);";
                push @lines, '    if (!p || !SvOK(*p)) return 1;';
            } elsif ($type eq 'integer_eq') {
                my $val = $comp->{value};
                push @lines, "    p = av_fetch(tuple, $i, 0);";
                push @lines, "    if (p && SvIV(*p) == $val) return 1;";
            }

            push @lines, '';
        }

        push @lines, '    return 0;';
        push @lines, '}';

        return \@lines;
    }

    # Try to generate a composite method override for methods that iterate over
    # a composite field with known component types. Returns { helper => [...], xsub => [...] }
    # or undef if the method is not a composite dispatch candidate.
    method _try_composite_method_override($mname, $method_item) {
        return unless defined $_composite_field_types && keys $_composite_field_types->%*;
        return unless defined $self->_get_class_methods() && exists $self->_get_class_methods()->{$mname};

        # Methods eligible for composite dispatch unrolling
        my %composite_methods = map { $_ => 1 }
            qw(is_zero multiply should_scan on_scan on_complete add
               _filter_compare on_skip_optional zero one);
        return unless exists $composite_methods{$mname};

        my $meta = $self->_get_class_methods()->{$mname};
        my @params = $meta->{params}->@*;

        # Find the composite field (semirings arrayref)
        my $composite_field;
        for my $fname (sort keys $_composite_field_types->%*) {
            $composite_field = $fname;
            last;
        }
        return unless defined $composite_field && defined $self->_get_field_map()
            && exists $self->_get_field_map()->{$composite_field};

        my $component_slugs = $_composite_field_types->{$composite_field};
        my $field_idx = $self->_get_field_map()->{$composite_field};

        # Check which components have _impl_ for this method.
        # Methods that ALL components have compiled can use _impl_ directly.
        my %has_impl;
        for my $slug ($component_slugs->@*) {
            $has_impl{$slug} = (exists $_multi_class_methods{$slug}
                && exists $_multi_class_methods{$slug}{$mname});
        }

        # For the core methods (multiply, add, is_zero, on_scan, on_complete),
        # all components must have _impl_ — otherwise skip unrolling.
        if ($mname =~ /^(?:multiply|add|is_zero|on_scan|on_complete|_filter_compare)$/) {
            for my $slug ($component_slugs->@*) {
                return unless $has_impl{$slug};
            }
        }

        # Generate the helper function body via dispatch
        my @helper = $self->_emit_composite_helper(
            $mname, \@params, $component_slugs, $field_idx, \%has_impl);
        return unless @helper;

        # Generate XSUB wrapper
        my @xsub = $self->_emit_composite_xsub($mname, \@params);

        return { helper => \@helper, xsub => \@xsub };
    }

    # Generate XSUB wrapper for a composite method override.
    method _emit_composite_xsub($mname, $params) {
        my $slug = $self->_get_current_slug();
        my @xsub;
        if ($params->@*) {
            push @xsub, 'SV *';
            push @xsub, "$mname(self, " . join(', ', $params->@*) . ')';
            push @xsub, '    SV *self';
            push @xsub, "    SV *$_" for $params->@*;
        } else {
            push @xsub, 'SV *';
            push @xsub, "$mname(self)";
            push @xsub, '    SV *self';
        }
        push @xsub, 'CODE:';
        my $call_args = join(', ', 'aTHX_ self', $params->@*);
        push @xsub, "    RETVAL = _impl_${slug}_${mname}($call_args);";
        push @xsub, 'OUTPUT:';
        push @xsub, '    RETVAL';
        push @xsub, '';
        return @xsub;
    }

    # Emit a call to a component's method — _impl_ if available, call_method otherwise.
    # $args_str format: "aTHX_ sr_expr, arg1, arg2, ..." for _impl_ calls.
    # For call_method, aTHX_ is stripped and the rest become XPUSHs arguments.
    # Uses paren-aware splitting to handle nested expressions like av_fetch(_sr, 0, 0).
    # Emit a component call expression for composite dispatch.
    # Returns an owned SV (refcount >= 1). Callers that store in AV should
    # NOT add SvREFCNT_inc — the returned SV is already owned by the caller.
    method _emit_component_call($slug, $mname, $sr_elem, $args_str, $has_impl) {
        if ($has_impl->{$slug}) {
            return "_impl_${slug}_${mname}($args_str)";
        }
        # Parse args: split on top-level commas (respecting parentheses)
        my @parts;
        my $depth = 0;
        my $current = '';
        for my $ch (split //, $args_str) {
            if ($ch eq '(' || $ch eq '{') { $depth++; $current .= $ch; }
            elsif ($ch eq ')' || $ch eq '}') { $depth--; $current .= $ch; }
            elsif ($ch eq ',' && $depth == 0) {
                push @parts, $current;
                $current = '';
            } else {
                $current .= $ch;
            }
        }
        push @parts, $current if length $current;
        # Remove aTHX_ prefix: may be standalone part or prefix of first arg
        if (@parts && $parts[0] =~ /^\s*aTHX_\s*$/) {
            shift @parts;
        } elsif (@parts && $parts[0] =~ s/^\s*aTHX_\s+//) {
            # aTHX_ was joined with first arg (no comma separator)
        }
        # Trim whitespace
        @parts = map { s/^\s+//r =~ s/\s+$//r } @parts;
        my $pushes = join(' ', map { "XPUSHs($_);" } @parts);
        return "({ dSP; ENTER; SAVETMPS; PUSHMARK(SP); $pushes PUTBACK;"
            . " call_method(\"$mname\", G_SCALAR); SPAGAIN;"
            . " SV *_mcr = SvREFCNT_inc(POPs); PUTBACK; FREETMPS; LEAVE; _mcr; })";
    }

    # Generate the static helper function for a composite method.
    method _emit_composite_helper($mname, $params, $component_slugs, $field_idx, $has_impl) {
        my $slug = $self->_get_current_slug();
        my @fwd_params = ('SV *self');
        push @fwd_params, "SV *$_" for $params->@*;
        my $sig = join(', ', @fwd_params);

        my $n_components = scalar $component_slugs->@*;
        my @h;
        push @h, "static SV * _impl_${slug}_${mname}(pTHX_ $sig) {";
        push @h, "    AV *_sr = (AV*)SvRV(ObjectFIELDS(SvRV(self))[$field_idx]);";
        # Guard: component count must match compiled dispatch.
        # A FilterComposite with fewer components (e.g., 2-element BNF pipeline
        # vs 5-element Perl pipeline) falls through to a generic loop that uses
        # call_method on each component individually. This avoids infinite
        # recursion (call_method on self would re-enter this function).
        push @h, "    if (av_len(_sr) + 1 != $n_components) {";
        push @h, "        /* Fallback: dispatch to each component via call_method */";
        if ($mname eq 'zero' || $mname eq 'one') {
            push @h, "        AV *_fb = newAV();";
            push @h, "        I32 _n = av_len(_sr) + 1; I32 _j;";
            push @h, "        for (_j = 0; _j < _n; _j++) {";
            push @h, "            SV *_comp = *av_fetch(_sr, _j, 0);";
            push @h, "            dSP; ENTER; SAVETMPS; PUSHMARK(SP);";
            push @h, "            XPUSHs(_comp);";
            push @h, "            PUTBACK; call_method(\"$mname\", G_SCALAR);";
            push @h, "            SPAGAIN; av_push(_fb, SvREFCNT_inc(POPs)); PUTBACK;";
            push @h, "            FREETMPS; LEAVE;";
            push @h, "        }";
            push @h, "        return newRV_noinc((SV*)_fb);";
        } elsif ($mname eq 'is_zero') {
            push @h, "        I32 _n = av_len(_sr) + 1; I32 _j;";
            push @h, "        for (_j = 0; _j < _n; _j++) {";
            push @h, "            SV *_comp = *av_fetch(_sr, _j, 0);";
            push @h, "            SV *_val = *av_fetch((AV*)SvRV(value), _j, 0);";
            push @h, "            dSP; ENTER; SAVETMPS; PUSHMARK(SP);";
            push @h, "            XPUSHs(_comp); XPUSHs(_val);";
            push @h, "            PUTBACK; call_method(\"is_zero\", G_SCALAR);";
            push @h, "            SPAGAIN; int _iz = SvTRUE(POPs); PUTBACK;";
            push @h, "            FREETMPS; LEAVE;";
            push @h, "            if (_iz) return &PL_sv_yes;";
            push @h, "        }";
            push @h, "        return &PL_sv_no;";
        } else {
            # multiply, add, on_scan, on_complete, etc. — iterate components
            my $has_value_params = ($mname =~ /^(?:multiply|add|_filter_compare)$/);
            if ($has_value_params && $mname eq 'multiply') {
                push @h, "        AV *_la = (AV*)SvRV(left); AV *_ra = (AV*)SvRV(right);";
                push @h, "        AV *_fb = newAV();";
                push @h, "        I32 _n = av_len(_sr) + 1; I32 _j;";
                push @h, "        for (_j = 0; _j < _n; _j++) {";
                push @h, "            SV *_comp = *av_fetch(_sr, _j, 0);";
                push @h, "            dSP; ENTER; SAVETMPS; PUSHMARK(SP);";
                push @h, "            XPUSHs(_comp); XPUSHs(*av_fetch(_la, _j, 0)); XPUSHs(*av_fetch(_ra, _j, 0));";
                push @h, "            PUTBACK; call_method(\"multiply\", G_SCALAR);";
                push @h, "            SPAGAIN; av_push(_fb, SvREFCNT_inc(POPs)); PUTBACK;";
                push @h, "            FREETMPS; LEAVE;";
                push @h, "        }";
                push @h, "        return newRV_noinc((SV*)_fb);";
            } else {
                # For other methods, fall back to eval_pv with the Perl implementation
                # This is a cold path — only used for non-standard component counts
                push @h, "        croak(\"FilterComposite::$mname: component count mismatch (%d != $n_components)\", (int)(av_len(_sr) + 1));";
            }
        }
        push @h, "    }";

        if ($mname eq 'is_zero') {
            $self->_emit_composite_is_zero(\@h, $params, $component_slugs, $has_impl);
        } elsif ($mname eq 'zero' || $mname eq 'one') {
            $self->_emit_composite_zero_one(\@h, $mname, $component_slugs, $has_impl);
        } elsif ($mname eq 'multiply') {
            $self->_emit_composite_multiply(\@h, $component_slugs, $has_impl);
        } elsif ($mname eq 'should_scan') {
            $self->_emit_composite_should_scan(\@h, $params, $component_slugs, $has_impl);
        } elsif ($mname eq 'on_scan') {
            $self->_emit_composite_on_scan(\@h, $params, $component_slugs, $has_impl);
        } elsif ($mname eq 'on_complete') {
            $self->_emit_composite_on_complete(\@h, $params, $component_slugs, $has_impl);
        } elsif ($mname eq 'on_skip_optional') {
            $self->_emit_composite_on_skip_optional(\@h, $params, $component_slugs, $has_impl);
        } elsif ($mname eq 'add') {
            $self->_emit_composite_add(\@h, $component_slugs, $has_impl);
        } elsif ($mname eq '_filter_compare') {
            $self->_emit_composite_filter_compare(\@h, $component_slugs, $has_impl);
        } else {
            return ();
        }

        push @h, '}';
        return @h;
    }

    # is_zero: short-circuit OR — any component zero → return true
    method _emit_composite_is_zero($h, $params, $slugs, $has_impl) {
        # Guard: non-tuple values fall back to method dispatch
        push $h->@*, "    if (!SvROK(value)) return &PL_sv_yes;";
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            my $vi = "(*av_fetch((AV*)SvRV(value), $i, 0))";
            push $h->@*, "    { /* Component [$i]: $slug */";
            my $call = $self->_emit_component_call($slug, 'is_zero', $sr, "aTHX_ $sr, $vi", $has_impl);
            push $h->@*, "        if (SvTRUE($call)) return &PL_sv_yes;";
            push $h->@*, "    }";
        }
        push $h->@*, "    return &PL_sv_no;";
    }

    # zero/one: build tuple from component zero()/one() calls
    method _emit_composite_zero_one($h, $mname, $slugs, $has_impl) {
        push $h->@*, "    AV *_result = newAV();";
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            push $h->@*, "    { /* Component [$i]: $slug */";
            my $call = $self->_emit_component_call($slug, $mname, $sr, "aTHX_ $sr", $has_impl);
            push $h->@*, "        av_push(_result, SvREFCNT_inc($call));";
            push $h->@*, "    }";
        }
        push $h->@*, "    return newRV_noinc((SV*)_result);";
    }

    # multiply: build result tuple, then annihilator check
    method _emit_composite_multiply($h, $slugs, $has_impl) {
        my $class_slug = $self->_get_current_slug();
        # Guard: non-tuple values fall back to zero (should never happen,
        # but prevents segfault from SvRV on non-reference)
        push $h->@*, "    if (!SvROK(left) || SvTYPE(SvRV(left)) != SVt_PVAV) return _impl_${class_slug}_zero(aTHX_ self);";
        push $h->@*, "    if (!SvROK(right) || SvTYPE(SvRV(right)) != SVt_PVAV) return _impl_${class_slug}_zero(aTHX_ self);";
        push $h->@*, "    AV *_result = newAV();";
        push $h->@*, "    SV *_mr;";
        # Build result tuple
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            my $lr = "(*av_fetch((AV*)SvRV(left), $i, 0))";
            my $rr = "(*av_fetch((AV*)SvRV(right), $i, 0))";
            push $h->@*, "    { /* Component [$i]: $slug */";
            my $call = $self->_emit_component_call($slug, 'multiply', $sr, "aTHX_ $sr, $lr, $rr", $has_impl);
            push $h->@*, "        _mr = $call;";
            push $h->@*, "        av_push(_result, SvREFCNT_inc(_mr));";
            push $h->@*, "    }";
        }
        # Annihilator: if any component is zero, return zero tuple
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            my $ri = "(*av_fetch(_result, $i, 0))";
            my $iz_call = $self->_emit_component_call($slug, 'is_zero', $sr, "aTHX_ $sr, $ri", $has_impl);
            push $h->@*, "    if (SvTRUE($iz_call)) {";
            push $h->@*, "        SvREFCNT_dec((SV*)_result);";
            push $h->@*, "        return _impl_${class_slug}_zero(aTHX_ self);";
            push $h->@*, "    }";
        }
        push $h->@*, "    return newRV_noinc((SV*)_result);";
    }

    # should_scan: short-circuit AND — first false returns false
    method _emit_composite_should_scan($h, $params, $slugs, $has_impl) {
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            # Build component_item: copy item hash, replace value with component slice
            push $h->@*, "    { /* Component [$i]: $slug */";
            push $h->@*, "        HV *_ci = newHV();";
            push $h->@*, "        hv_iterinit((HV*)SvRV(item));";
            push $h->@*, "        HE *_he;";
            push $h->@*, "        while ((_he = hv_iternext((HV*)SvRV(item)))) {";
            push $h->@*, "            STRLEN _kl; char *_kp = HePV(_he, _kl);";
            push $h->@*, "            hv_store(_ci, _kp, _kl, SvREFCNT_inc(HeVAL(_he)), 0);";
            push $h->@*, "        }";
            push $h->@*, "        SV **_vp = hv_fetchs((HV*)SvRV(item), \"value\", 0);";
            push $h->@*, "        if (_vp && SvROK(*_vp) && SvTYPE(SvRV(*_vp)) == SVt_PVAV) {";
            push $h->@*, "            SV **_ep = av_fetch((AV*)SvRV(*_vp), $i, 0);";
            push $h->@*, "            if (_ep) hv_stores(_ci, \"value\", SvREFCNT_inc(*_ep));";
            push $h->@*, "        }";
            push $h->@*, "        SV *_ci_ref = newRV_noinc((SV*)_ci);";
            my $args = "aTHX_ $sr, _ci_ref, alt_idx, pos, matched_text, is_predicted";
            my $call = $self->_emit_component_call($slug, 'should_scan', $sr, $args, $has_impl);
            push $h->@*, "        SV *_r = $call;";
            push $h->@*, "        SvREFCNT_dec(_ci_ref);";
            push $h->@*, "        if (!SvTRUE(_r)) return &PL_sv_no;";
            push $h->@*, "    }";
        }
        push $h->@*, "    return &PL_sv_yes;";
    }

    # on_scan: build result tuple with component item slicing, zero check per component
    method _emit_composite_on_scan($h, $params, $slugs, $has_impl) {
        my $class_slug = $self->_get_current_slug();
        push $h->@*, "    AV *_result = newAV();";
        push $h->@*, "    SV *_r;";
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            push $h->@*, "    { /* Component [$i]: $slug */";
            # Build component_item hash
            push $h->@*, "        HV *_ci = newHV();";
            push $h->@*, "        hv_iterinit((HV*)SvRV(item));";
            push $h->@*, "        HE *_he;";
            push $h->@*, "        while ((_he = hv_iternext((HV*)SvRV(item)))) {";
            push $h->@*, "            STRLEN _kl; char *_kp = HePV(_he, _kl);";
            push $h->@*, "            hv_store(_ci, _kp, _kl, SvREFCNT_inc(HeVAL(_he)), 0);";
            push $h->@*, "        }";
            push $h->@*, "        SV **_vp = hv_fetchs((HV*)SvRV(item), \"value\", 0);";
            push $h->@*, "        if (_vp && SvROK(*_vp) && SvTYPE(SvRV(*_vp)) == SVt_PVAV) {";
            push $h->@*, "            SV **_ep = av_fetch((AV*)SvRV(*_vp), $i, 0);";
            push $h->@*, "            if (_ep) hv_stores(_ci, \"value\", SvREFCNT_inc(*_ep));";
            push $h->@*, "        }";
            push $h->@*, "        SV *_ci_ref = newRV_noinc((SV*)_ci);";
            my $args = "aTHX_ $sr, _ci_ref, alt_idx, pos, matched_text";
            my $call = $self->_emit_component_call($slug, 'on_scan', $sr, $args, $has_impl);
            push $h->@*, "        _r = $call;";
            push $h->@*, "        SvREFCNT_dec(_ci_ref);";
            # Zero check: if component returns zero, return composite zero
            my $iz_call = $self->_emit_component_call($slug, 'is_zero', $sr, "aTHX_ $sr, _r", $has_impl);
            push $h->@*, "        if (SvTRUE($iz_call)) {";
            push $h->@*, "            SvREFCNT_dec((SV*)_result);";
            push $h->@*, "            return _impl_${class_slug}_zero(aTHX_ self);";
            push $h->@*, "        }";
            push $h->@*, "        av_push(_result, _r);";
            push $h->@*, "    }";
        }
        push $h->@*, "    return newRV_noinc((SV*)_result);";
    }

    # on_complete: like on_scan but threads TI result to SA via set_type_context
    method _emit_composite_on_complete($h, $params, $slugs, $has_impl) {
        my $class_slug = $self->_get_current_slug();
        push $h->@*, "    AV *_result = newAV();";
        push $h->@*, "    SV *_r;";
        push $h->@*, "    SV *_ti_result = NULL;";
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            push $h->@*, "    { /* Component [$i]: $slug */";
            # Thread TI result (index 2) to SA (index 4)
            if ($i == 4) {
                push $h->@*, "        if (_ti_result) {";
                # SA set_type_context — use _impl_ if available
                if ($has_impl->{'semanticaction'} && exists $_multi_class_methods{'semanticaction'}{'set_type_context'}) {
                    push $h->@*, "            _impl_semanticaction_set_type_context(aTHX_ $sr, _ti_result);";
                } else {
                    push $h->@*, "            { dSP; ENTER; SAVETMPS; PUSHMARK(SP); XPUSHs($sr); XPUSHs(_ti_result); PUTBACK;";
                    push $h->@*, "              call_method(\"set_type_context\", G_SCALAR); SPAGAIN; POPs; PUTBACK; FREETMPS; LEAVE; }";
                }
                push $h->@*, "        }";
            }
            # Build component_item hash
            push $h->@*, "        HV *_ci = newHV();";
            push $h->@*, "        hv_iterinit((HV*)SvRV(item));";
            push $h->@*, "        HE *_he;";
            push $h->@*, "        while ((_he = hv_iternext((HV*)SvRV(item)))) {";
            push $h->@*, "            STRLEN _kl; char *_kp = HePV(_he, _kl);";
            push $h->@*, "            hv_store(_ci, _kp, _kl, SvREFCNT_inc(HeVAL(_he)), 0);";
            push $h->@*, "        }";
            push $h->@*, "        SV **_vp = hv_fetchs((HV*)SvRV(item), \"value\", 0);";
            push $h->@*, "        if (_vp && SvROK(*_vp) && SvTYPE(SvRV(*_vp)) == SVt_PVAV) {";
            push $h->@*, "            SV **_ep = av_fetch((AV*)SvRV(*_vp), $i, 0);";
            push $h->@*, "            if (_ep) hv_stores(_ci, \"value\", SvREFCNT_inc(*_ep));";
            push $h->@*, "        }";
            push $h->@*, "        SV *_ci_ref = newRV_noinc((SV*)_ci);";
            # Pass on_epoch_commit to each component's on_complete so
            # SemanticAction can fire epoch boundary callbacks.
            my $args = "aTHX_ $sr, _ci_ref, alt_idx, pos, on_epoch_commit";
            my $call = $self->_emit_component_call($slug, 'on_complete', $sr, $args, $has_impl);
            push $h->@*, "        _r = $call;";
            push $h->@*, "        SvREFCNT_dec(_ci_ref);";
            # Zero check
            my $iz_call = $self->_emit_component_call($slug, 'is_zero', $sr, "aTHX_ $sr, _r", $has_impl);
            push $h->@*, "        if (SvTRUE($iz_call)) {";
            push $h->@*, "            SvREFCNT_dec((SV*)_result);";
            push $h->@*, "            return _impl_${class_slug}_zero(aTHX_ self);";
            push $h->@*, "        }";
            push $h->@*, "        av_push(_result, _r);";
            # Capture TI result at index 2
            if ($i == 2) {
                push $h->@*, "        _ti_result = _r;";
            }
            push $h->@*, "    }";
        }
        push $h->@*, "    return newRV_noinc((SV*)_result);";
    }

    # on_skip_optional: like on_scan but uses on_skip_optional where available,
    # falls back to multiply(value, one()) for components without it
    method _emit_composite_on_skip_optional($h, $params, $slugs, $has_impl) {
        my $class_slug = $self->_get_current_slug();
        push $h->@*, "    AV *_result = newAV();";
        push $h->@*, "    SV *_r;";
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            push $h->@*, "    { /* Component [$i]: $slug */";
            # Build component_item hash
            push $h->@*, "        HV *_ci = newHV();";
            push $h->@*, "        hv_iterinit((HV*)SvRV(item));";
            push $h->@*, "        HE *_he;";
            push $h->@*, "        while ((_he = hv_iternext((HV*)SvRV(item)))) {";
            push $h->@*, "            STRLEN _kl; char *_kp = HePV(_he, _kl);";
            push $h->@*, "            hv_store(_ci, _kp, _kl, SvREFCNT_inc(HeVAL(_he)), 0);";
            push $h->@*, "        }";
            push $h->@*, "        SV **_vp = hv_fetchs((HV*)SvRV(item), \"value\", 0);";
            push $h->@*, "        if (_vp && SvROK(*_vp) && SvTYPE(SvRV(*_vp)) == SVt_PVAV) {";
            push $h->@*, "            SV **_ep = av_fetch((AV*)SvRV(*_vp), $i, 0);";
            push $h->@*, "            if (_ep) hv_stores(_ci, \"value\", SvREFCNT_inc(*_ep));";
            push $h->@*, "        }";
            push $h->@*, "        SV *_ci_ref = newRV_noinc((SV*)_ci);";
            if ($has_impl->{$slug} && exists $_multi_class_methods{$slug}{'on_skip_optional'}) {
                my $args = "aTHX_ $sr, _ci_ref, alt_idx, pos, symbol_name";
                my $call = $self->_emit_component_call($slug, 'on_skip_optional', $sr, $args, $has_impl);
                push $h->@*, "        _r = $call;";
            } else {
                # Fall back to multiply(value, one()).
                # Use a per-method has_impl lookup: $has_impl was built for on_skip_optional,
                # but the fallback calls multiply/one/is_zero which may be compiled even when
                # on_skip_optional is not. Without this, _emit_component_call falls through to
                # call_method with nested dSP, causing stack corruption.
                my %core_impl = ($slug => (exists $_multi_class_methods{$slug} ? 1 : 0));
                my $comp_val = "({ SV **__vp = hv_fetchs(_ci, \"value\", 0); __vp ? *__vp : &PL_sv_undef; })";
                my $one_call = $self->_emit_component_call($slug, 'one', $sr, "aTHX_ $sr", \%core_impl);
                my $mul_call = $self->_emit_component_call($slug, 'multiply', $sr, "aTHX_ $sr, $comp_val, $one_call", \%core_impl);
                push $h->@*, "        _r = $mul_call;";
            }
            push $h->@*, "        SvREFCNT_dec(_ci_ref);";
            # Zero check — use per-method impl lookup since $has_impl is keyed
            # on on_skip_optional, not is_zero
            my %core_impl_iz = ($slug => (exists $_multi_class_methods{$slug} ? 1 : 0));
            my $iz_call = $self->_emit_component_call($slug, 'is_zero', $sr, "aTHX_ $sr, _r", \%core_impl_iz);
            push $h->@*, "        if (SvTRUE($iz_call)) {";
            push $h->@*, "            SvREFCNT_dec((SV*)_result);";
            push $h->@*, "            return _impl_${class_slug}_zero(aTHX_ self);";
            push $h->@*, "        }";
            push $h->@*, "        av_push(_result, _r);";
            push $h->@*, "    }";
        }
        push $h->@*, "    return newRV_noinc((SV*)_result);";
    }

    # add: zero checks, _filter_compare, verdict logic, post-merge hook
    method _emit_composite_add($h, $slugs, $has_impl) {
        my $slug = $self->_get_current_slug();
        # Guard: non-tuple values fall back to method dispatch
        push $h->@*, "    if (!SvROK(left) || SvTYPE(SvRV(left)) != SVt_PVAV) return right;";
        push $h->@*, "    if (!SvROK(right) || SvTYPE(SvRV(right)) != SVt_PVAV) return left;";
        # Zero handling: if any left component is zero, return right (and vice versa)
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            my $li = "(*av_fetch((AV*)SvRV(left), $i, 0))";
            my $ri = "(*av_fetch((AV*)SvRV(right), $i, 0))";
            my $iz_left = $self->_emit_component_call($slug, 'is_zero', $sr, "aTHX_ $sr, $li", $has_impl);
            my $iz_right = $self->_emit_component_call($slug, 'is_zero', $sr, "aTHX_ $sr, $ri", $has_impl);
            push $h->@*, "    if (SvTRUE($iz_left)) return right;";
            push $h->@*, "    if (SvTRUE($iz_right)) return left;";
        }
        # Call _filter_compare
        push $h->@*, "    SV *_verdict = _impl_${slug}__filter_compare(aTHX_ self, left, right);";
        push $h->@*, '    SV *_winner, *_loser;';
        push $h->@*, '    STRLEN _vl; const char *_vp = SvPV(_verdict, _vl);';
        push $h->@*, '    if (_vl == 11 && memEQ(_vp, "right_loses", 11)) {';
        push $h->@*, '        _winner = left; _loser = right;';
        push $h->@*, '    } else if (_vl == 10 && memEQ(_vp, "left_loses", 10)) {';
        push $h->@*, '        _winner = right; _loser = left;';
        push $h->@*, '    } else {';
        push $h->@*, '        _winner = left; _loser = right;';
        push $h->@*, '    }';
        # Post-merge hook: call on_merge if available
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            # Only SA has on_merge — check at codegen time
            if (exists $_multi_class_methods{$slug}{'on_merge'}) {
                my $wi = "(*av_fetch((AV*)SvRV(_winner), $i, 0))";
                my $lo = "(*av_fetch((AV*)SvRV(_loser), $i, 0))";
                push $h->@*, "    _impl_${slug}_on_merge(aTHX_ $sr, $wi, $lo);";
            } elsif ($slug eq 'semanticaction') {
                # SA may have on_merge via call_method
                my $wi = "(*av_fetch((AV*)SvRV(_winner), $i, 0))";
                my $lo = "(*av_fetch((AV*)SvRV(_loser), $i, 0))";
                push $h->@*, "    { dSP; ENTER; SAVETMPS; PUSHMARK(SP);";
                push $h->@*, "      XPUSHs($sr); XPUSHs(sv_2mortal(newSVpvs(\"on_merge\"))); PUTBACK;";
                push $h->@*, "      call_method(\"can\", G_SCALAR); SPAGAIN;";
                push $h->@*, "      int _has = SvTRUE(POPs); PUTBACK; FREETMPS; LEAVE;";
                push $h->@*, "      if (_has) {";
                push $h->@*, "          dSP; ENTER; SAVETMPS; PUSHMARK(SP);";
                push $h->@*, "          XPUSHs($sr); XPUSHs($wi); XPUSHs($lo); PUTBACK;";
                push $h->@*, "          call_method(\"on_merge\", G_DISCARD); FREETMPS; LEAVE;";
                push $h->@*, "      }";
                push $h->@*, "    }";
            }
        }
        push $h->@*, "    return _winner;";
    }

    # _filter_compare: scan each component for preference between left and right
    method _emit_composite_filter_compare($h, $slugs, $has_impl) {
        for my $i (0 .. $slugs->$#*) {
            my $slug = $slugs->[$i];
            my $sr = "(*av_fetch(_sr, $i, 0))";
            my $li = "(*av_fetch((AV*)SvRV(left), $i, 0))";
            my $ri = "(*av_fetch((AV*)SvRV(right), $i, 0))";
            push $h->@*, "    { /* Component [$i]: $slug */";
            push $h->@*, "        SV *_li = $li; SV *_ri = $ri;";
            # Skip identity: same value means no preference
            push $h->@*, "        int _same = 0;";
            push $h->@*, "        if (SvROK(_li) && SvROK(_ri)) _same = (SvRV(_li) == SvRV(_ri));";
            push $h->@*, "        else if (!SvROK(_li) && !SvROK(_ri)) _same = (SvIV(_li) == SvIV(_ri));";
            push $h->@*, "        if (!_same) {";
            # Call component add
            my $add_call = $self->_emit_component_call($slug, 'add', $sr, "aTHX_ $sr, _li, _ri", $has_impl);
            push $h->@*, "            SV *_result = $add_call;";
            # Normalize to AV: wrap non-array results
            push $h->@*, "            AV *_rav; int _rav_owned = 0;";
            push $h->@*, "            if (SvROK(_result) && SvTYPE(SvRV(_result)) == SVt_PVAV) {";
            push $h->@*, "                _rav = (AV*)SvRV(_result);";
            push $h->@*, "            } else {";
            push $h->@*, "                _rav = newAV(); av_push(_rav, SvREFCNT_inc(_result)); _rav_owned = 1;";
            push $h->@*, "            }";
            push $h->@*, "            SSize_t _rlen = av_len(_rav) + 1;";
            push $h->@*, "            if (_rlen == 1) {";
            push $h->@*, "                SV *_r = *av_fetch(_rav, 0, 0);";
            # Compare: ref by pointer, non-ref by IV
            push $h->@*, "                int _r_eq_left = (SvROK(_r) && SvROK(_li)) ? (SvRV(_r) == SvRV(_li))";
            push $h->@*, "                    : (!SvROK(_r) && !SvROK(_li)) ? (SvIV(_r) == SvIV(_li)) : 0;";
            push $h->@*, "                int _r_eq_right = (SvROK(_r) && SvROK(_ri)) ? (SvRV(_r) == SvRV(_ri))";
            push $h->@*, "                    : (!SvROK(_r) && !SvROK(_ri)) ? (SvIV(_r) == SvIV(_ri)) : 0;";
            push $h->@*, "                if (!(_r_eq_left && _r_eq_right) && (_r_eq_left || _r_eq_right)) {";
            push $h->@*, "                    if (_rav_owned) SvREFCNT_dec((SV*)_rav);";
            push $h->@*, "                    return _r_eq_left ? sv_2mortal(newSVpvs(\"right_loses\")) : sv_2mortal(newSVpvs(\"left_loses\"));";
            push $h->@*, "                }";
            push $h->@*, "            }";
            push $h->@*, "            if (_rav_owned) SvREFCNT_dec((SV*)_rav);";
            push $h->@*, "        }";
            push $h->@*, "    }";
        }
        push $h->@*, "    return sv_2mortal(newSVpvs(\"neither\"));";
    }

    # Emit native C for _copy_cfg_with_scope: copy a cfg_state hashref
    # replacing the scope field. The IR can't handle hash spread ($base->%*)
    # or for loops over hash keys, so emit the HV iteration directly in C.
    method _emit_native_copy_cfg_with_scope() {
        my $slug = $self->_get_current_slug();
        my $fn = "_impl_${slug}__copy_cfg_with_scope";
        my @helper;
        push @helper, "static SV * ${fn}(pTHX_ SV *base, SV *new_scope) {";
        push @helper, '    HV *src = (HV*)SvRV(base);';
        push @helper, '    HV *dst = newHV();';
        push @helper, '    hv_iterinit(src);';
        push @helper, '    HE *entry;';
        push @helper, '    while ((entry = hv_iternext(src)) != NULL) {';
        push @helper, '        STRLEN klen;';
        push @helper, '        char *key = hv_iterkey(entry, (I32*)&klen);';
        push @helper, '        SV *val = hv_iterval(src, entry);';
        push @helper, '        hv_store(dst, key, klen, SvREFCNT_inc(val), 0);';
        push @helper, '    }';
        push @helper, '    /* Replace scope with new value */';
        push @helper, '    hv_store(dst, "scope", 5, SvREFCNT_inc(new_scope), 0);';
        push @helper, '    return newRV_noinc((SV*)dst);';
        push @helper, '}';

        # No XSUB wrapper needed — this is a lexical sub only called from C
        return { helper => \@helper, xsub => undef };
    }

    # Emit native C for _dispatch_action: call a coderef with two arguments.
    # The IR loses coderef-call arguments ($method_ref->($obj, $ctx)), so
    # this emits the call_sv + argument pushing directly, bypassing IR.
    method _emit_native_dispatch_action() {
        my $slug = $self->_get_current_slug();
        my $fn = "_impl_${slug}__dispatch_action";
        my @helper;
        push @helper, "static SV * ${fn}(pTHX_ SV *actions_obj, SV *method_ref, SV *ctx) {";
        push @helper, '    SV *retval = NULL;';
        push @helper, '    {';
        push @helper, '        dSP;';
        push @helper, '        ENTER; SAVETMPS;';
        push @helper, '        PUSHMARK(SP);';
        push @helper, '        XPUSHs(actions_obj);';
        push @helper, '        XPUSHs(ctx);';
        push @helper, '        PUTBACK;';
        push @helper, '        call_sv(method_ref, G_SCALAR);';
        push @helper, '        SPAGAIN;';
        push @helper, '        retval = SvREFCNT_inc(POPs);';
        push @helper, '        PUTBACK;';
        push @helper, '        FREETMPS; LEAVE;';
        push @helper, '    }';
        push @helper, '    return retval;';
        push @helper, '}';

        my @xsub;
        push @xsub, 'SV *';
        push @xsub, '_dispatch_action(actions_obj, method_ref, ctx)';
        push @xsub, '    SV *actions_obj';
        push @xsub, '    SV *method_ref';
        push @xsub, '    SV *ctx';
        push @xsub, '  CODE:';
        push @xsub, "    SV *actions_obj_sv = actions_obj;";
        push @xsub, "    SV *method_ref_sv = method_ref;";
        push @xsub, "    SV *ctx_sv = ctx;";
        push @xsub, "    RETVAL = ${fn}(aTHX_ actions_obj_sv, method_ref_sv, ctx_sv);";
        push @xsub, '  OUTPUT:';
        push @xsub, '    RETVAL';
        push @xsub, '';

        return { helper => \@helper, xsub => \@xsub };
    }

    # Emit native C for set_cfg_state: store cfg_state for a Context.
    # eval_pv can't access class-scope %_cfg_state, so emit direct HV store.
    method _emit_native_set_cfg_state() {
        my $slug = $self->_get_current_slug();
        my $fn = "_impl_${slug}_set_cfg_state";
        my $csv = "_csv_${slug}__cfg_state";
        my @helper;
        push @helper, "static void ${fn}(pTHX_ SV *self, SV *ctx, SV *state) {";
        push @helper, '    PERL_UNUSED_VAR(self);';
        push @helper, "    char key[32];";
        push @helper, '    int klen = snprintf(key, sizeof(key), "%p", (void*)SvRV(ctx));';
        push @helper, "    hv_store($csv, key, klen, SvREFCNT_inc(state), 0);";
        push @helper, '}';

        my @xsub;
        push @xsub, 'void';
        push @xsub, 'set_cfg_state(self, ctx, state)';
        push @xsub, '    SV *self';
        push @xsub, '    SV *ctx';
        push @xsub, '    SV *state';
        push @xsub, '  CODE:';
        push @xsub, "    ${fn}(aTHX_ self, ctx, state);";
        push @xsub, '';

        return { helper => \@helper, xsub => \@xsub, is_void => true };
    }

    # Emit native C for update_cfg: set pending cfg state update.
    # eval_pv can't access class-scope $_pending_cfg_update.
    method _emit_native_update_cfg() {
        my $slug = $self->_get_current_slug();
        my $fn = "_impl_${slug}_update_cfg";
        my $csv = "_csv_${slug}__pending_cfg_update";
        my @helper;
        push @helper, "static void ${fn}(pTHX_ SV *self, SV *state) {";
        push @helper, '    PERL_UNUSED_VAR(self);';
        push @helper, "    sv_setsv($csv, state);";
        push @helper, '}';

        my @xsub;
        push @xsub, 'void';
        push @xsub, 'update_cfg(self, state)';
        push @xsub, '    SV *self';
        push @xsub, '    SV *state';
        push @xsub, '  CODE:';
        push @xsub, "    ${fn}(aTHX_ self, state);";
        push @xsub, '';

        return { helper => \@helper, xsub => \@xsub, is_void => true };
    }

    # Emit native C for on_merge: transfer/merge cfg_state from loser to winner.
    # The eval_pv fallback is completely broken:
    # 1. "return unless defined($x) && defined($y)" compiles to broken syntax
    # 2. %_cfg_state class-scope lexical inaccessible from eval_pv
    # 3. Method body gets truncated (complex conditionals lost)
    method _emit_native_on_merge() {
        my $slug = $self->_get_current_slug();
        my $fn = "_impl_${slug}_on_merge";
        my $csv_cfg = "_csv_${slug}__cfg_state";
        my $can_merge_fn = "_impl_${slug}__can_merge_cfg";
        my $copy_cfg_fn = "_impl_${slug}__copy_cfg_with_scope";
        my @helper;
        push @helper, "static void ${fn}(pTHX_ SV *self, SV *winner, SV *loser) {";
        push @helper, '    PERL_UNUSED_VAR(self);';
        push @helper, '    if (!SvOK(winner) || !SvOK(loser)) return;';
        push @helper, '';
        push @helper, '    /* Look up cfg_state for winner and loser by refaddr */';
        push @helper, '    char w_key[32], l_key[32];';
        push @helper, '    int w_klen = snprintf(w_key, sizeof(w_key), "%p", (void*)SvRV(winner));';
        push @helper, '    int l_klen = snprintf(l_key, sizeof(l_key), "%p", (void*)SvRV(loser));';
        push @helper, '';
        push @helper, "    SV **w_ent = hv_fetch($csv_cfg, w_key, w_klen, 0);";
        push @helper, "    SV **l_ent = hv_fetch($csv_cfg, l_key, l_klen, 0);";
        push @helper, '    SV *winner_state = (w_ent && *w_ent && SvOK(*w_ent)) ? *w_ent : NULL;';
        push @helper, '    SV *loser_state  = (l_ent && *l_ent && SvOK(*l_ent)) ? *l_ent : NULL;';
        push @helper, '';
        push @helper, '    /* If loser has state but winner does not, transfer it */';
        push @helper, '    if (loser_state && !winner_state) {';
        push @helper, "        hv_store($csv_cfg, w_key, w_klen, SvREFCNT_inc(loser_state), 0);";
        push @helper, '        return;';
        push @helper, '    }';
        push @helper, '';
        push @helper, '    /* If both have state, try to merge */';
        push @helper, "    SV *can_merge = ${can_merge_fn}(aTHX_ winner_state ? winner_state : &PL_sv_undef,";
        push @helper, '                                            loser_state ? loser_state : &PL_sv_undef);';
        push @helper, '    if (!SvTRUE(can_merge)) return;';
        push @helper, '';
        push @helper, '    /* Get control->operation() for both sides */';
        push @helper, '    HV *w_hv = (HV*)SvRV(winner_state);';
        push @helper, '    HV *l_hv = (HV*)SvRV(loser_state);';
        push @helper, '    SV **w_ctrl_ent = hv_fetch(w_hv, "control", 7, 0);';
        push @helper, '    SV **l_ctrl_ent = hv_fetch(l_hv, "control", 7, 0);';
        push @helper, '';
        push @helper, '    /* Call operation() on each control node */';
        push @helper, '    dSP;';
        push @helper, '    SV *w_op_sv, *l_op_sv;';
        push @helper, '    {';
        push @helper, '        ENTER; SAVETMPS; PUSHMARK(SP);';
        push @helper, '        XPUSHs(*w_ctrl_ent); PUTBACK;';
        push @helper, '        call_method("operation", G_SCALAR);';
        push @helper, '        SPAGAIN; w_op_sv = SvREFCNT_inc(POPs); PUTBACK;';
        push @helper, '        FREETMPS; LEAVE;';
        push @helper, '    }';
        push @helper, '    {';
        push @helper, '        ENTER; SAVETMPS; PUSHMARK(SP);';
        push @helper, '        XPUSHs(*l_ctrl_ent); PUTBACK;';
        push @helper, '        call_method("operation", G_SCALAR);';
        push @helper, '        SPAGAIN; l_op_sv = SvREFCNT_inc(POPs); PUTBACK;';
        push @helper, '        FREETMPS; LEAVE;';
        push @helper, '    }';
        push @helper, '';
        push @helper, '    /* Pick base: if winner is Start and loser is not, use loser */';
        push @helper, '    STRLEN w_len, l_len;';
        push @helper, '    const char *w_op = SvPV(w_op_sv, w_len);';
        push @helper, '    const char *l_op = SvPV(l_op_sv, l_len);';
        push @helper, '    int w_is_start = (w_len == 5 && strEQ(w_op, "Start"));';
        push @helper, '    int l_is_start = (l_len == 5 && strEQ(l_op, "Start"));';
        push @helper, '    SV *base = (w_is_start && !l_is_start) ? loser_state : winner_state;';
        push @helper, '';
        push @helper, '    SvREFCNT_dec(w_op_sv);';
        push @helper, '    SvREFCNT_dec(l_op_sv);';
        push @helper, '';
        push @helper, '    /* Merge scopes: winner_state->{scope}->merge(loser_state->{scope}) */';
        push @helper, '    SV **w_scope_ent = hv_fetch(w_hv, "scope", 5, 0);';
        push @helper, '    SV **l_scope_ent = hv_fetch(l_hv, "scope", 5, 0);';
        push @helper, '    SV *merged_scope;';
        push @helper, '    {';
        push @helper, '        ENTER; SAVETMPS; PUSHMARK(SP);';
        push @helper, '        XPUSHs(*w_scope_ent);';
        push @helper, '        XPUSHs(*l_scope_ent);';
        push @helper, '        PUTBACK;';
        push @helper, '        call_method("merge", G_SCALAR);';
        push @helper, '        SPAGAIN; merged_scope = SvREFCNT_inc(POPs); PUTBACK;';
        push @helper, '        FREETMPS; LEAVE;';
        push @helper, '    }';
        push @helper, '';
        push @helper, '    /* Copy base with merged scope, store as winner cfg_state */';
        push @helper, "    SV *result = ${copy_cfg_fn}(aTHX_ base, merged_scope);";
        push @helper, '    SvREFCNT_dec(merged_scope);';
        push @helper, "    hv_store($csv_cfg, w_key, w_klen, result, 0);";
        push @helper, '}';

        my @xsub;
        push @xsub, 'void';
        push @xsub, 'on_merge(self, winner, loser)';
        push @xsub, '    SV *self';
        push @xsub, '    SV *winner';
        push @xsub, '    SV *loser';
        push @xsub, '  CODE:';
        push @xsub, "    ${fn}(aTHX_ self, winner, loser);";
        push @xsub, '';

        return { helper => \@helper, xsub => \@xsub, is_void => true };
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
        my $escaped_module = $self->_escape_c_string($self->module_name());
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

        # Emit eval_pv fallback for unsupported methods (skips trivial stubs)
        if ($fallback_methods->@*) {
            my @fallback_lines;
            for my $method ($fallback_methods->@*) {
                my $line = $self->_emit_xs_eval_fallback($method);
                push @fallback_lines, $line if defined $line;
            }
            if (@fallback_lines) {
                push @lines, '    /* eval_pv fallback for unsupported methods */';
                push @lines, @fallback_lines;
                push @lines, '';
            }
        }

        # Restore PL_curstash
        push @lines, '    PL_curstash = old_stash;';
        push @lines, '}';

        return \@lines;
    }

    # Emit the inner content of a BOOT block for a single class (no BOOT:{} wrapper).
    # Used by generate_multi_class to consolidate multiple classes into one BOOT.
    method _emit_xs_boot_block_inner($class_decl, $fmap, $fallback_methods = [], $has_adjust = false) {
        my @lines;
        my $class_name = $class_decl->inputs()->[0]->value();
        my $escaped_class = $self->_escape_c_string($class_name);

        push @lines, "    /* Class: $class_name */";
        push @lines, '    {';
        push @lines, "        HV *stash = gv_stashpv(\"$escaped_class\", GV_ADD);";
        push @lines, '        HV *old_stash = PL_curstash;';
        push @lines, '        PL_curstash = stash;';
        push @lines, '';
        # Skip class setup if the class already exists (loaded from Perl source).
        # Only apply eval_pv method overrides for pre-existing classes.
        push @lines, "        if (!HvSTASH_IS_CLASS(stash)) {";
        push @lines, '            ENTER;';
        push @lines, '            Perl_class_setup_stash(aTHX_ stash);';
        push @lines, '';

        # Apply :isa inheritance
        my $parent = $class_decl->inputs()->[1];
        if (defined $parent) {
            my $parent_name = $parent->value();
            my $isa_attr = "isa($parent_name)";
            my $escaped_attr = $self->_escape_c_string($isa_attr);
            push @lines, '        {';
            push @lines, "            OP *attr = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped_attr\"));";
            push @lines, '            OP *list = newLISTOP(OP_LIST, 0, attr, NULL);';
            push @lines, '            Perl_class_apply_attributes(aTHX_ stash, list);';
            push @lines, '        }';
            push @lines, '';
        }

        # Register fields
        my $body = $class_decl->inputs()->[2];
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor
                     && $item->class() eq 'FieldDecl';

            my $name_node = $item->inputs()->[0];
            my $attrs = $item->inputs()->[1];
            my $default = $item->inputs()->[2];
            my $field_name = $name_node->value();
            my $escaped = $self->_escape_c_string($field_name);

            push @lines, '        {';
            push @lines, '            ENTER;';
            push @lines, '            Perl_class_prepare_initfield_parse(aTHX);';
            push @lines, "            PADOFFSET padix = pad_add_name_pvs(\"$escaped\", padadd_FIELD, NULL, NULL);";
            push @lines, '            PADNAME *pn = PadnamelistARRAY(PadlistNAMES(CvPADLIST(PL_compcv)))[padix];';

            if (ref($attrs) eq 'ARRAY') {
                for my $attr ($attrs->@*) {
                    my $attr_name = $attr->inputs()->[0]->value();
                    my $escaped_attr = $self->_escape_c_string($attr_name);
                    push @lines, '            {';
                    push @lines, "                OP *attr = newSVOP(OP_CONST, 0, newSVpvs(\"$escaped_attr\"));";
                    push @lines, '                Perl_class_apply_field_attributes(aTHX_ pn, attr);';
                    push @lines, '            }';
                }
            }

            if (defined $default) {
                # _emit_defop returns a list of C lines
                my @defop = $self->_emit_defop($default);
                push @lines, map { "    $_" } @defop;
            }

            push @lines, '            LEAVE;';
            push @lines, '        }';
        }

        # Register ADJUST
        if ($has_adjust) {
            push @lines, '        {';
            push @lines, "            GV *adjust_gv = gv_fetchpvs(\"_ADJUST\", 0, SVt_PVCV);";
            push @lines, '            if (adjust_gv && GvCV(adjust_gv)) {';
            push @lines, '                Perl_class_add_ADJUST(aTHX_ stash, GvCV(adjust_gv));';
            push @lines, '            }';
            push @lines, '        }';
        }

        push @lines, '            LEAVE;';

        # Eval fallbacks for methods that couldn't compile to native XS.
        # Only needed for fresh classes — pre-existing classes already have
        # working Perl methods from their source files.
        # Skips trivial stubs (the real Perl methods are already loaded).
        if ($fallback_methods->@*) {
            my @fb;
            for my $method ($fallback_methods->@*) {
                my $line = $self->_emit_xs_eval_fallback($method);
                push @fb, '        ' . $line if defined $line;
            }
            if (@fb) {
                push @lines, '            /* eval_pv fallback for unsupported methods */';
                push @lines, @fb;
            }
        }

        push @lines, '        }';  # end if (!HvSTASH_IS_CLASS(stash))

        # Initialize static class-scope variables.
        # These live outside the class setup block because they must be
        # initialized even when the class already exists from Perl source.
        if (keys %{$self->_get_class_scope_vars()}) {
            push @lines, '';
            push @lines, '        /* Initialize class-scope static variables */';
            # Declare __sv (topic variable) if any init expression uses map/for
            my $needs_topic = false;
            for my $var (sort keys %{$self->_get_class_scope_vars()}) {
                my $info = $self->_get_class_scope_vars()->{$var};
                if (defined $info->{init}) {
                    my $test_expr = eval { $self->_emit_xs_expr($info->{init}, {}) };
                    if (defined $test_expr && $test_expr =~ /__sv/) {
                        $needs_topic = true;
                        last;
                    }
                }
            }
            if ($needs_topic) {
                push @lines, '        SV *__sv = NULL;';
            }
            for my $var (sort keys %{$self->_get_class_scope_vars()}) {
                my $info = $self->_get_class_scope_vars()->{$var};
                my $sname = $info->{static_name};
                push @lines, "        if (!$sname) {";
                if (defined $info->{init}) {
                    # Has an initializer — emit the C expression
                    my $init_expr = eval { $self->_emit_xs_expr($info->{init}, {}) };
                    if (defined $init_expr
                            && !$self->_needs_eval_fallback($init_expr)
                            && $init_expr !~ /get_sv\(/) {
                        if ($info->{sigil} eq '%') {
                            push @lines, "            $sname = (HV*)SvRV($init_expr);";
                            push @lines, "            SvREFCNT_inc((SV*)$sname);";
                        } elsif ($info->{sigil} eq '@') {
                            push @lines, "            $sname = (AV*)SvRV($init_expr);";
                            push @lines, "            SvREFCNT_inc((SV*)$sname);";
                        } else {
                            push @lines, "            $sname = SvREFCNT_inc($init_expr);";
                        }
                    } else {
                        # Initializer too complex — use default
                        push @lines, $self->_emit_csv_default($info, $sname)->@*;
                    }
                } else {
                    # Bare declaration — use type-appropriate default
                    push @lines, $self->_emit_csv_default($info, $sname)->@*;
                }
                push @lines, "        }";
            }
        }

        push @lines, '        PL_curstash = old_stash;';
        push @lines, '    }';

        return \@lines;
    }

    # Emit default initialization for a class-scope static variable.
    # Returns arrayref of C lines for use inside the BOOT block.
    method _emit_csv_default($info, $sname) {
        my @lines;
        if ($info->{sigil} eq '%') {
            push @lines, "            $sname = newHV();";
            push @lines, "            SvREFCNT_inc((SV*)$sname);";
        } elsif ($info->{sigil} eq '@') {
            push @lines, "            $sname = newAV();";
            push @lines, "            SvREFCNT_inc((SV*)$sname);";
        } else {
            push @lines, "            $sname = newSV(0);";
            push @lines, "            SvREFCNT_inc($sname);";
        }
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

    # Detect stale-value merge corruption in a method's XS output:
    # method body has call_method or _impl_ call (real work) but RETVAL is a bare string.
    # Uses _impl_ pattern (XS-specific) in addition to call_method.
    method _is_stale_merge($xs_output) {
        my $has_dispatch = $xs_output =~ /(?:call_method|_impl_)\(/;
        my $has_bare_str = $xs_output =~ /(?:RETVAL|retval) = newSVpvs\("/;
        if ($ENV{DEBUG_STALE_MERGE} && $has_bare_str) {
            warn "STALE_MERGE_CHECK: dispatch=$has_dispatch bare_str=$has_bare_str\n";
            # Show the offending line
            for my $line (split /\n/, $xs_output) {
                warn "  LINE: $line\n" if $line =~ /(?:RETVAL|retval) = newSVpvs/;
            }
        }
        return ($has_dispatch && $has_bare_str);
    }

    # Emit eval_pv fallback for a method that can't be compiled to XS.
    # Generates a Perl sub installed into the module's namespace via eval_pv.
    # Returns undef if the generated body is trivially empty (the real Perl
    # method from the loaded module will be used instead).
    method _emit_xs_eval_fallback($method_decl) {
        my $name = $method_decl->inputs()->[0]->value();
        my $params = $method_decl->inputs()->[1];
        my $body = $method_decl->inputs()->[2];

        # Use Perl target to generate the method body statements.
        # Some IR node types (e.g., Node::If) are not supported by the
        # Perl target — skip those items gracefully.
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my @body_lines;
        for my $item ($body->@*) {
            my $code;
            try {
                $code = $perl_target->_emit_node($item);
            } catch ($e) {
                # Unsupported node type — skip this item in eval fallback
                next;
            }
            push @body_lines, $code if defined $code;
        }

        # Skip trivial stubs — if the body only contains variable declarations
        # and a bare 'return', the original Perl method is already loaded and
        # will be used via normal method dispatch.
        my @meaningful = grep { $_ ne "'return'" && !/^my\b/ } @body_lines;
        if (!@meaningful) {
            return;
        }

        # Build parameter list
        my @param_names = map { $_->value() } $params->@*;
        my $param_list = join(', ', '$self', @param_names);
        my $body_code = join('; ', @body_lines);

        # Wrap as sub in module namespace
        my $mn = $self->module_name();
        my $perl_code = "sub ${mn}::${name} { my ($param_list) = \@_; $body_code }";
        my $escaped = $self->_escape_c_string($perl_code);

        return "    eval_pv(\"$escaped\", TRUE);";
    }

    # Extract per-class XS code sections for assembly into single or multi-class .xs files.
    # Returns hashref: { fwd_decls => [...], helpers => [...], xsubs => [...],
    #   boot_lines => [...], class_decl => $node, field_map => $map }
    # Sets $self->_get_current_slug(), $self->_get_field_map(), $self->_get_class_methods(), $_cv_cache as side effects.
    method _emit_class_sections($ir) {
        my $class_decl = $self->_find_class_decl($ir);
        return unless defined $class_decl;

        # Set the current class slug for identifier namespacing
        my $class_name = $class_decl->inputs()->[0]->value();
        $self->_set_current_slug($self->_class_slug($class_name));
        my $slug = $self->_get_current_slug();

        # Build field map once and store it for use throughout code generation
        $self->_set_field_map($self->_build_field_index_map($class_decl));

        # Pre-scan methods to build $self->_get_class_methods() for direct call optimization
        $self->_set_class_methods($self->_scan_class_methods($class_decl));

        # Pre-scan for field-invocant method calls to build CV cache.
        # Filter out :param fields — their object types vary per instance,
        # so caching CVs in process-wide statics is incorrect (e.g., Earley's
        # $semiring field can be Boolean or FilterComposite). Non-:param fields
        # (initialized in ADJUST) have stable types and can safely use CV caching.
        my $raw_cv_cache = $self->_scan_field_method_calls($class_decl);
        $_cv_cache = {};
        for my $key (sort keys $raw_cv_cache->%*) {
            my $field_name = $raw_cv_cache->{$key}{field_name};
            next if $self->_get_param_fields() && $self->_get_param_fields()->{$field_name};
            $_cv_cache->{$key} = $raw_cv_cache->{$key};
        }

        my @fwd_decl_lines;
        my @helper_lines;
        my @xsub_lines;
        my @fallback_methods;

        my $body = $class_decl->inputs()->[2];
        my @adjust_stmts;
        my @method_items;
        my @sub_items;

        # Pass 1: classify methods and subs as simple or complex
        for my $item ($body->@*) {
            if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'MethodDecl') {
                push @method_items, $item;
                my $mname = $item->inputs()->[0]->value();
                # All methods (simple or complex) compile via _emit_xs_method
                # and get _impl_ helpers — no need to exclude any from dispatch.
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'SubDecl') {
                push @sub_items, $item;
            } elsif ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'VarDecl') {
                # Check for mis-parented SubDecl inside VarDecl initializer.
                # Parser sometimes nests SubDecl as VarDecl initializer when
                # `my %_cache; sub _intern(...)` are adjacent statements.
                my $init = $item->inputs()->[1];
                if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                        && $init->class() eq 'SubDecl') {
                    push @sub_items, $init;
                    # Don't add to @adjust_stmts — the SubDecl body would
                    # break ADJUST compilation. The var name is still tracked
                    # for class-scope-vars via the loop below.
                } else {
                    push @adjust_stmts, $item;
                }
            } elsif (!($item isa Chalk::Bootstrap::IR::Node::Constructor
                       && $item->class() eq 'FieldDecl')) {
                push @adjust_stmts, $item;
            }
        }

        # Collect class-scope variable metadata from ALL VarDecl items in class body.
        # These are compiled as static C variables, initialized in BOOT, and
        # referenced directly by _impl_ helpers instead of falling to eval_pv.
        $self->_reset_class_scope_vars();
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            if ($item->class() eq 'VarDecl') {
                my $raw_var = $item->inputs()->[0]->value();
                my $sigil = substr($raw_var, 0, 1);
                my $var = $raw_var;
                $var =~ s/^[\$\@\%]//;
                my $init = $item->inputs()->[1];
                # Skip VarDecl whose init is a SubDecl (those are sub definitions)
                next if defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                    && $init->class() eq 'SubDecl';
                # Skip VarDecl for variables that are fields (ADJUST assigns them,
                # but they're already handled by the field map)
                next if defined $self->_get_field_map() && exists $self->_get_field_map()->{$var};
                $self->_get_class_scope_vars()->{$var} = {
                    sigil       => $sigil,
                    init        => $init,
                    static_name => "_csv_${slug}_${var}",
                };
            }
        }

        # Extract `use constant { NAME => value, ... }` declarations.
        # Constants are inlined as numeric literals in the generated C,
        # since C doesn't have Perl's constant sub mechanism.
        $self->_reset_use_constants();
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            next unless $item->class() eq 'UseDecl';
            my $mn = $item->inputs()->[0];
            next unless defined $mn && $mn->value() eq 'constant';
            my $args = $item->inputs()->[1];
            next unless defined $args && ref($args) eq 'ARRAY';
            my $hash_expr = $args->[0];
            next unless $hash_expr isa Chalk::Bootstrap::IR::Node::Constructor
                     && $hash_expr->class() eq 'HashRefExpr';
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
                    $self->_get_use_constants()->{$kv} = $vv;
                }
            }
        }

        # Filter class-scope VarDecl out of adjust_stmts — they're
        # initialized as static C variables in BOOT, not in ADJUST.
        @adjust_stmts = grep {
            if ($_ isa Chalk::Bootstrap::IR::Node::Constructor
                    && $_->class() eq 'VarDecl') {
                my $v = $_->inputs()->[0]->value();
                $v =~ s/^[\$\@\%]//;
                !exists $self->_get_class_scope_vars()->{$v};
            } else {
                true;
            }
        } @adjust_stmts;

        # Pass 1b: try to compile class-scope subs BEFORE method emission.
        # Subs that compile successfully stay in %{$self->_get_class_subs()} so method bodies
        # can emit _impl_ direct calls. Failed subs are removed so methods
        # fall back to call_pv with the fully-qualified name.
        for my $sub_item (@sub_items) {
            my $sname = $sub_item->inputs()->[0]->value();
            my $sparams = $sub_item->inputs()->[1];
            my $sbody = $sub_item->inputs()->[2];

            # Native emitters for subs that use patterns the XS codegen
            # can't handle (coderef calls with args, hash spread, loops
            # over hash keys).
            my $native_emitter = {
                '_dispatch_action'    => '_emit_native_dispatch_action',
                '_copy_cfg_with_scope' => '_emit_native_copy_cfg_with_scope',
            };
            if (exists $native_emitter->{$sname}) {
                my $method = $native_emitter->{$sname};
                my $native = $self->$method();
                if (defined $native) {
                    $self->_get_class_subs()->{$sname}{compiled} = true;
                    push @helper_lines, $native->{helper}->@*;
                    push @helper_lines, '';
                    if ($native->{xsub}) {
                        push @xsub_lines, $native->{xsub}->@*;
                        push @xsub_lines, '';
                    }
                    next;
                }
            }

            my @param_nodes;
            for my $p ($sparams->@*) {
                push @param_nodes, $p;
            }

            my $result;
            try {
                $result = $self->_emit_xs_sub($sname, \@param_nodes, $sbody);
            } catch ($e) {
                $self->_delete_class_method($sname);
                $self->_get_class_subs()->{$sname}{compiled} = false;
                next;
            }

            if (ref($result) eq 'HASH') {
                # Check for incomplete compilation: /* unknown node */ or
                # /* unsupported op */ means the emitter couldn't translate
                # some IR nodes to C (e.g., __SUB__ recursion, hash sigil
                # dereference, complex loop patterns). These subs need their
                # IR support expanded before they can compile natively.
                # TODO: eval_pv in sub output indicates unsupported IR nodes
                # that should be compiled natively. Regular expressions may be
                # the only legitimate case, and even those should use the C
                # regex API (pregcomp/pregexec) rather than eval_pv.
                my $helper_text = join("\n", $result->{helper}->@*);
                if ($helper_text =~ m{/\* (?:unknown node|unsupported op)}) {
                    $self->_get_class_subs()->{$sname}{compiled} = false;
                    next;
                }
                # Subs that reference $self but don't have $self as a parameter
                # can't compile as static C functions — self isn't available.
                # This happens with class-scope `my sub` declarations that
                # close over $self from the enclosing class.
                if ($helper_text =~ /\bself\b/
                        && !grep { $_->value() =~ /^\$?self$/ } $sparams->@*) {
                    $self->_get_class_subs()->{$sname}{compiled} = false;
                    next;
                }
                $self->_get_class_subs()->{$sname}{compiled} = true;
                push @helper_lines, $result->{helper}->@*;
                push @helper_lines, '';

                # Package/our subs get XSUB wrappers so Perl code can call them.
                # Lexical subs (my/state) are only callable via direct C calls.
                my $sub_scope = $self->_get_class_subs()->{$sname}{scope} // 'package';
                if ($sub_scope eq 'package' || $sub_scope eq 'our') {
                    my @xsub;
                    my @param_names;
                    for my $p ($sparams->@*) {
                        my $pname = $p->value();
                        $pname =~ s/^[\$\@\%]//;
                        push @param_names, $pname;
                    }
                    my $impl_name = "_impl_${slug}_${sname}";
                    my $call_args;
                    if (@param_names) {
                        $call_args = 'aTHX_ ' . join(', ', map { "${_}_sv" } @param_names);
                    } else {
                        $call_args = 'aTHX';
                    }

                    push @xsub, 'SV *';
                    if (@param_names) {
                        push @xsub, "$sname(" . join(', ', @param_names) . ')';
                        for my $pn (@param_names) {
                            push @xsub, "    SV *${pn}_sv";
                        }
                    } else {
                        push @xsub, "$sname()";
                    }
                    push @xsub, '  CODE:';
                    push @xsub, "    RETVAL = $impl_name($call_args);";
                    push @xsub, '  OUTPUT:';
                    push @xsub, '    RETVAL';
                    push @xsub, '';
                    push @xsub_lines, @xsub;
                }
            }
        }

        # Save method metadata for forward declaration generation after Pass 2
        # (we defer this so we can filter out methods that fall to eval_pv fallback)
        my %pre_fwd_methods;
        for my $mname (sort keys $self->_get_class_methods()->%*) {
            $pre_fwd_methods{$mname} = $self->_get_class_methods()->{$mname};
        }

        # Emit static CV cache declarations for field-invocant method calls
        if ($_cv_cache && keys $_cv_cache->%*) {
            push @fwd_decl_lines, '';
            for my $key (sort keys $_cv_cache->%*) {
                push @fwd_decl_lines, "static CV *_cv_${slug}_${key} = NULL;";
            }
        }

        # Emit inline semiring intrinsics (e.g., _inline_is_zero)
        if (defined $_semiring_intrinsics) {
            for my $fname (sort keys $_semiring_intrinsics->%*) {
                if (defined $self->_get_field_map() && exists $self->_get_field_map()->{$fname}) {
                    my $spec = $_semiring_intrinsics->{$fname};
                    if (defined $spec->{components}) {
                        push @helper_lines, $self->_emit_inline_is_zero($fname, $spec)->@*;
                        push @helper_lines, '';
                    }
                }
            }
        }

        # Emit _impl_ helpers for :reader fields so cross-class dispatch can
        # call them directly without Perl method dispatch overhead.
        # Readers are auto-generated by seal_stash but lack _impl_ helpers.
        if (defined $self->_get_field_map()) {
            for my $fname (sort keys $self->_get_field_map()->%*) {
                next unless $self->_get_class_methods() && $self->_get_class_methods()->{$fname}
                    && $self->_get_class_methods()->{$fname}{is_reader};
                my $fidx = $self->_get_field_map()->{$fname};
                push @fwd_decl_lines, "static SV *_impl_${slug}_${fname}(pTHX_ SV *self);";
                push @helper_lines, "static SV *_impl_${slug}_${fname}(pTHX_ SV *self) {";
                push @helper_lines, "    return SvREFCNT_inc(ObjectFIELDS(SvRV(self))[$fidx]);";
                push @helper_lines, "}";
                push @helper_lines, '';
            }
        }

        # Pass 2: emit all methods (with $self->_get_class_methods() finalized)
        # skip_method_names: methods that call uncompiled my subs — neither
        # XSUB nor eval_pv can reach lexical subs, so the original Perl
        # method must stay in place. Tracked as fallbacks for cross-class
        # dispatch filtering but not emitted.
        # Native method emitter dispatch table: method_name => emitter_method.
        # These emit hand-crafted C for methods that use patterns the XS
        # codegen can't handle (class-scope lexicals, complex unless/&&).
        my %native_method_emitters = (
            'set_cfg_state' => '_emit_native_set_cfg_state',
            'update_cfg'    => '_emit_native_update_cfg',
            'on_merge'      => '_emit_native_on_merge',
        );

        my %skip_method_names;
        for my $item (@method_items) {
            my $mname = $item->inputs()->[0]->value();

            # Composite override: emit hand-crafted C for methods that iterate
            # over a composite field with known component types.
            my $override = $self->_try_composite_method_override($mname, $item);
            if (defined $override) {
                push @helper_lines, $override->{helper}->@*;
                push @helper_lines, '';
                push @xsub_lines, $override->{xsub}->@*;
                push @xsub_lines, '';
                next;
            }

            # Native method emitters for methods that use patterns the XS
            # codegen can't handle (class-scope lexicals, complex unless/&&).
            if (exists $native_method_emitters{$mname}) {
                my $emitter = $native_method_emitters{$mname};
                my $native = $self->$emitter();
                if (defined $native) {
                    # Emit forward declaration with correct return type
                    my $ret_type = $native->{is_void} ? 'void' : 'SV *';
                    my $meta = $self->_get_class_methods()->{$mname};
                    my @fwd_params = ('SV *self');
                    if ($meta) {
                        for my $pname ($meta->{params}->@*) {
                            push @fwd_params, "SV *$pname";
                        }
                    }
                    push @fwd_decl_lines, "static $ret_type _impl_${slug}_${mname}(pTHX_ " . join(', ', @fwd_params) . ");";
                    push @helper_lines, $native->{helper}->@*;
                    push @helper_lines, '';
                    if ($native->{xsub}) {
                        push @xsub_lines, $native->{xsub}->@*;
                        push @xsub_lines, '';
                    }
                    next;
                }
            }

            my $result;
            try {
                $result = $self->_emit_xs_method($item);
            } catch ($e) {
                # Method compilation failed (unsupported IR node types etc.)
                # Fall back to eval_pv
                warn "DEBUG: ::${mname} compile failed: $e" if $ENV{DEBUG_XS_COMPILE};
                $self->_delete_class_method($mname);
                push @fallback_methods, $item;
                next;
            }

            if (ref($result) eq 'HASH') {
                my $helper_output = join("\n", $result->{helper}->@*);
                if ($self->_calls_uncompiled_my_subs($helper_output)) {
                    # Method calls a lexical sub that can't be compiled.
                    # Neither XSUB nor eval_pv can reach it — keep
                    # the original Perl method in place.
                    $self->_delete_class_method($mname);
                    $skip_method_names{$mname} = 1;
                } elsif ($self->_needs_eval_fallback($helper_output)) {
                    $self->_delete_class_method($mname);
                    push @fallback_methods, $item;
                } elsif ($self->_uses_class_scope_vars($helper_output)) {
                    # Method references class-level lexicals (e.g., my $ZERO = []).
                    # The XS emitter creates uninitialized local copies instead of
                    # sharing the class-scope value. Fall back to Perl.
                    $self->_delete_class_method($mname);
                    push @fallback_methods, $item;
                } elsif ($self->_is_stale_merge($helper_output)) {
                    my $fixed = $self->_repair_stale_merge($result->{helper}, $item);
                    push @helper_lines, $fixed->@*;
                    push @helper_lines, '';
                    push @xsub_lines, $result->{xsub}->@*;
                    push @xsub_lines, '';
                } else {
                    push @helper_lines, $result->{helper}->@*;
                    push @helper_lines, '';
                    push @xsub_lines, $result->{xsub}->@*;
                    push @xsub_lines, '';
                }
            } else {
                my $method_lines = $result;
                my $xs_output = join("\n", $method_lines->@*);
                if ($self->_calls_uncompiled_my_subs($xs_output)) {
                    $self->_delete_class_method($mname);
                    $skip_method_names{$mname} = 1;
                } elsif ($self->_needs_eval_fallback($xs_output)) {
                    push @fallback_methods, $item;
                } elsif ($self->_uses_class_scope_vars($xs_output)) {
                    $self->_delete_class_method($mname);
                    push @fallback_methods, $item;
                } elsif ($self->_is_stale_merge($xs_output)) {
                    my $fixed = $self->_repair_stale_merge($method_lines, $item);
                    push @xsub_lines, $fixed->@*;
                    push @xsub_lines, '';
                } else {
                    push @xsub_lines, $method_lines->@*;
                    push @xsub_lines, '';
                }
            }
        }

        # Emit ADJUST as native void XSUB if class has ADJUST statements
        my $has_adjust = false;
        if (@adjust_stmts) {
            my $result = eval { $self->_emit_xs_complex_method('_ADJUST', [], \@adjust_stmts) };
            if (ref($result) eq 'HASH') {
                my $helper_output = join("\n", $result->{helper}->@*);
                if (!$self->_needs_eval_fallback($helper_output)) {
                    my $first_line = $result->{helper}[0];
                    (my $fwd = $first_line) =~ s/\s*\{\s*$/;/;
                    push @fwd_decl_lines, $fwd;
                    push @helper_lines, $result->{helper}->@*;
                    push @helper_lines, '';
                    push @xsub_lines, $result->{xsub}->@*;
                    push @xsub_lines, '';
                    $has_adjust = true;
                }
            }
        }

        # Record fallback and skipped methods per slug for cross-class dispatch filtering
        my %fallback_names;
        for my $fb_item (@fallback_methods) {
            my $fb_name = $fb_item->inputs()->[0]->value();
            $_fallback_method_slugs{"$self->_get_current_slug():$fb_name"} = 1;
            $fallback_names{$fb_name} = 1;
        }
        # Skipped methods (call uncompiled my subs) also need fallback slug tracking
        for my $sname (keys %skip_method_names) {
            $_fallback_method_slugs{"$self->_get_current_slug():$sname"} = 1;
            $fallback_names{$sname} = 1;
        }

        # Emit forward declarations only for methods that got _impl_ helpers
        # (skip those that fell to eval_pv fallback)
        my @method_fwd_decls;
        for my $mname (sort keys %pre_fwd_methods) {
            next if exists $fallback_names{$mname};
            # Skip methods with native emitters — they emit their own fwd decls
            next if exists $native_method_emitters{$mname};
            # Skip subs — they get their own forward decls (with different param lists)
            next if exists $self->_get_class_subs()->{$mname};
            my $meta = $pre_fwd_methods{$mname};
            my @fwd_params = ('SV *self');
            for my $pname ($meta->{params}->@*) {
                push @fwd_params, "SV *$pname";
            }
            push @method_fwd_decls, "static SV * _impl_${slug}_${mname}(pTHX_ " . join(', ', @fwd_params) . ");";
        }
        # Forward declarations for compiled class-scope subs (no $self parameter)
        for my $sname (sort keys %{$self->_get_class_subs()}) {
            my $meta = $self->_get_class_subs()->{$sname};
            next unless $meta->{compiled};
            my @fwd_params;
            for my $pname ($meta->{params}->@*) {
                push @fwd_params, "SV *$pname";
            }
            my $param_str = @fwd_params ? 'pTHX_ ' . join(', ', @fwd_params) : 'pTHX';
            push @method_fwd_decls, "static SV * _impl_${slug}_${sname}($param_str);";
        }
        unshift @fwd_decl_lines, @method_fwd_decls;

        # Emit static declarations for class-scope variables
        if (keys %{$self->_get_class_scope_vars()}) {
            my @csv_decls;
            push @csv_decls, "/* Class-scope variables for $self->_get_current_slug() */";
            for my $var (sort keys %{$self->_get_class_scope_vars()}) {
                my $info = $self->_get_class_scope_vars()->{$var};
                my $c_type = $info->{sigil} eq '%' ? 'HV *'
                           : $info->{sigil} eq '@' ? 'AV *'
                           :                         'SV *';
                push @csv_decls, "static $c_type$info->{static_name} = NULL;";
            }
            unshift @fwd_decl_lines, @csv_decls, '';
        }

        $self->_set_class_methods(undef);

        return {
            fwd_decls        => \@fwd_decl_lines,
            helpers          => \@helper_lines,
            xsubs            => \@xsub_lines,
            fallback_methods => \@fallback_methods,
            class_decl       => $class_decl,
            field_map        => $self->_get_field_map(),
            has_adjust       => $has_adjust,
            class_scope_vars => { %{$self->_get_class_scope_vars()} },
        };
    }

    # Emit the common XS preamble (includes and class C API declarations).
    method _emit_xs_preamble() {
        my @lines;
        push @lines, '#include "EXTERN.h"';
        push @lines, '#include "perl.h"';
        push @lines, '#include "XSUB.h"';
        push @lines, '';
        push @lines, 'extern void Perl_class_setup_stash(pTHX_ HV *stash);';
        push @lines, 'extern void Perl_class_prepare_initfield_parse(pTHX);';
        push @lines, 'extern void Perl_class_set_field_defop(pTHX_ PADNAME *pn, int defmode, OP *defop);';
        push @lines, 'extern void Perl_class_apply_attributes(pTHX_ HV *stash, OP *attrlist);';
        push @lines, 'extern void Perl_class_apply_field_attributes(pTHX_ PADNAME *pn, OP *attrlist);';
        push @lines, 'extern void Perl_class_add_ADJUST(pTHX_ HV *stash, CV *cv);';
        push @lines, '';
        return @lines;
    }

    # Emit the .xs file for a single class.
    method _emit_xs($ir) {
        my @lines = $self->_emit_xs_preamble();

        my $sections = $self->_emit_class_sections($ir);

        if (defined $sections) {
            if ($sections->{fwd_decls}->@*) {
                push @lines, $sections->{fwd_decls}->@*;
                push @lines, '';
            }
            push @lines, $sections->{helpers}->@*;

            push @lines, "MODULE = " . $self->module_name() . "  PACKAGE = " . $self->module_name();
            push @lines, '';
            push @lines, $sections->{xsubs}->@*;

            push @lines, $self->_emit_xs_boot_block(
                $sections->{class_decl}, $sections->{field_map},
                $sections->{fallback_methods}, $sections->{has_adjust},
            )->@*;
        } else {
            push @lines, "MODULE = " . $self->module_name() . "  PACKAGE = " . $self->module_name();
            push @lines, '';
        }

        my $xs_text = join("\n", @lines) . "\n";
        $xs_text = $self->_fixup_xs_list_destructuring($xs_text);
        return $xs_text;
    }

    # Emit a multi-class .xs file from an array of class entries.
    # Each entry: { class_name, ir, sa, ctx }
    # Produces one preamble, per-class helpers/XSUBs, and consolidated BOOT.
    method generate_multi_class($entries) {
        my @lines = $self->_emit_xs_preamble();
        my @all_sections;

        # Reset regex statics and anon sub state for this compilation unit
        $self->_reset_regex_statics();
        $self->_reset_regex_counter();
        @_anon_sub_fwd_decls = ();
        @_anon_sub_helpers = ();
        @_anon_sub_boot = ();
        $_anon_sub_counter = 0;

        # Pre-pass: collect method metadata from all classes for cross-class dispatch.
        # Also populate composite_field_types for classes with composite_components.
        %_multi_class_methods = ();
        %_fallback_method_slugs = ();
        $_composite_field_types = undef;

        for my $entry ($entries->@*) {
            my $slug = $self->_class_slug($entry->{class_name});
            # Quick scan: find class decl and scan methods
            my $class_decl = $self->_find_class_decl($entry->{ir});
            next unless defined $class_decl;
            my $methods = $self->_scan_class_methods($class_decl);
            $_multi_class_methods{$slug} = $methods if defined $methods;
        }

        # Build composite field type mappings from registry metadata
        if (defined $_class_registry) {
            for my $entry ($entries->@*) {
                my $reg_entry = $_class_registry->resolve($entry->{class_name});
                next unless defined $reg_entry && defined $reg_entry->{composite_components};
                my $cc = $reg_entry->{composite_components};
                # cc is hashref: field_name => [class_name, class_name, ...]
                $_composite_field_types //= {};
                for my $fname (sort keys $cc->%*) {
                    my @slugs = map { $self->_class_slug($_) } $cc->{$fname}->@*;
                    $_composite_field_types->{$fname} = \@slugs;
                }
            }
        }

        # Phase 1: emit all helpers and forward declarations
        my @fwd_lines;
        my @helper_lines;
        for my $entry ($entries->@*) {
            $self->_reset_cfg_lookup();
            $self->_build_cfg_lookup($entry->{sa}, $entry->{ctx}, $entry->{cfg_snapshot});

            my $sections = $self->_emit_class_sections($entry->{ir});
            next unless defined $sections;

            push @all_sections, {
                sections    => $sections,
                class_name  => $entry->{class_name},
            };

            if ($sections->{fwd_decls}->@*) {
                push @fwd_lines, $sections->{fwd_decls}->@*;
                push @fwd_lines, '';
            }
            push @helper_lines, $sections->{helpers}->@*;
        }

        # Emit forward declarations first
        push @lines, @fwd_lines;

        # Emit static REGEXP* declarations for lazy-compiled regex patterns
        if ($self->_get_regex_statics() && $self->_get_regex_statics()->@*) {
            for my $rx ($self->_get_regex_statics()->@*) {
                push @lines, "static REGEXP *$rx->{var} = NULL;";
            }
            push @lines, '';
        }

        # Emit static HV* stash pointers for speculative :param dispatch.
        # Initialized in BOOT to avoid per-call gv_stashpv lookup.
        {
            my %stash_slugs;
            for my $slug (sort keys %_multi_class_methods) {
                $stash_slugs{$slug} = 1;
            }
            for my $slug (sort keys %stash_slugs) {
                push @lines, "static HV *_stash_${slug} = NULL;";
            }
            push @lines, '' if keys %stash_slugs;
        }

        # Emit forward declarations for anonymous sub CV statics
        # (must appear before helper_lines which may reference them)
        if (@_anon_sub_fwd_decls) {
            push @lines, @_anon_sub_fwd_decls;
            push @lines, '';
        }

        # Emit helpers (which reference the regex statics and anon sub CV vars)
        push @lines, @helper_lines;

        # Emit anonymous sub static helpers accumulated during method compilation
        if (@_anon_sub_helpers) {
            push @lines, '';
            push @lines, @_anon_sub_helpers;
        }

        # Phase 2: emit MODULE/PACKAGE sections with XSUBs
        for my $entry (@all_sections) {
            my $pkg = $entry->{class_name};
            push @lines, "MODULE = " . $self->module_name() . "  PACKAGE = $pkg";
            push @lines, '';
            push @lines, $entry->{sections}{xsubs}->@*;
        }

        # Phase 3: consolidated BOOT block after all MODULE sections.
        # BOOT must come last because xsubpp treats everything after BOOT:
        # as C code until the next MODULE directive.
        push @lines, 'BOOT:';
        push @lines, '{';
        # Initialize stash pointers for speculative :param dispatch
        for my $entry ($entries->@*) {
            my $slug = $self->_class_slug($entry->{class_name});
            push @lines, "    _stash_${slug} = gv_stashpv(\"$entry->{class_name}\", GV_ADD);";
        }
        for my $e (@all_sections) {
            my $s = $e->{sections};
            # Restore per-class class-scope vars for BOOT initialization
            %{$self->_get_class_scope_vars()} = $s->{class_scope_vars}->%*;
            my $boot_inner = $self->_emit_xs_boot_block_inner(
                $s->{class_decl}, $s->{field_map},
                $s->{fallback_methods}, $s->{has_adjust},
            );
            push @lines, $boot_inner->@*;
        }
        # Register anonymous sub CVs so call_sv can dispatch to them
        if (@_anon_sub_boot) {
            push @lines, @_anon_sub_boot;
        }
        push @lines, '}';

        $self->_reset_cfg_lookup();
        %_multi_class_methods = ();
        $_composite_field_types = undef;

        my $xs_text = join("\n", @lines) . "\n";
        $xs_text = $self->_fixup_xs_list_destructuring($xs_text);
        return $xs_text;
    }


    # Emit a single XSUB for a MethodDecl
    method _emit_xs_method($method_decl) {
        my $slug   = $self->_get_current_slug();
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
                    # Produce _impl_ helper + XSUB so composite dispatch can
                    # call this method directly without call_method overhead.
                    my $c_expr = "newSVpvs(\"$str\")";
                    # Map well-known constants to efficient C representations
                    my $raw = $value->value();
                    if ($raw eq '1' || $raw eq 'true') {
                        $c_expr = 'SvREFCNT_inc(&PL_sv_yes)';
                    } elsif ($raw eq '0' || $raw eq 'false' || $raw eq '') {
                        $c_expr = 'SvREFCNT_inc(&PL_sv_no)';
                    } elsif ($raw eq 'undef') {
                        $c_expr = 'SvREFCNT_inc(&PL_sv_undef)';
                    } elsif ($raw =~ /\A-?\d+\z/) {
                        $c_expr = "newSViv($raw)";
                    }
                    # Build parameter lists for both helper and XSUB
                    my @helper_params = ('SV *self');
                    my @xsub_params = ('SV *self');
                    for my $p ($params->@*) {
                        my $pname = $p->value();
                        $pname =~ s/^\$//;
                        push @helper_params, "SV *$pname";
                        push @xsub_params, "SV *$pname";
                    }
                    my @helper;
                    push @helper, "static SV *_impl_${slug}_${name}(pTHX_ " . join(', ', @helper_params) . ") {";
                    push @helper, "    return $c_expr;";
                    push @helper, "}";
                    my $xsub_call_args = join(', ', 'aTHX_ self', map { my $p = $_; $p =~ s/^SV \*//; $p } @xsub_params[1..$#xsub_params]);
                    my @xsub;
                    push @xsub, 'SV *';
                    if (@xsub_params > 1) {
                        push @xsub, "${name}(" . join(', ', map { my $p = $_; $p =~ s/^SV \*//; $p } @xsub_params) . ')';
                    } else {
                        push @xsub, "${name}(self, ...)";
                    }
                    push @xsub, "    $_" for @xsub_params;
                    push @xsub, '  CODE:';
                    push @xsub, "    RETVAL = _impl_${slug}_${name}($xsub_call_args);";
                    push @xsub, '  OUTPUT:';
                    push @xsub, '    RETVAL';
                    return { helper => \@helper, xsub => \@xsub };
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

        # Pass return_type from IR to complex method emitter
        my $return_type_node = $method_decl->inputs()->[3];
        my $return_type = $return_type_node ? $return_type_node->value() : undef;
        return $self->_emit_xs_complex_method($name, $params, $body, $return_type);
    }

    # Emit a multi-statement method body as an XSUB using Perl API calls.
    # Collects variable declarations into PREINIT section and body statements
    # into CODE section. Uses eval_pv() for constructs too complex for pure C
    # (regex, backticks, complex interpolation).
    # $ir_return_type: rich type from TypeInference (Int, Str, Bool, etc.),
    # 'Void' for void methods, or undef to fall back to heuristic detection.
    method _emit_xs_complex_method($name, $params, $body, $ir_return_type = undef) {
        my $slug = $self->_get_current_slug();
        my @code;

        # Determine if the method returns a value.
        my $last_item = $body->[-1];
        my $last_is_return = (defined $last_item
            && $last_item isa Chalk::Bootstrap::IR::Node::Constructor
            && $last_item->class() eq 'ReturnStmt');
        # Detect tail-position expressions: a bare expression as the final
        # body item is treated as a return value (stale-merge strips explicit
        # return in tail position).
        # Three cases:
        # 1. Unambiguous value exprs (TernaryExpr) — always treated as return
        # 2. Ambiguous exprs (MethodCallExpr, SubscriptExpr) — only when body
        #    also contains ReturnStmts (distinguishes from side-effects like ADJUST)
        # 3. Single-statement bodies with expression-type tail — stale-merge
        #    stripped the only ReturnStmt, so no other returns exist to trigger
        #    case 2. Treat non-void expressions as return values.
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
        # Use IR return_type when available, fall back to heuristic.
        # Override Void when the body clearly has returns (IR type inference
        # sometimes misclassifies methods calling my-sub helpers as Void
        # because it can't see inside the sub to determine the return type).
        my $heuristic_has_return = $last_is_return || $tail_expr_return
               || $single_stmt_return || $body_has_returns;
        my $has_return;
        if (defined $ir_return_type && $ir_return_type eq 'Void'
                && ($last_is_return || $body_has_returns)) {
            # Body has explicit returns but IR says Void — trust the body
            $has_return = true;
            $ir_return_type = 'Any';  # fall back to generic SV* for XSUB type
        } elsif (defined $ir_return_type) {
            $has_return = $ir_return_type ne 'Void';
        } else {
            $has_return = $heuristic_has_return;
        }

        # Track C variable declarations needed
        my %declared_vars;

        # Track method parameters as declared vars before body emission,
        # so _emit_xs_const_expr can resolve them as C parameters
        my @xs_params = ('SV *self');
        for my $p ($params->@*) {
            my $pname = $p->value();
            $pname =~ s/^[\$\@\%]//;
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
        my $prev_return_context = $self->_get_return_context();
        $self->_set_return_context($has_return);

        # Emit each body item as C code, marking the last statement
        for my $idx (0 .. $body->@* - 1) {
            my $is_last = ($idx == $body->@* - 1);
            my $stmt = $self->_emit_xs_stmt($body->[$idx], \%declared_vars, $is_last);
            push @code, $stmt if defined $stmt;
        }

        # Assign the last expression to retval so the helper returns it.
        # Helpers always return SV* (void methods return &PL_sv_undef as
        # fallback), so we always try to capture the tail expression.
        # For explicitly returning methods, the ReturnStmt already sets
        # retval via the 'retval = ...; goto xsreturn;' pattern.
        if (!$last_is_return && @code) {
            my $last_code = $code[-1];
            # Handle multi-line code entries (e.g., chained VarDecl):
            # split into separate entries, only wrap the final line as retval.
            if ($last_code =~ /\n/) {
                my @parts = split(/\n/, $last_code);
                my $final_line = pop @parts;
                # Replace the multi-line entry with the leading lines
                $code[-1] = join("\n", @parts);
                # Wrap the final line as retval (skip void operations like sv_setsv)
                if ($final_line =~ s/;\s*$//) {
                    if ($final_line =~ /^sv_setsv\b/) {
                        push @code, "$final_line;";
                    } else {
                        my $wrapped = $self->_wrap_retval($final_line);
                        push @code, "retval = $wrapped;";
                    }
                } else {
                    push @code, $final_line;
                }
            } else {
                # Strip trailing semicolon from bare expression statement
                if ($last_code =~ s/;\s*$//) {
                    if ($last_code =~ /^sv_setsv\b/) {
                        $code[-1] = "$last_code;";
                    } else {
                        my $wrapped = $self->_wrap_retval($last_code);
                        $code[-1] = "retval = $wrapped;";
                    }
                }
            }
        }

        # Restore previous return context
        $self->_set_return_context($prev_return_context);

        # Build the static helper function.
        # Helpers always return SV* so callers can use them uniformly as
        # expressions. Void methods return &PL_sv_undef. The XSUB wrapper
        # preserves the original void/SV* distinction for Perl callers.
        my @helper;
        my $helper_name = "_impl_${slug}_${name}";
        push @helper, "static SV * $helper_name(pTHX_ " . join(', ', @xs_params) . ") {";

        # Local variable declarations (were PREINIT in XSUB)
        push @helper, '    SV *retval = NULL;';
        for my $var (sort keys %declared_vars) {
            next if $var eq 'hash';
            next if $var =~ /^param:/;
            push @helper, "    SV *${var}_sv = NULL;";
        }

        # Body statements — rewrite RETVAL references to retval,
        # and bare 'return;' to 'return &PL_sv_undef;' since all helpers
        # are declared as returning SV*.
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

        # Build the thin XSUB wrapper
        my @xsub;
        if ($has_return) {
            push @xsub, _xs_c_type_for($ir_return_type);
        } else {
            push @xsub, 'void';
        }
        my @bare_params = map { /^SV \*(.*)/ ? $1 : $_ } @xs_params;
        # Use varargs (self, ...) when method has >1 param to support
        # optional parameters. Pull each param from the stack with
        # &PL_sv_undef as the default for missing args.
        my @non_self_params = @bare_params[1..$#bare_params];
        if (@non_self_params > 1) {
            push @xsub, "${name}(self, ...)";
            push @xsub, "    SV *self";
            push @xsub, '  PREINIT:';
            for my $idx (0 .. $#non_self_params) {
                my $p = $non_self_params[$idx];
                my $stack_idx = $idx + 1;  # ST(0) = self
                push @xsub, "    SV *$p = items > $stack_idx ? ST($stack_idx) : &PL_sv_undef;";
            }
        } else {
            push @xsub, "${name}(" . join(', ', @bare_params) . ")";
            for my $p (@xs_params) {
                push @xsub, "    $p";
            }
        }
        push @xsub, '  CODE:';
        my $call_args = join(', ', 'aTHX_ self', @non_self_params);
        if ($has_return) {
            push @xsub, "    RETVAL = $helper_name($call_args);";
            push @xsub, '  OUTPUT:';
            push @xsub, '    RETVAL';
        } else {
            push @xsub, "    $helper_name($call_args);";
        }

        return { helper => \@helper, xsub => \@xsub, returns => $has_return };
    }

    # Emit a class-scope sub declaration as a static C helper function.
    # Unlike methods, subs have no implicit $self parameter.
    # Returns hashref { helper => [...] } (no xsub — subs are internal only).
    method _emit_xs_sub($name, $params, $body) {
        my $slug = $self->_get_current_slug();
        my @code;

        my $last_item = $body->[-1];
        my $last_is_return = (defined $last_item
            && $last_item isa Chalk::Bootstrap::IR::Node::Constructor
            && $last_item->class() eq 'ReturnStmt');
        # Bare 'return' keyword appears as a Constant (not ReturnStmt Constructor)
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

        # Build params list (no $self for subs)
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

        my $prev_return_context = $self->_get_return_context();
        $self->_set_return_context($has_return);

        for my $idx (0 .. $body->@* - 1) {
            my $is_last = ($idx == $body->@* - 1);
            my $stmt = $self->_emit_xs_stmt($body->[$idx], \%declared_vars, $is_last);
            push @code, $stmt if defined $stmt;
        }

        if (!$last_is_return && @code) {
            my $last_code = $code[-1];
            if ($last_code =~ s/;\s*$//) {
                if ($last_code =~ /^sv_setsv\b/) {
                    # sv_setsv returns void — keep as statement, not retval
                    $code[-1] = "$last_code;";
                } else {
                    my $wrapped = $self->_wrap_retval($last_code);
                    $code[-1] = "retval = $wrapped;";
                    # We assigned to retval, so ensure the function returns it
                    $has_return = true;
                }
            }
        }

        $self->_set_return_context($prev_return_context);

        # Build the static helper function (no XSUB wrapper — internal only)
        my @helper;
        my $helper_name = "_impl_${slug}_${name}";
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

        return { helper => \@helper };
    }


    # Emit a single IR node as a C statement line.
    # $is_last indicates whether this is the final statement in the method body.
    method _emit_xs_stmt($node, $declared_vars, $is_last = true) {
        return undef unless defined $node;

        # Check cfg_state lookup for control flow dispatch
        if (%{$self->_get_cfg_lookup()} && ref($node)) {
            my $state = $self->_get_cfg_lookup()->{refaddr($node)};
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
            # Inside scoped loops (ENTER/SAVETMPS per iteration), must
            # FREETMPS/LEAVE before continue/break to avoid leaking the scope.
            if ($val eq 'next')   { return $self->_get_loop_depth() ? "{ FREETMPS; LEAVE; continue; }" : "continue;"; }
            if ($val eq 'last')   { return $self->_get_loop_depth() ? "{ FREETMPS; LEAVE; break; }" : "break;"; }
            if ($val eq 'return') { return "return;"; }
            return $self->_emit_xs_expr($node, $declared_vars) . ";";
        }

        return "/* unknown node */";
    }

    # Emit a C expression for an IR node
    method _emit_xs_expr($node, $declared_vars) {
        my $slug = $self->_get_current_slug();
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
            # $#$arrayref — last index of array referenced by scalar
            # IR value: $#$item_types → after sigil strip: #$item_types
            # Also handles $#array → after sigil strip: #array
            if ($var =~ /^#\$?(.+)/) {
                my $inner = $1;
                my $inner_expr;
                if ($declared_vars && $declared_vars->{$inner}) {
                    $inner_expr = "${inner}_sv";
                } elsif ($declared_vars && $declared_vars->{"param:$inner"}) {
                    $inner_expr = $inner;
                } elsif ($self->_get_field_map() && exists $self->_get_field_map()->{$inner}) {
                    my $idx = $self->_get_field_map()->{$inner};
                    $inner_expr = "ObjectFIELDS(SvRV(self))[$idx]";
                } else {
                    $inner_expr = "get_sv(\"${\$self->module_name()}::$inner\", GV_ADD)";
                }
                return "sv_2mortal(newSViv(av_len((AV*)SvRV($inner_expr))))";
            }
            # $self is the XS method receiver — use the C parameter directly
            if ($var eq 'self') {
                return 'self';
            }
            # Regex capture variables ($1, $2, ...) — fetch from package
            # globals set by _emit_xs_regex_match wrapper
            if ($var =~ /^\d+$/) {
                return "get_sv(\"::_c$var\", GV_ADD)";
            }
            # Class-scope static variable — check before declared_vars because
            # _collect_var_decls may create a local SV* for VarDecl in the
            # method body, but the actual shared value lives in the static.
            if (%{$self->_get_class_scope_vars()} && exists $self->_get_class_scope_vars()->{$var}) {
                my $info = $self->_get_class_scope_vars()->{$var};
                # Hash/array statics: return a mortal reference so SvRV()
                # in SubscriptExpr handler correctly unwraps to HV*/AV*.
                if ($info->{sigil} eq '%' || $info->{sigil} eq '@') {
                    return "sv_2mortal(newRV_inc((SV*)$info->{static_name}))";
                }
                return $info->{static_name};
            }
            if ($declared_vars && $declared_vars->{$var}) {
                return "${var}_sv";
            }
            # Method parameters are bare C variables (no _sv suffix)
            if ($declared_vars && $declared_vars->{"param:$var"}) {
                return $var;
            }
            # Field access: use ObjectFIELDS indexed access if this is a field
            if ($self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
                my $idx = $self->_get_field_map()->{$var};
                return "ObjectFIELDS(SvRV(self))[$idx]";
            }
            # Package global or unknown variable — use get_sv for package lookup
            my $escaped = $self->_escape_c_string($var);
            return "get_sv(\"${\$self->module_name()}::$escaped\", GV_ADD)";
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

        # qr// with interpolated variables — the C preprocessor doesn't do
        # Perl-style interpolation, so newSVpvs("qr/$var/") would produce
        # the literal string. Use eval_pv to compile at runtime instead.
        # Terminal::match accepts plain pattern strings, so strip qr//.
        if ($val =~ m{^qr/(.*)/\w*$}s) {
            my $body = $1;
            # Extract variable names from the pattern body
            my @parts;
            my $rest = $body;
            while ($rest =~ /\G(.*?)\$(\w+)/gcs) {
                my ($lit, $var) = ($1, $2);
                my $escaped_lit = $self->_escape_c_string($lit);
                push @parts, "sv_catpvs(_qr, \"$escaped_lit\")" if length $lit;
                # Resolve the variable to its C expression
                if (%{$self->_get_class_scope_vars()} && exists $self->_get_class_scope_vars()->{$var}) {
                    my $info = $self->_get_class_scope_vars()->{$var};
                    push @parts, "sv_catsv(_qr, (SV*)$info->{static_name})";
                } elsif ($declared_vars && $declared_vars->{$var}) {
                    push @parts, "sv_catsv(_qr, ${var}_sv)";
                } elsif ($declared_vars && $declared_vars->{"param:$var"}) {
                    push @parts, "sv_catsv(_qr, $var)";
                } elsif ($self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
                    my $idx = $self->_get_field_map()->{$var};
                    push @parts, "sv_catsv(_qr, ObjectFIELDS(SvRV(self))[$idx])";
                }
            }
            # Remaining literal after last variable
            my $tail = substr($body, pos($rest) // 0);
            if (length $tail) {
                my $escaped_tail = $self->_escape_c_string($tail);
                push @parts, "sv_catpvs(_qr, \"$escaped_tail\")";
            }

            if (@parts) {
                my $cat_ops = join('; ', @parts);
                return '({ SV *_qr = sv_2mortal(newSVpvs("")); ' . $cat_ops . '; _qr; })';
            }
        }

        # Resolve `use constant` names to their numeric values.
        # Without this, constants like STRUCT_IS_LIST become string literals
        # in the generated C, producing "isn't numeric" warnings and wrong results.
        if (%{$self->_get_use_constants()} && exists $self->_get_use_constants()->{$val}) {
            return "sv_2mortal(newSViv($self->_get_use_constants()->{$val}))";
        }

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
                } elsif (%{$self->_get_class_scope_vars()} && exists $self->_get_class_scope_vars()->{$var}) {
                    my $info = $self->_get_class_scope_vars()->{$var};
                    $src = ($info->{sigil} eq '%' || $info->{sigil} eq '@')
                        ? "(SV*)$info->{static_name}"
                        : $info->{static_name};
                } elsif ($declared_vars && $declared_vars->{$var}) {
                    $src = "${var}_sv ? ${var}_sv : &PL_sv_undef";
                } elsif ($declared_vars && $declared_vars->{"param:$var"}) {
                    $src = "$var ? $var : &PL_sv_undef";
                } elsif ($self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
                    my $idx = $self->_get_field_map()->{$var};
                    $src = "ObjectFIELDS(SvRV(self))[$idx]";
                } else {
                    my $escaped = $self->_escape_c_string($var);
                    $src = "get_sv(\"${\$self->module_name()}::$escaped\", GV_ADD)";
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
        # Short-circuit — evaluate $left once into temp to avoid double evaluation.
        # Cast non-SV* results (AV*/HV* from postfix deref) back to SV* so the
        # ternary always returns a uniform pointer type for the C compiler.
        my $sv_right = ($right =~ /^\((?:AV|HV)\*\)/) ? "(SV*)$right" : $right;
        my $sv_left  = ($left  =~ /^\((?:AV|HV)\*\)/) ? "(SV*)$left"  : $left;
        if ($op eq '&&' || $op eq 'and') { return "({ SV *_l = $sv_left; SvTRUE(_l) ? $sv_right : _l; })"; }
        if ($op eq '||' || $op eq 'or')  { return "({ SV *_l = $sv_left; SvTRUE(_l) ? _l : $sv_right; })"; }
        if ($op eq '//')                  { return "({ SV *_l = $sv_left; SvOK(_l) ? _l : $sv_right; })"; }

        # Numeric ops — sv_2mortal prevents leaks when used as sub-expressions
        if ($op eq '+')  { return "sv_2mortal(newSVnv(SvNV($left) + SvNV($right)))"; }
        if ($op eq '-')  { return "sv_2mortal(newSVnv(SvNV($left) - SvNV($right)))"; }
        if ($op eq '*')  { return "sv_2mortal(newSVnv(SvNV($left) * SvNV($right)))"; }
        if ($op eq '/')  { return "sv_2mortal(newSVnv(SvNV($left) / SvNV($right)))"; }
        if ($op eq '%')  { return "sv_2mortal(newSViv(SvIV($left) % SvIV($right)))"; }
        # Integer bitwise ops — used by Structural semiring for flag manipulation
        if ($op eq '|')  { return "sv_2mortal(newSViv(SvIV($left) | SvIV($right)))"; }
        if ($op eq '&')  { return "sv_2mortal(newSViv(SvIV($left) & SvIV($right)))"; }
        # String repetition — 'str' x $n
        if ($op eq 'x') {
            return "({ SV *_xs = $left; SV *_xn = $right; "
                . "STRLEN _xlen; const char *_xp = SvPV(_xs, _xlen); "
                . "IV _xc = SvIV(_xn); SV *_xr; "
                . "if (_xc < 1 || _xlen == 0) { _xr = sv_2mortal(newSVpvs(\"\")); } "
                . "else { _xr = sv_2mortal(newSV(_xlen * _xc + 1)); SvPOK_on(_xr); "
                . "repeatcpy(SvPVX(_xr), _xp, _xlen, _xc); "
                . "SvCUR_set(_xr, _xlen * _xc); *SvEND(_xr) = '\\0'; } _xr; })";
        }
        # Numeric comparison: use integer comparison when both operands are
        # IV/UV to avoid precision loss. SvNV on a 64-bit UV (e.g., from
        # refaddr/PTR2UV) can lose low bits since double has only 52-bit
        # mantissa, causing identity comparisons to fail.
        if ($op eq '==' || $op eq '!=' || $op eq '<' || $op eq '>'
                || $op eq '<=' || $op eq '>=') {
            my $c_op = $op;
            my $cmp = "(SvIOK($left) && SvIOK($right)"
                . " ? (SvUOK($left) || SvUOK($right)"
                .   " ? SvUV($left) $c_op SvUV($right)"
                .   " : SvIV($left) $c_op SvIV($right))"
                . " : SvNV($left) $c_op SvNV($right))";
            return "($cmp ? &PL_sv_yes : &PL_sv_no)";
        }

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
        my $slug = $self->_get_current_slug();
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

        # Direct call optimization: when invocant is self and method is in
        # the same class, call the static helper function directly instead
        # of going through Perl's method dispatch protocol.
        # All helpers return SV* (void methods return &PL_sv_undef), so the
        # call always produces a usable SV* value.
        if ($invocant_expr eq 'self' && defined $self->_get_class_methods()
                && defined $self->_get_class_methods()->{$method_name}) {
            my @call_args = ('aTHX_ self', @arg_exprs);
            my $call = "_impl_${slug}_${method_name}(" . join(', ', @call_args) . ")";
            if (@pre_eval) {
                my @stmts = (@pre_eval, $call);
                return '({ ' . join('; ', @stmts) . '; })';
            }
            return $call;
        }

        # Composite field dispatch: when invocant is $field->[$i] and $field has
        # composite_components with all components of a single known type,
        # emit _impl_SLUG_method(aTHX_ element, args) instead of call_method.
        # This replaces Perl method dispatch with a direct C call.
        if (defined $_composite_field_types && defined $invocant_node
                && $invocant_node isa Chalk::Bootstrap::IR::Node::Constructor
                && $invocant_node->class() eq 'SubscriptExpr') {
            my $target_node = $invocant_node->inputs()->[0];
            if (defined $target_node
                    && $target_node isa Chalk::Bootstrap::IR::Node::Constant) {
                my $val = $target_node->value();
                if ($val =~ /^[\$\@\%](.+)/) {
                    my $field_name = $1;
                    if (exists $_composite_field_types->{$field_name}) {
                        my $component_slugs = $_composite_field_types->{$field_name};
                        # Check all components are the same type (uniform dispatch)
                        my %unique_slugs;
                        $unique_slugs{$_} = 1 for $component_slugs->@*;
                        if (keys %unique_slugs == 1) {
                            my ($target_slug) = keys %unique_slugs;
                            # Verify the method exists and was compiled (not eval_pv fallback)
                            if (exists $_multi_class_methods{$target_slug}
                                    && exists $_multi_class_methods{$target_slug}{$method_name}
                                    && !exists $_fallback_method_slugs{"$target_slug:$method_name"}) {
                                my @call_args = ("aTHX_ $invocant_expr", @arg_exprs);
                                my $call = "_impl_${target_slug}_${method_name}(" . join(', ', @call_args) . ")";
                                if (@pre_eval) {
                                    my @stmts = (@pre_eval, $call);
                                    return '({ ' . join('; ', @stmts) . '; })';
                                }
                                return $call;
                            }
                        }
                    }
                }
            }
        }

        # Semiring intrinsic: when invocant is a field with intrinsics configured
        # and method is is_zero, emit a direct C call instead of Perl dispatch.
        # Eliminates the entire ENTER/SAVETMPS/call_sv/FREETMPS/LEAVE bridge.
        if ($method_name eq 'is_zero' && defined $_semiring_intrinsics
                && defined $invocant_node
                && $invocant_node isa Chalk::Bootstrap::IR::Node::Constant) {
            my $val = $invocant_node->value();
            if ($val =~ /^[\$\@\%](.+)/) {
                my $var = $1;
                if (defined $self->_get_field_map() && exists $self->_get_field_map()->{$var}
                        && exists $_semiring_intrinsics->{$var}) {
                    my $fidx = $self->_get_field_map()->{$var};
                    # The semiring field stores the FilterComposite; its _semirings
                    # arrayref is passed to _inline_is_zero for lazy Boolean zero init.
                    # We pass the field's _semirings (obtained via method call once,
                    # but the inline function caches it).
                    my $arg = $arg_exprs[0] // 'NULL';
                    my $intrinsic = "_inline_${slug}_is_zero(aTHX_ ObjectFIELDS(SvRV(self))[$fidx], $arg)";
                    # Wrap in GCC statement expression so _fixup_ternary_assignment
                    # can detect and rewrite ternary patterns that assign the result.
                    my $expr = "({ SV *_izr = ($intrinsic ? &PL_sv_yes : &PL_sv_no); _izr; })";
                    if (@pre_eval) {
                        my @stmts = (@pre_eval, $expr);
                        return '({ ' . join('; ', @stmts) . '; })';
                    }
                    return $expr;
                }
            }
        }

        # Unique method name dispatch: if only one compiled class defines this
        # method, emit a direct _impl_ call regardless of invocant type.
        # Safe for reader methods (children, position, rule, etc.) that are
        # unique to a single class like Context.
        if ($invocant_expr ne 'self') {
            my @matching_slugs;
            for my $slug (sort keys %_multi_class_methods) {
                if (exists $_multi_class_methods{$slug}{$method_name}
                        && !exists $_fallback_method_slugs{"$slug:$method_name"}) {
                    push @matching_slugs, $slug;
                }
            }
            if (@matching_slugs == 1) {
                my $target_slug = $matching_slugs[0];
                my @call_args = ("aTHX_ $invocant_expr", @arg_exprs);
                my $call = "_impl_${target_slug}_${method_name}(" . join(', ', @call_args) . ")";
                if (@pre_eval) {
                    my @stmts = (@pre_eval, $call);
                    return '({ ' . join('; ', @stmts) . '; })';
                }
                return $call;
            }
        }

        # Speculative inline for :param fields: when the invocant is a :param
        # field and we know the primary type from the class registry, emit a
        # stash check + direct _impl_ call. Falls back to call_method on mismatch.
        # This is a monomorphic inline cache — one pointer comparison per call.
        if ($invocant_expr ne 'self' && defined $invocant_node
                && $invocant_node isa Chalk::Bootstrap::IR::Node::Constant
                && defined $self->_get_param_fields()) {
            my $val = $invocant_node->value();
            if ($val =~ /^[\$\@\%](.+)/) {
                my $var = $1;
                if (exists $self->_get_param_fields()->{$var} && defined $self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
                    # Find which compiled classes define this method (excluding self).
                    # Prioritize the class from the `uses` registration for this field.
                    my @candidates;
                    for my $slug (sort keys %_multi_class_methods) {
                        next if $slug eq $self->_get_current_slug();
                        if (exists $_multi_class_methods{$slug}{$method_name}
                                && !exists $_fallback_method_slugs{"$slug:$method_name"}) {
                            push @candidates, $slug;
                        }
                    }
                    # Pick the best target: when there are multiple candidates,
                    # prefer the one registered as a `uses` dependency for this
                    # class (e.g., FilterComposite for Earley's $semiring).
                    if (@candidates >= 1) {
                        my $target_slug = $candidates[0];
                        if (defined $_class_registry && @candidates > 1) {
                            # Check the current class's uses deps for a better target
                            for my $cname ($_class_registry->all_classes()) {
                                my $reg = $_class_registry->resolve($cname);
                                next unless defined $reg && defined $reg->{uses};
                                my $cslug = $self->_class_slug($cname);
                                next unless $cslug eq $self->_get_current_slug();
                                for my $dep ($reg->{uses}->@*) {
                                    my $dep_slug = $self->_class_slug($dep);
                                    if (grep { $_ eq $dep_slug } @candidates) {
                                        $target_slug = $dep_slug;
                                        last;
                                    }
                                }
                                last;  # found current class entry, stop searching
                            }
                        }
                        my @call_args = ("aTHX_ $invocant_expr", @arg_exprs);
                        my $impl_call = "_impl_${target_slug}_${method_name}(" . join(', ', @call_args) . ")";
                        my $stash_var = "_stash_${target_slug}";

                        # Build call_method fallback as statement expression
                        my @cm_parts;
                        push @cm_parts, "dSP; ENTER; SAVETMPS; PUSHMARK(SP)";
                        push @cm_parts, "XPUSHs($invocant_expr)";
                        push @cm_parts, "XPUSHs($_)" for @arg_exprs;
                        push @cm_parts, "PUTBACK; call_method(\"$escaped_name\", G_SCALAR)";
                        push @cm_parts, "SPAGAIN; SV *_mcr = SvREFCNT_inc(POPs); PUTBACK";
                        push @cm_parts, "FREETMPS; LEAVE; _mcr";
                        my $cm_expr = '({ ' . join('; ', @cm_parts) . '; })';

                        my $expr = "({ SV *_inv = $invocant_expr; "
                            . "(SvROK(_inv) && SvOBJECT(SvRV(_inv)) && SvSTASH(SvRV(_inv)) == $stash_var) "
                            . "? $impl_call "
                            . ": $cm_expr; })";

                        if (@pre_eval) {
                            my @stmts = (@pre_eval, $expr);
                            return '({ ' . join('; ', @stmts) . '; })';
                        }
                        return $expr;
                    }
                }
            }
        }

        # CV cache optimization: when invocant is a field variable and method
        # name is cached, use lazy-resolved call_sv instead of call_method.
        # Eliminates per-call gv_fetchmethod_autoload + @ISA walk overhead.
        my $cv_cache_key;
        if (defined $_cv_cache && defined $invocant_node
                && $invocant_node isa Chalk::Bootstrap::IR::Node::Constant) {
            my $val = $invocant_node->value();
            if ($val =~ /^[\$\@\%](.+)/) {
                my $var = $1;
                my $key = "${var}_${method_name}";
                if (exists $_cv_cache->{$key}) {
                    $cv_cache_key = $key;
                }
            }
        }

        my @stmts;
        push @stmts, @pre_eval;

        if (defined $cv_cache_key) {
            # Lazy-resolve CV on first call, then use call_sv for dispatch
            my $field_idx = $_cv_cache->{$cv_cache_key}{field_idx};
            my $cv_var = "_cv_${slug}_${cv_cache_key}";
            push @stmts, "if (!${cv_var}) { GV *_gv = gv_fetchmethod_autoload(SvSTASH(SvRV(ObjectFIELDS(SvRV(self))[$field_idx])), \"$escaped_name\", TRUE); if (_gv) ${cv_var} = GvCV(_gv); }";
            push @stmts, 'dSP';
            push @stmts, 'ENTER; SAVETMPS';
            push @stmts, 'PUSHMARK(SP)';
            push @stmts, "XPUSHs($invocant_expr)";
            for my $expr (@arg_exprs) {
                push @stmts, "XPUSHs($expr)";
            }
            push @stmts, 'PUTBACK';
            push @stmts, "call_sv((SV*)${cv_var}, G_SCALAR)";
            push @stmts, 'SPAGAIN';
            push @stmts, 'SV *_mcr = SvREFCNT_inc(POPs)';
            push @stmts, 'PUTBACK; FREETMPS; LEAVE';
            push @stmts, '_mcr';
        } else {
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
        }

        return '({ ' . join('; ', @stmts) . '; })';
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

        # Handle stale-merge parse artifact: return [EXPR] is parsed as
        # SubscriptExpr("return", EXPR, "array") instead of ReturnStmt([EXPR]).
        # The inner EXPR (e.g., map builtin) already produces the array content,
        # so emit it directly — the map handler wraps results in newRV_noinc(AV*).
        if ($style eq 'array'
                && defined $target
                && $target isa Chalk::Bootstrap::IR::Node::Constant
                && $target->value() eq 'return') {
            return $self->_emit_xs_expr($index, $declared_vars);
        }

        # Coderef call: $f->($arg1, $arg2) — emit call_sv with arguments.
        if ($style eq 'call') {
            my $tgt = defined $target
                ? $self->_emit_xs_expr($target, $declared_vars)
                : 'self';
            my @push_stmts;
            if (ref($index) eq 'ARRAY') {
                for my $arg ($index->@*) {
                    my $arg_expr = $self->_emit_xs_expr($arg, $declared_vars);
                    push @push_stmts, "XPUSHs($arg_expr)";
                }
            } elsif (defined $index) {
                my $arg_expr = $self->_emit_xs_expr($index, $declared_vars);
                push @push_stmts, "XPUSHs($arg_expr)";
            }
            my $pushes = join('; ', @push_stmts);
            $pushes = " $pushes; " if $pushes;
            return "({ dSP; ENTER; SAVETMPS; PUSHMARK(SP);${pushes}PUTBACK; "
                 . "call_sv($tgt, G_SCALAR); SPAGAIN; SV *_cr = SvREFCNT_inc(POPs); "
                 . "PUTBACK; FREETMPS; LEAVE; _cr; })";
        }

        # Fallback for undef index (legacy IR from before "call" style was added)
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

        # Built-in Perl hash variables (%ENV, %SIG, %INC) are compiled by
        # _emit_xs_const_expr as get_sv (scalar lookup), but subscript access
        # needs get_hv (hash lookup). Detect and fix: wrap get_hv result in a
        # reference so the SvRV dereference below works correctly.
        if ($style eq 'hash' && defined $target) {
            my $is_const = $target isa Chalk::Bootstrap::IR::Node::Constant;
            if ($is_const) {
                my $var_name = $target->value();
                if ($var_name =~ /\A(ENV|SIG|INC)\z/) {
                    $tgt = "sv_2mortal(newRV_inc((SV*)get_hv(\"$1\", 0)))";
                }
            }
            # Also check if tgt string contains get_sv for a known hash var
            if ($tgt =~ /get_sv\("[^"]*::(ENV|SIG|INC)"/) {
                $tgt = "sv_2mortal(newRV_inc((SV*)get_hv(\"$1\", 0)))";
            }
        }

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
                if (exists $declared_vars->{"param:$src_var"}) {
                    $src_expr = $src_var;
                } elsif (exists $declared_vars->{$src_var}) {
                    $src_expr = "${src_var}_sv";
                } elsif (defined $self->_get_field_map() && exists $self->_get_field_map()->{$src_var}) {
                    $src_expr = "ObjectFIELDS(SvRV(self))[$self->_get_field_map()->{$src_var}]";
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

    # Compile anonymous sub as a static C function with a CV wrapper.
    # The body is compiled to native C just like regular methods. A CV
    # is created via newXS in the BOOT block so call_sv can dispatch to it.
    # The CV is cached in a static SV* for zero-overhead repeated use.
    method _emit_xs_anon_sub_expr($node, $declared_vars) {
        my $slug = $self->_get_current_slug();
        my $params_node = $node->inputs()->[0];
        my $body_items  = $node->inputs()->[1] // [];

        my $idx = $_anon_sub_counter++;
        my $fn_name = "_anon_${slug}_${idx}";
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
                $c = $self->_emit_xs_expr($stmt, \%anon_vars);
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

            # Forward-declare the CV cache and register in BOOT
            push @_anon_sub_fwd_decls, "static SV *${cv_var} = NULL;";

            push @_anon_sub_boot, "    ${cv_var} = (SV*)newXS(\"::${fn_name}\", XS_${fn_name}, __FILE__);";
            push @_anon_sub_boot, "    SvREFCNT_inc(${cv_var});";

            return $cv_var;
        }

        # Fallback: compile via eval_pv if body compilation fails
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $perl_src = $perl_target->_emit_anon_sub_expr($node);
        my $prefix = 'use feature "signatures"; no warnings "experimental::signatures"; ';
        my $escaped = $self->_escape_c_string($prefix . $perl_src);
        return "eval_pv(\"$escaped\", TRUE)";
    }

    # Emit regex match using native Perl regex C API (pregcomp/pregexec).
    # Compiles the regex once into a static REGEXP* and reuses it.
    # None of the regex patterns used in this codebase have capture groups,
    # so captures are not extracted (the capture-saving boilerplate was dead code).
    method _emit_xs_regex_match($node, $declared_vars) {
        my $target  = $node->inputs()->[0];
        my $pattern = $node->inputs()->[1]->value();

        # Extract the raw regex and flags from the pattern (e.g., /foo/i, m{bar}x)
        my ($raw_pat, $flags);
        if ($pattern =~ m{^m\{(.*)\}([msixpodualngcer]*)$}s) {
            ($raw_pat, $flags) = ($1, $2);
        } elsif ($pattern =~ m{^/(.*)/([msixpodualngcer]*)$}s) {
            ($raw_pat, $flags) = ($1, $2);
        }

        if (!defined $raw_pat) {
            # Unrecognized pattern format — fall back to eval_pv
            my $match_perl = '$_ =~ ' . $pattern
                . ' and do { $::_c1=$1; $::_c2=$2; $::_c3=$3; 1 }';
            my $escaped = $self->_escape_c_string($match_perl);
            if (defined $target) {
                my $tgt = $self->_emit_xs_expr($target, $declared_vars);
                return "({ sv_setsv(DEFSV, $tgt); eval_pv(\"$escaped\", TRUE); })";
            }
            return "eval_pv(\"$escaped\", TRUE)";
        }

        # Build a unique static variable name for the compiled regex
        
        my $rx_var = "_rx_" . $self->_inc_regex_counter();

        # Wrap flags as inline modifiers: pattern → (?flags:pattern)
        my $full_pat = length($flags) ? "(?$flags:$raw_pat)" : $raw_pat;

        # Escape the pattern for C string literal
        my $c_pat = $self->_escape_c_string($full_pat);

        # Store regex patterns to declare as statics at top of generated file
        
        $self->_push_regex_static({
            var   => $rx_var,
            pat   => $c_pat,
        });

        my $tgt;
        if (defined $target) {
            $tgt = $self->_emit_xs_expr($target, $declared_vars);
        }

        # Emit pregexec call with lazy compilation.
        # Pattern SV is freed after pregcomp since pregcomp copies it internally.
        my $tgt_expr = defined $tgt ? $tgt : 'DEFSV';
        return "({ "
            . "if (!$rx_var) { SV *_pat_sv = newSVpvs(\"$c_pat\"); $rx_var = pregcomp(_pat_sv, 0); SvREFCNT_dec(_pat_sv); } "
            . "STRLEN _rxl; char *_rxs = SvPV($tgt_expr, _rxl); "
            . "(pregexec($rx_var, _rxs, _rxs + _rxl, _rxs, 0, $tgt_expr, 1)) "
            . "? &PL_sv_yes : &PL_sv_no; })";
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
        my $slug = $self->_get_current_slug();
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

        # refaddr() — return the pointer value of the referent as UV
        # Guard with SvROK check: Perl's refaddr() returns undef for non-refs.
        # Without this, SvRV on a non-reference (e.g. true/false) segfaults.
        if ($name eq 'refaddr' && $args->@* == 1) {
            my $arg = $self->_emit_xs_expr($args->[0], $declared_vars);
            return "(SvROK($arg) ? sv_2mortal(newSVuv(PTR2UV(SvRV($arg)))) : &PL_sv_undef)";
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
                # push @arr, reverse @src — iterate source backwards, push each element
                if ($val_name eq 'reverse') {
                    my $val_args = $val_node->inputs()->[1];
                    my $src_expr = $self->_emit_xs_expr($val_args->[0], $declared_vars);
                    my $src_av;
                    if ($val_args->[0] isa Chalk::Bootstrap::IR::Node::Constructor
                            && $val_args->[0]->class() eq 'PostfixDerefExpr') {
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

        # join — native C via sv_catsv
        if ($name eq 'join' && $args->@* >= 2) {
            my $sep = $self->_emit_xs_expr($args->[0], $declared_vars);
            if ($args->@* == 2) {
                # join($sep, @array) — iterate over arrayref
                my $arr = $self->_emit_xs_expr($args->[1], $declared_vars);
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
                my @c_args = map { $self->_emit_xs_expr($_, $declared_vars) } $args->@[1 .. $args->$#*];
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
            my $arg = $self->_emit_xs_expr($args->[0], $declared_vars);
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
            my $arg = $self->_emit_xs_expr($args->[0], $declared_vars);
            return "sv_2mortal(newSViv(sv_len_utf8($arg)))";
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

        # pop(@arr) — native array pop via av_pop
        if ($name eq 'pop' && $args->@* == 1) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_xs_expr($arr_node, $declared_vars);
            my $av_expr;
            if ($arr_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $arr_node->class() eq 'PostfixDerefExpr') {
                $av_expr = $arr;
            } else {
                $av_expr = "(AV*)SvRV($arr)";
            }
            return "av_pop($av_expr)";
        }

        # reverse(@arr) — reverse an array into a new AV
        if ($name eq 'reverse' && $args->@* == 1) {
            my $arr_node = $args->[0];
            my $arr = $self->_emit_xs_expr($arr_node, $declared_vars);
            my $av_expr;
            if ($arr_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $arr_node->class() eq 'PostfixDerefExpr') {
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
        # to sort/map/grep, the caller invokes _emit_xs_keys_list directly.
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

        # sort — bare sort (no block) using sortsv with sv_cmp
        if ($name eq 'sort' && $args->@* == 1) {
            my $list_node = $args->[0];
            # Detect sort keys %$hash — emit keys as list, then sort
            my $list_expr;
            if ($list_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $list_node->class() eq 'BuiltinCall'
                    && $list_node->inputs()->[0]->value() eq 'keys') {
                $list_expr = $self->_emit_xs_keys_list($list_node->inputs()->[1]->[0], $declared_vars);
            } else {
                $list_expr = $self->_emit_xs_expr($list_node, $declared_vars);
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
                    if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                            && $stmt->class() eq 'VarDecl') {
                        my $vname = $stmt->inputs()->[0]->value() =~ s/^\$//r;
                        $map_vars{$vname} = 1;
                        my $init = $self->_emit_xs_expr($stmt->inputs()->[1], \%map_vars);
                        push @block_stmts, "SV *${vname}_sv = $init";
                    } else {
                        push @block_stmts, $self->_emit_xs_expr($stmt, \%map_vars);
                    }
                }
                $block_body = '({ ' . join('; ', @block_stmts) . '; })';
            } elsif (defined $block_node && $block_node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $block_node->class() eq 'AnonSubExpr') {
                my $body = $block_node->inputs()->[1] // [];
                if ($body->@* > 1) {
                    # Multi-statement block: emit all stmts as compound statement expr.
                    # VarDecl items declare local C variables; last item is the return value.
                    $needs_topic_binding = true;
                    my %map_vars = ($declared_vars ? $declared_vars->%* : ());
                    $map_vars{'_'} = 1;
                    my @block_stmts;
                    for my $stmt ($body->@*) {
                        if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                                && $stmt->class() eq 'VarDecl') {
                            my $vname = $stmt->inputs()->[0]->value() =~ s/^\$//r;
                            $map_vars{$vname} = 1;
                            my $init = $self->_emit_xs_expr($stmt->inputs()->[1], \%map_vars);
                            push @block_stmts, "SV *${vname}_sv = $init";
                        } else {
                            push @block_stmts, $self->_emit_xs_expr($stmt, \%map_vars);
                        }
                    }
                    $block_body = '({ ' . join('; ', @block_stmts) . '; })';
                } elsif ($body->@*) {
                    $block_body = $self->_emit_xs_expr($body->[-1], $declared_vars);
                }
            } elsif (defined $block_node) {
                # Bare expression block: bind $_ (topic) to current element
                $needs_topic_binding = true;
                my $topic_vars = { ($declared_vars ? $declared_vars->%* : ()), '_' => 1 };
                $block_body = $self->_emit_xs_expr($block_node, $topic_vars);
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
                my $range_left  = $self->_emit_xs_expr($list_node->inputs()->[1], $declared_vars);
                my $range_right = $self->_emit_xs_expr($list_node->inputs()->[2], $declared_vars);
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
            my $list_expr = $self->_emit_xs_expr($list_node, $declared_vars);
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

        # substr — character-correct extraction
        # For UTF-8 strings, byte offsets differ from character offsets.
        # Use sv_pos_u2b to convert character offset/length to byte offset/length.
        if ($name eq 'substr' && $args->@* >= 2) {
            my $str = $self->_emit_xs_expr($args->[0], $declared_vars);
            my $off = $self->_emit_xs_expr($args->[1], $declared_vars);
            if ($args->@* >= 3) {
                my $len = $self->_emit_xs_expr($args->[2], $declared_vars);
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

        # Check if this is a call to a known class-scope sub.
        # Compiled subs get direct _impl_ C calls.
        # Uncompiled subs get call_pv with the FQ package name (not eval_pv).
        if (%{$self->_get_class_subs()} && exists $self->_get_class_subs()->{$name}) {
            my @c_args;
            for my $arg ($args->@*) {
                push @c_args, $self->_emit_xs_expr($arg, $declared_vars);
            }

            if ($self->_get_class_subs()->{$name}{compiled}) {
                # Direct C call to compiled helper
                my $helper_name = "_impl_${slug}_${name}";
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
    method _emit_xs_keys_list($hash_node, $declared_vars) {
        my $hash = $self->_emit_xs_expr($hash_node, $declared_vars);
        my $hv_expr;
        if ($hash_node isa Chalk::Bootstrap::IR::Node::Constructor
                && $hash_node->class() eq 'PostfixDerefExpr') {
            $hv_expr = $hash;
        } else {
            $hv_expr = "(HV*)SvRV($hash)";
        }
        return "({ HV *_khv = $hv_expr; HE *_khe; I32 _klen = HvUSEDKEYS(_khv); "
            . "AV *_kav = newAV(); av_extend(_kav, _klen - 1); "
            . "hv_iterinit(_khv); "
            . "while ((_khe = hv_iternext(_khv))) { "
            .   "av_push(_kav, newSVhek(HeKEY_hek(_khe))); "
            . "} "
            . "newRV_noinc((SV*)_kav); })";
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
        if (defined $self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
            my $idx = $self->_get_field_map()->{$var};
            my $accessor = "ObjectFIELDS(SvRV(self))[$idx]";
            if (defined $init) {
                my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
                return "({ sv_setsv($accessor, $init_expr); $accessor; })";
            }
            return "({ sv_setsv($accessor, &PL_sv_undef); $accessor; })";
        }

        # Class-scope variables in expression context: evaluate init (if any)
        # and return the static. Statement-level resets (hv_clear etc.) are
        # handled by _emit_xs_var_decl.
        if (%{$self->_get_class_scope_vars()} && exists $self->_get_class_scope_vars()->{$var}) {
            my $info = $self->_get_class_scope_vars()->{$var};
            if (defined $init) {
                my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
                return "({ $init_expr; $info->{static_name}; })";
            }
            return $info->{static_name};
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
            if (defined $self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
                my $idx = $self->_get_field_map()->{$var};
                my $fs = $self->_get_field_sigils() ? ($self->_get_field_sigils()->{$var} // '$') : '$';
                if ($fs eq '%') {
                    $this_stmt = "hv_clear((HV*)ObjectFIELDS(SvRV(self))[$idx]);";
                } elsif ($fs eq '@') {
                    $this_stmt = "av_clear((AV*)ObjectFIELDS(SvRV(self))[$idx]);";
                } else {
                    $this_stmt = "sv_setsv(ObjectFIELDS(SvRV(self))[$idx], $default_val);";
                }
            } elsif (%{$self->_get_class_scope_vars()} && exists $self->_get_class_scope_vars()->{$var}) {
                my $csv_info = $self->_get_class_scope_vars()->{$var};
                my $csv_sname = $csv_info->{static_name};
                if ($csv_info->{sigil} eq '%') {
                    $this_stmt = "({ hv_clear($csv_sname); (SV*)$csv_sname; });";
                } elsif ($csv_info->{sigil} eq '@') {
                    $this_stmt = "({ av_clear($csv_sname); (SV*)$csv_sname; });";
                } else {
                    $this_stmt = "({ sv_setsv($csv_sname, $default_val); $csv_sname; });";
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
        if (defined $self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
            my $idx = $self->_get_field_map()->{$var};
            my $fs = $self->_get_field_sigils() ? ($self->_get_field_sigils()->{$var} // '$') : '$';
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

        # Class-scope variables: method-body VarDecl emits the real
        # operation on the static (e.g. hv_clear for %hash = ()).
        # Uses statement-expression form so the result is usable as a
        # return value when this is the last statement in a method body.
        if (%{$self->_get_class_scope_vars()} && exists $self->_get_class_scope_vars()->{$var}) {
            my $info = $self->_get_class_scope_vars()->{$var};
            my $sname = $info->{static_name};
            if (defined $init) {
                my $init_expr = $self->_emit_xs_expr($init, $declared_vars);
                return "({ sv_setsv($sname, $init_expr); (SV*)$sname; });";
            }
            # No init = reset to empty: %hash = () or @array = () or $scalar = undef
            if ($info->{sigil} eq '%') {
                return "({ hv_clear($sname); (SV*)$sname; });";
            } elsif ($info->{sigil} eq '@') {
                return "({ av_clear($sname); (SV*)$sname; });";
            } else {
                return "({ sv_setsv($sname, &PL_sv_undef); $sname; });";
            }
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
            # Array variable declared with a scalar init (e.g., my @stack = ($self)):
            # wrap the scalar in a fresh AV ref. Without this, the variable aliases
            # the init SV directly, and av_push/av_pop on it corrupt the original.
            # Skip if the init already produces an array ref (newRV, newAV patterns).
            if (defined $sigil && $sigil eq '@'
                    && $init_expr !~ /newRV_noinc/
                    && $init_expr !~ /newAV\(\)/) {
                $init_expr = "({ AV *_av = newAV(); av_push(_av, SvREFCNT_inc($init_expr)); newRV_noinc((SV*)_av); })";
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
    # SvREFCNT_inc ensures proper ownership for borrowed references:
    # The OUTPUT section mortalises RETVAL (decrements refcount), so we
    # must increment to avoid freeing SVs still stored in containers.
    # For new* values (newSViv, newRV_noinc, etc.) the refcount is already
    # 1, so the mortalisation correctly consumes it. SvREFCNT_inc on these
    # would leak. To handle both cases, we skip SvREFCNT_inc for values
    # that are clearly newly-created (start with 'new' or '&PL_sv_').
    method _emit_xs_return_stmt($node, $declared_vars, $is_last = true) {
        my $value = $node->inputs()->[0];
        my $val_expr = $self->_emit_xs_expr($value, $declared_vars);
        $val_expr =~ s/^sv_2mortal\((.+)\)$/$1/;
        my $retval = $self->_wrap_retval($val_expr);
        if ($is_last) {
            return "RETVAL = $retval;";
        }
        # Inside scoped loops, unwind ENTER/SAVETMPS scopes before goto
        my $unwind = "FREETMPS; LEAVE; " x $self->_get_loop_depth();
        return "${unwind}RETVAL = $retval; goto xsreturn;";
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
    # Wrap a C expression in SvTRUE(), casting to (SV*) when the
    # expression produces AV* or HV* (e.g. from postfix deref ->@*).
    # SvTRUE requires SV* — passing AV*/HV* directly is a C type error.
    my sub _sv_true_wrap($expr) {
        if ($expr =~ /^\(AV\*\)/ || $expr =~ /^\(HV\*\)/) {
            return "SvTRUE((SV*)$expr)";
        }
        return "SvTRUE($expr)";
    }

    # The If node's condition is already the correct test (negated for unless).
    # 'next' maps to C 'continue', 'last' maps to C 'break'.
    method _emit_xs_loop_jump($jump_keyword, $if_node, $declared_vars) {
        my $cond = $if_node->inputs()->[1];
        my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
        my $c_keyword = $jump_keyword eq 'last' ? 'break' : 'continue';
        # Inside scoped loops (ENTER/SAVETMPS per iteration), must
        # FREETMPS/LEAVE before continue/break to avoid leaking the scope.
        my $sv_cond = _sv_true_wrap($cond_expr);
        if ($self->_get_loop_depth()) {
            return "if ($sv_cond) { FREETMPS; LEAVE; $c_keyword; }";
        }
        return "if ($sv_cond) $c_keyword;";
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
        push @lines, "$prefix (" . _sv_true_wrap($cond_expr) . ") {";
        for my $idx (0 .. $true_stmts->@* - 1) {
            my $stmt = $true_stmts->[$idx];
            my $is_last_in_then = ($idx == $true_stmts->@* - 1);
            # Stale-merge can strip ReturnStmt leaving a bare expression.
            # When in return context (method has returns), detect the last
            # bare expression and emit it as RETVAL assignment + goto.
            # Inside loops, MethodCallExpr at tail is likely a void side-effect
            # (e.g., _complete()), not a return value. Only allow unambiguous
            # value expressions (SubscriptExpr, TernaryExpr) inside loops.
            my $is_loop_safe_return = !$self->_get_loop_depth()
                || ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && ($stmt->class() eq 'SubscriptExpr'
                        || $stmt->class() eq 'TernaryExpr'));
            if ($self->_get_return_context() && $is_loop_safe_return && $is_last_in_then
                    && $self->_is_bare_return_expr($stmt)) {
                my $val_expr = $self->_emit_xs_expr($stmt, $declared_vars);
                $val_expr =~ s/^sv_2mortal\((.+)\)$/$1/;
                my $wrapped = $self->_wrap_retval($val_expr);
                # Inside scoped loops, unwind ENTER/SAVETMPS scopes before goto
                my $unwind = "FREETMPS; LEAVE; " x $self->_get_loop_depth();
                push @lines, "    ${unwind}RETVAL = $wrapped; goto xsreturn;";
                next;
            }
            my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
            push @lines, "    $code" if defined $code;
        }
        if ($false_stmts->@*) {
            # Detect elsif: single If CFG node in else branch
            if (scalar $false_stmts->@* == 1
                    && ref($false_stmts->[0])
                    && %{$self->_get_cfg_lookup()}) {
                my $elsif_state = $self->_get_cfg_lookup()->{refaddr($false_stmts->[0])};
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
        push @lines, "if (" . _sv_true_wrap($cond_expr) . ") {";
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

            # Scope boundary frees mortal SVs per iteration instead of per-function
            push @lines, "        ENTER; SAVETMPS;";
            $self->_inc_loop_depth();
            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
                push @lines, "        $code" if defined $code;
            }
            $self->_dec_loop_depth();
            push @lines, "        FREETMPS; LEAVE;";
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
                    push @lines, "while (" . _sv_true_wrap($cond_expr) . ") {";
                }
            # Detect while (@array): array variable in boolean context
            # should check element count, not SvTRUE (which is always true
            # for a reference). Emit av_len >= 0 for proper empty-array check.
            } elsif ($cond isa Chalk::Bootstrap::IR::Node::Constant
                    && $cond->value() =~ /^\@/) {
                my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
                push @lines, "while (av_len((AV*)SvRV($cond_expr)) >= 0) {";
            } else {
                my $cond_expr = $self->_emit_xs_expr($cond, $declared_vars);
                push @lines, "while (" . _sv_true_wrap($cond_expr) . ") {";
            }

            # Scope boundary frees mortal SVs per iteration instead of per-function
            push @lines, "    ENTER; SAVETMPS;";
            $self->_inc_loop_depth();
            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_xs_stmt($stmt, $declared_vars, false);
                push @lines, "    $code" if defined $code;
            }
            $self->_dec_loop_depth();
            push @lines, "    FREETMPS; LEAVE;";
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
                # Inject chart re-read: the Perl source re-reads item/alt_idx from
                # the chart after the processed check, to get the merged value instead
                # of a stale agenda entry. The IR loses this list assignment entirely.
                # Detect: processed_sv assignment followed later by _is_complete call,
                # with chart_sv/pos_sv/core_id_sv/origin_sv available.
                if ($body_code =~ /processed_sv.*PL_sv_yes/ && $body_code =~ /call_method\("_is_complete"/) {
                    my @new_lines;
                    for my $line (@lines) {
                        if ($line =~ /call_method\("_is_complete"/ && $line !~ /_reread/) {
                            # Inject chart re-read before _is_complete
                            push @new_lines, '    { SV *_reread = ({ dSP; ENTER; SAVETMPS; PUSHMARK(SP); XPUSHs(self); XPUSHs(chart_sv); XPUSHs(pos_sv); XPUSHs(core_id_sv); XPUSHs(origin_sv); PUTBACK; call_method("_chart_get", G_SCALAR); SPAGAIN; SV *_mcr = SvREFCNT_inc(POPs); PUTBACK; FREETMPS; LEAVE; _mcr; }); item_sv = (*av_fetch((AV*)SvRV(_reread), 0, 0)); alt_idx_sv = (*av_fetch((AV*)SvRV(_reread), 1, 0)); }';
                        }
                        push @new_lines, $line;
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
                if ($self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
                    my $idx = $self->_get_field_map()->{$var};
                    $src = "ObjectFIELDS(SvRV(self))[$idx]";
                } else {
                    # Fallback for non-field variables (shouldn't happen in simple cases)
                    my $escaped = $self->_escape_c_string($var);
                    $src = "get_sv(\"${\$self->module_name()}::$escaped\", GV_ADD)";
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

    # Emit the .pm stub using dl_* API for XS loading
    method _emit_pm_stub($ir) {
        my @lines;
        push @lines, "# Generated by Chalk::Bootstrap compiler";
        push @lines, 'use 5.42.0;';
        push @lines, 'use utf8;';
        push @lines, "package " . $self->module_name() . ";";
        push @lines, 'use strict;';
        push @lines, 'use warnings;';
        push @lines, 'require DynaLoader;';
        push @lines, '';

        # Use raw dl_* API to bypass XSLoader's @ISA pollution
        # which conflicts with feature class sealed stashes

        # Compute .so path: auto/Foo/Bar/Baz/Baz.so for Foo::Bar::Baz
        my $dir_path = $self->module_name();
        $dir_path =~ s/::/\//g;
        my $filename = $self->module_name();
        $filename =~ s/^.*:://;  # Get last component
        my $so_rel_path = "auto/$dir_path/$filename.so";

        my $boot_name = $self->module_name();
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
        push @lines, "DynaLoader::dl_install_xsub('" . $self->module_name() . "::_bootstrap', \$boot, \$so);";
        push @lines, $self->module_name() . "->_bootstrap();";
        push @lines, '';
        push @lines, '1;';

        return join("\n", @lines) . "\n";
    }

    # Emit .pm stub with require statements for pure-Perl runtime deps.
    # Scans the generated XS content for call_pv targets and emits require
    # for any packages not in the compiled class set.
    method _emit_pm_stub_with_deps($xs_content, $compiled_classes) {
        my %compiled = map { $_ => 1 } $compiled_classes->@*;

        # Extract package names from call_pv("Package::Name::func", ...) patterns
        my %runtime_deps;
        while ($xs_content =~ /call_pv\("([^"]+)"/g) {
            my $fqn = $1;
            # Strip trailing function name to get package
            my $pkg = $fqn;
            $pkg =~ s/::[^:]+$//;
            next if $compiled{$pkg};
            $runtime_deps{$pkg} = 1;
        }

        # Also check for newSVpvs("Package::Name") + call_method patterns
        # that reference uncompiled Chalk packages
        while ($xs_content =~ /newSVpvs?\("(Chalk::[^"]+)"\)/g) {
            my $pkg = $1;
            next if $compiled{$pkg};
            next if $pkg =~ /::[a-z]/;  # Skip if looks like a method/sub name
            $runtime_deps{$pkg} = 1;
        }

        my @lines;
        push @lines, "# Generated by Chalk::Bootstrap compiler";
        push @lines, 'use 5.42.0;';
        push @lines, 'use utf8;';
        push @lines, "package " . $self->module_name() . ";";
        push @lines, 'use strict;';
        push @lines, 'use warnings;';
        push @lines, 'require DynaLoader;';
        push @lines, '';

        # Require pure-Perl runtime deps before loading XS
        if (keys %runtime_deps) {
            push @lines, '# Pure-Perl runtime dependencies (called via call_pv from XS)';
            for my $dep (sort keys %runtime_deps) {
                push @lines, "require $dep;";
            }
            push @lines, '';
        }

        # .so loading (same as _emit_pm_stub)
        my $dir_path = $self->module_name();
        $dir_path =~ s/::/\//g;
        my $filename = $self->module_name();
        $filename =~ s/^.*:://;
        my $so_rel_path = "auto/$dir_path/$filename.so";

        my $boot_name = $self->module_name();
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
        push @lines, "DynaLoader::dl_install_xsub('" . $self->module_name() . "::_bootstrap', \$boot, \$so);";
        push @lines, $self->module_name() . "->_bootstrap();";
        push @lines, '';
        push @lines, '1;';

        return join("\n", @lines) . "\n";
    }

    # Emit Build.PL
    method _emit_build_pl() {
        my $xs_path = $self->_module_path_prefix() . '.xs';
        my $lib_path = $self->_module_path_prefix();
        my $mn = $self->module_name();
        return qq[use Module::Build;

Module::Build->new(
    module_name    => '$mn',
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

# ABOUTME: Shared helper methods for C and XS code emitters extracted from Target::C.
# ABOUTME: Provides IR analysis, fixup utilities, and CFG emission shared by code generation targets.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::Perl::Target::EmitHelpers {
    field $field_map;          # hashref: field name => index (set during analysis)
    field $field_sigils;       # hashref: field name => sigil ($, @, %) (set during analysis)
    field %_cfg_lookup;        # IR node refaddr => cfg_state entry, built by generate_*
    field $_return_context = false;  # true when emitting a method body that returns a value
    field $_loop_depth = 0;          # nesting depth inside loops (suppresses bare-return detection)
    field $_class_methods;     # hashref: name => { returns => bool, params => \@param_names }
    field %_class_scope_vars;  # var_name => { sigil, init, static_name } for class-level lexicals
    field %_class_subs;        # sub_name => { params => [...], is_sub => 1 } for class-scope sub declarations
    field $_current_slug = ''; # class-derived identifier prefix for collision avoidance
    field $_param_fields;      # hashref: field_name => 1 for :param fields (type varies per instance)
    field $_sa;                # stored SemanticAction for emit_from_cfg_state access
    field $_ctx;               # stored Context for emit_from_cfg_state access

    # Accessor methods for shared state fields.
    # C.pm's subclass methods use these to read and write fields that
    # the shared helper methods (defined here) need during code generation.
    # Getters allow C-specific emit methods to read state set by helpers.
    # Setters allow C.pm's _analyze_class and generate_c_files to initialize state.
    method _get_field_map()           { return $field_map; }
    method _set_field_map($val)       { $field_map = $val; }
    method _get_current_slug()        { return $_current_slug; }
    method _set_current_slug($val)    { $_current_slug = $val; }
    method _set_class_methods($val)   { $_class_methods = $val; }
    method _get_class_scope_vars()    { return \%_class_scope_vars; }
    method _reset_class_scope_vars()  { %_class_scope_vars = (); }
    method _set_class_scope_var($key, $val) { $_class_scope_vars{$key} = $val; }
    method _get_class_subs()          { return \%_class_subs; }
    method _reset_class_subs()        { %_class_subs = (); }
    method _set_class_sub_compiled($name, $val) { $_class_subs{$name}{compiled} = $val; }
    method _get_cfg_lookup()          { return \%_cfg_lookup; }
    method _reset_cfg_lookup()        { %_cfg_lookup = (); }
    method _set_sa($val)              { $_sa = $val; }
    method _set_ctx($val)             { $_ctx = $val; }
    method _get_return_context()      { return $_return_context; }
    method _set_return_context($val)  { $_return_context = $val; }
    method _get_loop_depth()          { return $_loop_depth; }
    method _get_field_sigils()        { return $field_sigils; }
    method _get_param_fields()        { return $_param_fields; }

    # Derive a short lowercase slug from a class name for identifier namespacing.
    # Takes the last component of a qualified name and lowercases it.
    # e.g., "Chalk::Bootstrap::Earley" => "earley", "SlugTest" => "slugtest"
    method _class_slug($class_name) {
        my ($last) = $class_name =~ /(?:.*::)?(\w+)$/;
        return lc($last // $class_name);
    }

    # Map a TypeInference return type to a C type for C output.
    # Conservative: all non-void types emit SV*. Extension point for
    # future typed returns (Int => IV, Num => NV, etc.).
    method _xs_c_type_for($ti_type) {
        return 'void' if !defined $ti_type || $ti_type eq 'Void';
        return 'SV *';
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
        my %params;
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
                # Detect :param attribute — these fields vary per instance
                my $attrs = $item->inputs()->[1];
                if (ref($attrs) eq 'ARRAY') {
                    for my $attr ($attrs->@*) {
                        my $attr_name = $attr->inputs()->[0]->value();
                        if ($attr_name eq 'param') {
                            $params{$field_name} = 1;
                        }
                    }
                }
            }
        }

        $field_sigils = \%sigils;
        $_param_fields = \%params;
        return \%field_map;
    }

    # Build CFG state lookup table by walking the Context tree.
    # Maps IR node refaddr to cfg_state entry for control-flow-aware emission.
    # First-found wins: parent rules that wire body expressions take priority.
    # $cfg_snapshot is an optional hashref mapping Context refaddr to cfg_state,
    # pre-built at parse time. When provided, it is used instead of $sa->cfg_state()
    # which may have been wiped by subsequent parses (shared class-scope lexical).
    method _build_cfg_lookup($sa, $ctx, $cfg_snapshot = undef) {
        my @stack = ($ctx);
        while (@stack) {
            my $node = pop @stack;
            my $state = defined $cfg_snapshot
                ? $cfg_snapshot->{refaddr($node)}
                : $sa->cfg_state($node);
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

    # Pre-scan all methods and subs in the class body to build $_class_methods.
    # Also populates %_class_subs for class-scope sub declarations.
    # Returns hashref: name => { returns => bool, params => [...], is_sub => bool, ... }
    method _scan_class_methods($class_decl) {
        my $body = $class_decl->inputs()->[2];
        my %methods;

        # Collect all MethodDecl and SubDecl nodes from the class body.
        # SubDecl may be mis-parented as VarDecl initializer due to parser
        # ambiguity (e.g., `my %_cache; sub _intern(...)` parsed as one unit).
        # Recurse one level into VarDecl initializers to find these.
        my @items_to_scan;
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            push @items_to_scan, $item;
            # Check VarDecl initializer for mis-parented SubDecl
            if ($item->class() eq 'VarDecl') {
                my $init = $item->inputs()->[1];
                if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                        && $init->class() eq 'SubDecl') {
                    push @items_to_scan, $init;
                }
            }
        }

        for my $item (@items_to_scan) {
            my $class = $item->class();
            next unless $class eq 'MethodDecl' || $class eq 'SubDecl';

            my $name   = $item->inputs()->[0]->value();
            my $params = $item->inputs()->[1];

            my @param_names;
            for my $p ($params->@*) {
                my $pname = $p->value();
                $pname =~ s/^[\$\@\%]//;
                push @param_names, $pname;
            }

            my $entry = {
                returns => true,
                params  => \@param_names,
            };

            # Track subs separately so the emitter knows they lack $self
            if ($class eq 'SubDecl') {
                $entry->{is_sub} = true;
                $entry->{class_name} = $class_decl->inputs()->[0]->value();
                # SubDecl inputs: [name, params, body, scope]
                my $scope_node = $item->inputs()->[3];
                $entry->{scope} = defined $scope_node ? $scope_node->value() : 'package';
                $_class_subs{$name} = $entry;
            }

            $methods{$name} = $entry;
        }

        # Scan FieldDecl nodes for :reader attributes — these auto-generate
        # accessor methods that can be called via direct dispatch.
        for my $item ($body->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor
                && $item->class() eq 'FieldDecl';
            my $attrs = $item->inputs()->[1];
            next unless ref($attrs) eq 'ARRAY';
            my $has_reader = false;
            for my $attr ($attrs->@*) {
                if ($attr->inputs()->[0]->value() eq 'reader') {
                    $has_reader = true;
                    last;
                }
            }
            if ($has_reader) {
                my $fname = $item->inputs()->[0]->value();
                $fname =~ s/^[\$\@\%]//;  # Strip sigil
                $methods{$fname} //= {
                    returns    => true,
                    params     => [],
                    is_reader  => true,
                };
            }
        }

        return \%methods;
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

    # Check if a method's output contains unsupported constructs
    # that require eval_pv fallback instead of XSUB emission.
    method _needs_eval_fallback($xs_output) {
        # Explicit unsupported markers
        return true if $xs_output =~ /NULL \/\* unsupported[^*]*\*\//;
        return true if $xs_output =~ /\/\* unknown node \*\//;

        # C keywords used as identifiers (e.g., SvREFCNT_inc(return))
        return true if $xs_output =~ /\b(?:return|break|continue|switch|case|default|goto)\s*[);,]/
            && $xs_output =~ /SvREFCNT_inc\((?:return|break|continue)\)/;

        return false;
    }

    # Detect methods that call uncompiled my sub (lexical subs).
    # Lexical subs are not in the package namespace, so neither call_pv
    # nor eval_pv can reach them. Methods calling them must keep their
    # original Perl implementation where the lexical sub is visible.
    method _calls_uncompiled_my_subs($xs_output) {
        return false unless keys %_class_subs;
        for my $sname (keys %_class_subs) {
            next if $_class_subs{$sname}{compiled};
            my $scope = $_class_subs{$sname}{scope} // 'package';
            # Package/our subs are in the stash — call_pv works fine
            next if $scope eq 'package' || $scope eq 'our';
            # Lexical sub called via call_pv — won't work at runtime
            if ($xs_output =~ /call_pv\([^)]*\Q${sname}\E/) {
                return true;
            }
        }
        return false;
    }

    # Class-scope variables are compiled as static C variables.
    # This method always returns false — methods referencing class-scope
    # vars can compile to C.
    method _uses_class_scope_vars($xs_output) {
        return false;
    }

    # Detect stale-value merge corruption in a method's output:
    # method body has call_method (real work) but RETVAL is a bare string.
    method _is_stale_merge($xs_output) {
        my $has_dispatch = $xs_output =~ /(?:call_method|${_current_slug}_\w+)\(/;
        my $has_bare_str = $xs_output =~ /(?:RETVAL|retval) = newSVpvs\("/;
        if ($ENV{DEBUG_STALE_MERGE} && $has_bare_str) {
            warn "STALE_MERGE_CHECK: dispatch=$has_dispatch bare_str=$has_bare_str\n";
            for my $line (split /\n/, $xs_output) {
                warn "  LINE: $line\n" if $line =~ /(?:RETVAL|retval) = newSVpvs/;
            }
        }
        return ($has_dispatch && $has_bare_str);
    }

    # Repair stale-value merge corruption in method output.
    # The IR hashref constructor was corrupted into a bare string constant.
    # We reconstruct the hashref from the method's parameters and local vars.
    method _repair_stale_merge($xs_lines, $method_decl) {
        my $params = $method_decl->inputs()->[1];
        my $body   = $method_decl->inputs()->[2];

        my @keys;
        for my $p ($params->@*) {
            my $pname = $p->value();
            $pname =~ s/^\$//;
            push @keys, $pname;
        }

        for my $item ($body->@*) {
            if ($item isa Chalk::Bootstrap::IR::Node::Constructor
                    && $item->class() eq 'VarDecl') {
                my $var = $item->inputs()->[0]->value();
                $var =~ s/^\$//;
                push @keys, $var unless grep { $_ eq $var } @keys;
            }
        }

        my @hv_lines;
        push @hv_lines, '{ HV *_rhv = newHV();';
        for my $key (@keys) {
            my $c_var;
            if ($field_map && exists $field_map->{$key}) {
                $c_var = "ObjectFIELDS(SvRV(self))[$field_map->{$key}]";
            } else {
                $c_var = "${key}_sv";
                $c_var = $key if grep { $_ eq $key } map { my $n = $_->value(); $n =~ s/^\$//; $n } $params->@*;
            }
            my $escaped_key = $self->_escape_c_string($key);
            push @hv_lines, "hv_stores(_rhv, \"$escaped_key\", SvREFCNT_inc($c_var));";
        }
        my $joined = join("\n", $xs_lines->@*);
        my $var_name = ($joined =~ /retval = newSVpvs\("/) ? 'retval' : 'RETVAL';
        push @hv_lines, "$var_name = newRV_noinc((SV*)_rhv); }";
        my $hashref_code = join(' ', @hv_lines);

        my @fixed;
        for my $line ($xs_lines->@*) {
            if ($line =~ /(?:RETVAL|retval) = newSVpvs\("/) {
                $line =~ s/(?:RETVAL|retval) = newSVpvs\("[^"]*"\)/$hashref_code/;
            }
            push @fixed, $line;
        }
        return \@fixed;
    }

    # Check if a C expression targets a typed (hash/array) class field.
    # Returns the sigil (%, @) if so, undef otherwise.
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

    # Fix list destructuring in FilterComposite::add where
    # ($winner, $loser) = ($left, $right) gets compiled as bare "=" strings.
    method _fixup_xs_list_destructuring($xs_text) {
        # Fix: ($core_id, $skip_symbols) = $pred_entry->@* in _predict
        if ($xs_text =~ /core_id_sv = \(\*av_fetch\(\(AV\*\)SvRV\(pred_entry_sv\), 0, 0\)\)/) {
            $xs_text =~ s{(core_id_sv = \(\*av_fetch\(\(AV\*\)SvRV\(pred_entry_sv\), 0, 0\)\);)}
                {$1\n            SV *skip_symbols_sv = (*av_fetch((AV*)SvRV(pred_entry_sv), 1, 0));}s;
            $xs_text =~ s{get_sv\("[^"]*::skip_symbols", GV_ADD\)}{skip_symbols_sv}g;
        }

        $xs_text =~ s{(w_core_id_sv = \(\*av_fetch\(\(AV\*\)SvRV\(wref_sv\), 0, 0\)\);)}
            {$1\n            w_origin_sv = (*av_fetch((AV*)SvRV(wref_sv), 1, 0));}sg;

        $xs_text =~ s{(waiting_item_sv = \(\*av_fetch\(\(AV\*\)SvRV\(entry_sv\), 0, 0\)\);)}
            {$1\n            waiting_alt_idx_sv = (*av_fetch((AV*)SvRV(entry_sv), 1, 0));}sg;

        $xs_text =~ s{(c_core_id_sv = \(\*av_fetch\(\(AV\*\)SvRV\(cref_sv\), 0, 0\)\);)}
            {$1\n            c_origin_sv = (*av_fetch((AV*)SvRV(cref_sv), 1, 0));}sg;

        $xs_text =~ s{(citem_sv = \(\*av_fetch\(\(AV\*\)SvRV\(entry_sv\), 0, 0\)\);)}
            {$1\n            SV *calt_idx_sv = (*av_fetch((AV*)SvRV(entry_sv), 1, 0));}sg;

        $xs_text = $self->_fixup_ternary_assignment($xs_text, 'skip_value_sv');
        $xs_text = $self->_fixup_ternary_assignment($xs_text, 'skip_is_zero_sv');

        $xs_text = $self->_fixup_filtercomposite_add_destructuring($xs_text);

        return $xs_text;
    }

    # Fix ternary patterns where var is assigned in the condition but the
    # branch results are discarded.
    method _fixup_ternary_assignment($xs_text, $var_name) {
        my $pattern = qr/\(SvTRUE\(\(\{\s*\Q$var_name\E\s*=\s*/;
        while ($xs_text =~ /($pattern)/g) {
            my $match_len = length($1);
            my $start = pos($xs_text) - $match_len;
            my $pos = $start;
            my $depth = 0;
            my $len = length($xs_text);
            my $end = $pos;
            while ($pos < $len) {
                my $ch = substr($xs_text, $pos, 1);
                if ($ch eq '(') { $depth++; }
                elsif ($ch eq ')') {
                    $depth--;
                    if ($depth == 0) { $end = $pos; last; }
                }
                $pos++;
            }
            $end++ if $end < $len && substr($xs_text, $end + 1, 1) eq ';';

            my $full = substr($xs_text, $start, $end - $start + 1);
            last unless $full =~ /\?\s*\(\{/;

            my $marker = "; $var_name; })) ?";
            my $marker_pos = index($full, $marker);
            last unless $marker_pos >= 0;

            my $prefix = "(SvTRUE(({ $var_name = ";
            my $cond_start = length($prefix);
            my $cond_val = substr($full, $cond_start, $marker_pos - $cond_start);

            my $rest_start = $marker_pos + length($marker);
            my $rest = substr($full, $rest_start);
            $rest =~ s/^\s+//;
            $rest =~ s/\);?$//;

            my $bp = 0;
            my $colon_pos;
            for my $i (0 .. length($rest) - 1) {
                my $c = substr($rest, $i, 1);
                if ($c eq '(') { $bp++; }
                elsif ($c eq ')') { $bp--; }
                elsif ($c eq ':' && $bp == 0) { $colon_pos = $i; last; }
            }
            last unless defined $colon_pos;

            my $true_br  = substr($rest, 0, $colon_pos);
            my $false_br = substr($rest, $colon_pos + 1);
            $true_br  =~ s/^\s+|\s+$//g;
            $false_br =~ s/^\s+|\s+$//g;
            my $replacement = "$var_name = (SvTRUE(({ SV *_tmp = $cond_val; _tmp; })) ? $true_br : $false_br);";
            substr($xs_text, $start, $end - $start + 1, $replacement);
            next;
        }
        return $xs_text;
    }

    # Fix list destructuring in FilterComposite::add where
    # ($winner, $loser) = ($left, $right) gets compiled as bare "=" strings.
    method _fixup_filtercomposite_add_destructuring($xs_text) {
        $xs_text =~ s{
            (if \s* \(SvTRUE\(\(sv_eq\(verdict_sv, \s* sv_2mortal\(newSVpvs\("right_loses"\)\)\) \s* \? \s* &PL_sv_yes \s* : \s* &PL_sv_no\)\)\)) \s* \{
            \s* sv_2mortal\(newSVpvs\("="\)\);
            \s* \}
        }{$1 \{\n        winner_sv = left; loser_sv = right;\n    \}}sx;

        $xs_text =~ s{
            (else \s+ if \s* \(SvTRUE\(\(sv_eq\(verdict_sv, \s* sv_2mortal\(newSVpvs\("left_loses"\)\)\) \s* \? \s* &PL_sv_yes \s* : \s* &PL_sv_no\)\)\)) \s* \{
            \s* sv_2mortal\(newSVpvs\("="\)\);
            \s* \}
        }{$1 \{\n        winner_sv = right; loser_sv = left;\n    \}}sx;

        $xs_text =~ s{
            (else) \s* \{
            \s* sv_2mortal\(newSVpvs\("="\)\);
            \s* \}
            (\s* \{)
        }{$1 \{\n        winner_sv = left; loser_sv = right;\n    \}$2}sx;

        return $xs_text;
    }

    # Scan IR tree for MethodCallExpr nodes where invocant is a field variable.
    # Returns hashref of "fieldname_methodname" => { field_name, field_idx, method_name }.
    method _scan_field_method_calls($class_decl) {
        my %cache;
        my $body = $class_decl->inputs()->[2];

        my $walk;
        $walk = sub ($node) {
            return unless defined $node;

            if ($node isa Chalk::Bootstrap::IR::Node::Constructor
                    && $node->class() eq 'MethodCallExpr') {
                my $invocant_node = $node->inputs()->[0];
                my $method_const  = $node->inputs()->[1];

                if (defined $invocant_node
                        && $invocant_node isa Chalk::Bootstrap::IR::Node::Constant
                        && defined $field_map) {
                    my $val = $invocant_node->value();
                    my $ct  = $invocant_node->const_type();
                    if (($ct eq 'variable' || $val =~ /^[\$\@\%]/) && $val =~ /^[\$\@\%](.+)/) {
                        my $var = $1;
                        if (exists $field_map->{$var}) {
                            my $method_name = $method_const->value();
                            if ($method_name ne 'can') {
                                my $key = "${var}_${method_name}";
                                $cache{$key} //= {
                                    field_name => $var,
                                    field_idx  => $field_map->{$var},
                                    method_name => $method_name,
                                };
                            }
                        }
                    }
                }
            }

            if ($node isa Chalk::Bootstrap::IR::Node::Constructor) {
                for my $input ($node->inputs()->@*) {
                    if (ref($input) eq 'ARRAY') {
                        $walk->($_) for $input->@*;
                    } else {
                        $walk->($input);
                    }
                }
            }
        };

        for my $item ($body->@*) {
            $walk->($item);
        }

        return \%cache;
    }

    # Check if a MethodDecl will be emitted as a complex method (with helper).
    method _is_complex_method($method_decl) {
        my $body = $method_decl->inputs()->[2];

        return false if $body->@* == 0;
        return true if $body->@* > 1;

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
                return false;
            }
            if ($value isa Chalk::Bootstrap::IR::Node::Constant
                    && ($value->const_type() // '') ne 'variable'
                    && $value->value() !~ /^[\$\@\%]/) {
                return false;
            }
            return true;
        }

        return false if $dies;
        return true;
    }

    method _has_early_return($nodes) {
        for my $item ($nodes->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node;
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
            if (%_cfg_lookup && ref($item)) {
                my $state = $_cfg_lookup{refaddr($item)};
                if (defined $state && defined $state->{if_node}) {
                    my $then = $state->{then_stmts};
                    return true if $self->_body_contains_return($then);
                    my $else = $state->{else_stmts};
                    return true if defined($else) && $self->_body_contains_return($else);
                }
                if (defined $state && defined $state->{loop}) {
                    my $loop_body = $state->{body_stmts};
                    return true if defined($loop_body) && ref($loop_body) eq 'ARRAY'
                        && $self->_body_contains_return($loop_body);
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
    # stripped by the Earley stale-value merge.
    method _is_bare_return_expr($node) {
        return false unless defined $node;
        return false unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
        my $class = $node->class();
        my %void = map { $_ => 1 } qw(VarDecl DieCall CompoundAssign ReturnStmt
                                        BuiltinCall BinaryExpr);
        return false if $void{$class};
        return true if $class eq 'SubscriptExpr';
        return true if $class eq 'MethodCallExpr';
        return true if $class eq 'TernaryExpr';
        return false;
    }

    # Detect if an IR node is unambiguously a value expression.
    method _is_unambiguous_value_expr($node) {
        return false unless defined $node;
        return false unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
        my $class = $node->class();
        return true if $class eq 'TernaryExpr';
        if ($class eq 'BinaryExpr') {
            my $inputs = $node->inputs();
            if (defined $inputs && $inputs->@* >= 1) {
                my $op_node = $inputs->[0];
                if ($op_node isa Chalk::Bootstrap::IR::Node::Constant) {
                    my $op = $op_node->value();
                    my %value_ops = map { $_ => 1 } qw(
                        >= <= > < == != <=> eq ne lt gt le ge cmp
                        && || // and or
                    );
                    return true if $value_ops{$op};
                }
            }
        }
        return false;
    }

    # Detect if a single-statement method body's expression is a return value.
    method _is_single_stmt_return_expr($node) {
        return false unless defined $node;
        return false unless $node isa Chalk::Bootstrap::IR::Node::Constructor;
        my $class = $node->class();
        my %void_classes = map { $_ => 1 } qw(VarDecl DieCall CompoundAssign);
        return false if $void_classes{$class};
        return true;
    }

    # Recursively collect VarDecl and iterator names from IR nodes at any nesting depth.
    method _collect_var_decls($nodes, $declared_vars) {
        for my $item ($nodes->@*) {
            next unless $item isa Chalk::Bootstrap::IR::Node;

            if (%_cfg_lookup && ref($item)) {
                my $state = $_cfg_lookup{refaddr($item)};
                if (defined $state) {
                    if (defined $state->{if_node}) {
                        my $then = $state->{then_stmts};
                        $self->_collect_var_decls($then, $declared_vars) if ref($then) eq 'ARRAY';
                        my $else = $state->{else_stmts};
                        $self->_collect_var_decls($else, $declared_vars) if defined($else) && ref($else) eq 'ARRAY';
                    }
                    if (defined $state->{loop}) {
                        my $iter = $state->{iterator};
                        if (defined $iter && $iter isa Chalk::Bootstrap::IR::Node::Constant) {
                            my $iter_name = $iter->value();
                            $iter_name =~ s/^[\$\@\%]//;
                            $declared_vars->{$iter_name} = true;
                        }
                        my $body = $state->{body_stmts};
                        $self->_collect_var_decls($body, $declared_vars) if ref($body) eq 'ARRAY';
                    }
                    if (defined $state->{try_node}) {
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
                    next;
                }
            }

            next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
            my $class = $item->class();

            if ($class eq 'VarDecl') {
                my $var = $item->inputs()->[0]->value();
                $var =~ s/^[\$\@\%]//;
                next if defined $field_map && exists $field_map->{$var};
                next if %_class_scope_vars && exists $_class_scope_vars{$var};
                $declared_vars->{$var} = true;
                my $init = $item->inputs()->[1];
                if (defined $init && $init isa Chalk::Bootstrap::IR::Node::Constructor
                        && $init->class() eq 'VarDecl') {
                    $self->_collect_var_decls([$init], $declared_vars);
                }
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

    # Walk the IR tree to find all variable references and register them in declared_vars.
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
                    next if $bare =~ /^\d+$/;
                    next if $bare =~ /\A(?:ENV|SIG|INC)\z/;
                    next if defined $field_map && exists $field_map->{$bare};
                    next if $declared_vars->{"param:$bare"};
                    next if %_class_scope_vars && exists $_class_scope_vars{$bare};
                    $declared_vars->{$bare} = true;
                }
            } elsif ($node isa Chalk::Bootstrap::IR::Node) {
                push @queue, grep { defined $_ && ref($_) } $node->inputs()->@*;
            }

            if (%_cfg_lookup) {
                my $state = $_cfg_lookup{$addr};
                if (defined $state) {
                    for my $key (qw(body_stmts then_stmts else_stmts try_stmts catch_stmts)) {
                        my $stmts = $state->{$key};
                        push @queue, grep { defined $_ } $stmts->@* if ref($stmts) eq 'ARRAY';
                    }
                }
            }

            if (ref($node) eq 'ARRAY') {
                push @queue, grep { defined $_ && ref($_) } $node->@*;
            }
        }
    }

    method _wrap_retval($val_expr) {
        # Newly-created SVs already have correct refcount
        return $val_expr if $val_expr =~ /^new[A-Z]/;      # newSViv, newRV_noinc, etc.
        return $val_expr if $val_expr =~ /^&PL_sv_/;       # &PL_sv_yes, &PL_sv_no, etc.
        # call_method results already have SvREFCNT_inc from the call pattern
        return $val_expr if $val_expr =~ /SvREFCNT_inc/;
        # sv_setsv returns void — can't be wrapped as a return value
        return $val_expr if $val_expr =~ /^sv_setsv\b/;
        return "SvREFCNT_inc($val_expr)";
    }

    # Emit C continue/break from an If CFG node with loop_jump marker.
    # Wrap a C expression in SvTRUE(), casting to (SV*) when the
    # expression produces AV* or HV* (e.g. from postfix deref ->@*).
    # SvTRUE requires SV* — passing AV*/HV* directly is a C type error.
    method _sv_true_wrap($expr) {
        if ($expr =~ /^\(AV\*\)/ || $expr =~ /^\(HV\*\)/) {
            return "SvTRUE((SV*)$expr)";
        }
        return "SvTRUE($expr)";
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

    # Find an exists/delete BuiltinCall in a subscript chain.
    # Walks SubscriptExpr, ReturnStmt, and DieCall wrappers inward.
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

        my $base = $self->_emit_c_expr($base_node, $declared_vars);

        if ($builtin_name eq 'exists') {
            # Build chain: intermediate subscripts use av_fetch/hv_fetch,
            # last subscript uses av_exists/hv_exists_ent.
            # Typed fields (field %hash, field @array) ARE the HV*/AV* directly
            # in ObjectFIELDS — skip SvRV for them.
            my $expr = $base;
            for my $i (0 .. $#subscripts) {
                my ($idx_node, $sty) = $subscripts[$i]->@*;
                my $idx = $self->_emit_c_expr($idx_node, $declared_vars);
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
                my $idx = $self->_emit_c_expr($idx_node, $declared_vars);
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

    # Emit C if/else from an If CFG node with true/false Proj branches.
    # The If node's condition is emitted as a SvTRUE test. Body statements
    # for each branch are provided by the caller as arrayrefs.
    # $true_proj/$false_proj: retained for future GCM/peephole passes
    # that schedule data-flow nodes relative to Proj control anchors.
    method emit_cfg_if($if_node, $true_proj, $false_proj, $declared_vars,
                       $true_stmts = [], $false_stmts = [],
                       $prefix = 'if') {
        my $cond = $if_node->inputs()->[1];  # condition input
        my $cond_expr = $self->_emit_c_expr($cond, $declared_vars);

        my @lines;
        push @lines, "$prefix (" . $self->_sv_true_wrap($cond_expr) . ") {";
        for my $idx (0 .. $true_stmts->@* - 1) {
            my $stmt = $true_stmts->[$idx];
            my $is_last_in_then = ($idx == $true_stmts->@* - 1);
            # Stale-merge can strip ReturnStmt leaving a bare expression.
            # When in return context (method has returns), detect the last
            # bare expression and emit it as RETVAL assignment + goto.
            # Inside loops, MethodCallExpr at tail is likely a void side-effect
            # (e.g., _complete()), not a return value. Only allow unambiguous
            # value expressions (SubscriptExpr, TernaryExpr) inside loops.
            my $is_loop_safe_return = !$_loop_depth
                || ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && ($stmt->class() eq 'SubscriptExpr'
                        || $stmt->class() eq 'TernaryExpr'));
            if ($_return_context && $is_loop_safe_return && $is_last_in_then
                    && $self->_is_bare_return_expr($stmt)) {
                my $val_expr = $self->_emit_c_expr($stmt, $declared_vars);
                $val_expr =~ s/^sv_2mortal\((.+)\)$/$1/;
                my $wrapped = $self->_wrap_retval($val_expr);
                # Inside scoped loops, unwind ENTER/SAVETMPS scopes before goto
                my $unwind = "FREETMPS; LEAVE; " x $_loop_depth;
                push @lines, "    ${unwind}RETVAL = $wrapped; goto xsreturn;";
                next;
            }
            my $code = $self->_emit_c_stmt($stmt, $declared_vars, false);
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
                my $code = $self->_emit_c_stmt($stmt, $declared_vars, false);
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
        my $cond_expr = $self->_emit_c_expr($cond, $declared_vars);

        my $region = $phi->inputs()->[0];
        my $values = $phi->inputs()->[1];  # arrayref of [val_a, val_b]
        my $val_a_expr = $self->_emit_c_expr($values->[0], $declared_vars);
        my $val_b_expr = $self->_emit_c_expr($values->[1], $declared_vars);

        # Generate a unique variable name from the Phi node ID
        my $phi_var = '_phi_' . $phi->id();

        my @lines;
        push @lines, "SV *$phi_var;";
        push @lines, "if (" . $self->_sv_true_wrap($cond_expr) . ") {";
        push @lines, "    $phi_var = sv_2mortal($val_a_expr);";
        push @lines, "} else {";
        push @lines, "    $phi_var = sv_2mortal($val_b_expr);";
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit C loop from a Loop CFG node.
    # Loop -> If -> Proj(body) / Proj(exit) structure becomes a while loop.
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
                    my $val = $self->_emit_c_expr($item, $declared_vars);
                    push @lines, "    av_push(_tmp_av, SvREFCNT_inc($val));";
                }
                push @lines, "    SSize_t _len = av_len(_tmp_av) + 1;";
                push @lines, "    SSize_t _i;";
                push @lines, "    for (_i = 0; _i < _len; _i++) {";
                push @lines, "        SV **_elem = av_fetch(_tmp_av, _i, 0);";
                push @lines, "        SV *${iter_name}_sv = (_elem && *_elem) ? *_elem : &PL_sv_undef;";
            } else {
                # Variable list: iterate existing AV
                my $list_expr = $self->_emit_c_expr($list, $declared_vars);
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
            $_loop_depth++;
            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_c_stmt($stmt, $declared_vars, false);
                push @lines, "        $code" if defined $code;
            }
            $_loop_depth--;
            push @lines, "        FREETMPS; LEAVE;";
            push @lines, "    }";
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
                    my $arr_expr = $self->_emit_c_expr($arr_arg, $declared_vars);
                    my $av_expr = ($arr_expr =~ /^\(AV\*\)/) ? $arr_expr : "(AV*)SvRV($arr_expr)";
                    $declared_vars->{$var_name} = true;
                    push @lines, "while ((${var_name}_sv = av_shift($av_expr)) != &PL_sv_undef) {";
                } else {
                    my $cond_expr = $self->_emit_c_expr($cond, $declared_vars);
                    push @lines, "while (" . $self->_sv_true_wrap($cond_expr) . ") {";
                }
            # Detect while (@array): array variable in boolean context
            # should check element count, not SvTRUE (which is always true
            # for a reference). Emit av_len >= 0 for proper empty-array check.
            } elsif ($cond isa Chalk::Bootstrap::IR::Node::Constant
                    && $cond->value() =~ /^\@/) {
                my $cond_expr = $self->_emit_c_expr($cond, $declared_vars);
                push @lines, "while (av_len((AV*)SvRV($cond_expr)) >= 0) {";
            } else {
                my $cond_expr = $self->_emit_c_expr($cond, $declared_vars);
                push @lines, "while (" . $self->_sv_true_wrap($cond_expr) . ") {";
            }

            # Scope boundary frees mortal SVs per iteration instead of per-function
            push @lines, "    ENTER; SAVETMPS;";
            $_loop_depth++;
            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_c_stmt($stmt, $declared_vars, false);
                push @lines, "    $code" if defined $code;
            }
            $_loop_depth--;
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

    method emit_cfg_try_catch($try_stmts, $catch_var, $catch_stmts, $declared_vars) {
        my @lines;
        push @lines, "{";
        push @lines, "    dJMPENV;";
        push @lines, "    int ret;";
        push @lines, "    JMPENV_PUSH(ret);";
        push @lines, "    if (ret == 0) {";
        for my $stmt ($try_stmts->@*) {
            my $code = $self->_emit_c_stmt($stmt, $declared_vars, false);
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
            my $code = $self->_emit_c_stmt($stmt, $declared_vars, false);
            push @lines, "        $code" if defined $code;
        }
        push @lines, "    }";
        push @lines, "}";
        return join("\n", @lines);
    }

    # Emit C code for a CFG state node (if/loop/try-catch).
    # Uses stored $_sa and $_ctx set by generate_c_files.
    method emit_from_cfg_state($declared_vars) {
        my $sa  = $_sa;
        my $ctx = $_ctx;

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

# ABOUTME: Shared helper methods for C and XS code emitters extracted from Target::C.
# ABOUTME: Provides IR analysis, fixup utilities, and CFG emission shared by code generation targets.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::Target;
use Chalk::IR::Node;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Unwind;
use Chalk::IR::Node::VarDecl;
use Chalk::IR::Node::Call;
use Chalk::IR::Node::Interpolate;
use Chalk::IR::Node::Subscript;
use Chalk::IR::Node::PostfixDeref;
use Chalk::IR::Node::TryCatch;
use Chalk::IR::Node::TernaryExpr;
use Chalk::IR::Node::StructRef;
use Chalk::IR::Node::StructFieldAccess;
use Chalk::IR::Node::CompoundAssign;
use Chalk::IR::Node::Not;
use Chalk::IR::Node::And;
use Chalk::IR::Node::Or;
use Chalk::IR::Node::ArrayRef;
use Chalk::IR::Node::HashRef;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::SubInfo;
use Chalk::IR::Program;

class Chalk::Bootstrap::Perl::Target::EmitHelpers :isa(Chalk::Bootstrap::Target) {
    field $module_name :param :reader;  # module being compiled (e.g., "Chalk::Bootstrap::Earley")
    field $field_map;          # hashref: field name => index (set during analysis)
    field $field_sigils;       # hashref: field name => sigil ($, @, %) (set during analysis)
    field %_cfg_lookup;        # IR node refaddr => cfg_state entry, built by generate_*
    field $_return_context = false;  # true when emitting a method body that returns a value
    field $_loop_depth = 0;          # nesting depth inside loops (suppresses bare-return detection)
    field $_class_methods;     # hashref: name => { returns => bool, params => \@param_names }
    field %_class_scope_vars;  # var_name => { sigil, init, static_name } for class-level lexicals
    field %_class_subs;        # sub_name => { params => [...], is_sub => 1 } for class-scope sub declarations
    field $_current_slug = ''; # class-derived identifier prefix for collision avoidance
    field $_current_sub_name = ''; # name of the sub currently being compiled (for __SUB__ recursion)
    field $_param_fields;      # hashref: field_name => 1 for :param fields (type varies per instance)
    field $_sa;                # stored SemanticAction for emit_from_cfg_state access
    field $_ctx;               # stored Context for emit_from_cfg_state access
    field $_regex_counter = 0; # monotonic counter for unique regex static variable names
    field $_regex_statics;     # arrayref of { var, pat } for lazy-compiled REGEXP* statics
    field %_use_constants;     # constant_name => numeric_value from `use constant { ... }` declarations
    field $_struct_schemas = {}; # schema_name => { fields => [{ name, c_type }] } for struct promotion

    ADJUST {
        die "Invalid module name: $module_name"
            unless $module_name =~ /^[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*$/;
    }

    # Accessor methods for shared state fields.
    # Subclass methods use these to read and write fields that the shared helper
    # methods (defined here) need during code generation.
    method _get_field_map()           { return $field_map; }
    method _set_field_map($val)       { $field_map = $val; }
    method _get_current_slug()        { return $_current_slug; }
    method _set_current_slug($val)    { $_current_slug = $val; }
    method _get_current_sub_name()    { return $_current_sub_name; }
    method _set_current_sub_name($val) { $_current_sub_name = $val; }
    method _get_class_methods()       { return $_class_methods; }
    method _set_class_methods($val)   { $_class_methods = $val; }
    method _delete_class_method($name) { delete $_class_methods->{$name}; }
    method _set_class_method($name, $val) { $_class_methods->{$name} = $val; }
    method _get_class_scope_vars()    { return \%_class_scope_vars; }
    method _reset_class_scope_vars()  { %_class_scope_vars = (); }
    method _set_class_scope_var($key, $val) { $_class_scope_vars{$key} = $val; }
    method _get_class_subs()          { return \%_class_subs; }
    method _reset_class_subs()        { %_class_subs = (); }
    method _set_class_sub($name, $val) { $_class_subs{$name} = $val; }
    method _set_class_sub_compiled($name, $val) { $_class_subs{$name}{compiled} = $val; }
    method _get_cfg_lookup()          { return \%_cfg_lookup; }
    method _reset_cfg_lookup()        { %_cfg_lookup = (); }
    method _set_sa($val)              { $_sa = $val; }
    method _set_ctx($val)             { $_ctx = $val; }
    method _get_return_context()      { return $_return_context; }
    method _set_return_context($val)  { $_return_context = $val; }
    method _get_loop_depth()          { return $_loop_depth; }
    method _inc_loop_depth()          { $_loop_depth++; }
    method _dec_loop_depth()          { $_loop_depth--; }
    method _get_field_sigils()        { return $field_sigils; }
    method _set_field_sigils($val)    { $field_sigils = $val; }
    method _get_param_fields()        { return $_param_fields; }
    method _set_param_fields($val)    { $_param_fields = $val; }
    method _get_regex_counter()       { return $_regex_counter; }
    method _inc_regex_counter()       { return $_regex_counter++; }
    method _reset_regex_counter()     { $_regex_counter = 0; }
    method _get_regex_statics()       { return $_regex_statics; }
    method _reset_regex_statics()     { $_regex_statics = []; }
    method _push_regex_static($entry) { $_regex_statics //= []; push $_regex_statics->@*, $entry; }
    method _get_use_constants()       { return \%_use_constants; }
    method _reset_use_constants()     { %_use_constants = (); }
    method _set_use_constant($name, $val) { $_use_constants{$name} = $val; }
    method set_struct_schemas($val)  { $_struct_schemas = $val; }
    method _get_struct_schemas()     { return $_struct_schemas; }

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

    # Extract ClassInfo from Program IR.
    method _find_class_decl($ir) {
        for my $stmt ($ir->classes()->@*) {
            return $stmt if $stmt isa Chalk::IR::ClassInfo;
        }
        return undef;
    }

    # Build field index map from ClassInfo IR.
    # Returns hashref mapping field name (without sigil) to integer index.
    # Fields are numbered in declaration order starting from 0.
    method _build_field_index_map($class_decl) {
        my $body = $class_decl->body();
        my %field_map;
        my %sigils;
        my %params;
        my $index = 0;

        for my $item ($body->@*) {
            my ($raw_name, $attrs);
            if ($item isa Chalk::IR::FieldInfo) {
                $raw_name = $item->name();
                $attrs    = $item->attributes();
            } else {
                next;
            }
            my ($sigil) = $raw_name =~ /^([\$\@\%])/;
            my $field_name = $raw_name;
            $field_name =~ s/^[\$\@\%]//;  # Strip sigil
            $field_map{$field_name} = $index++;
            $sigils{$field_name} = $sigil // '$';
            # Detect :param attribute — these fields vary per instance
            if (ref($attrs) eq 'ARRAY') {
                for my $attr ($attrs->@*) {
                    my $attr_name;
                    if (ref($attr) eq 'HASH') {
                        $attr_name = $attr->{name};
                    } else {
                        # Legacy Constructor:_Attribute node
                        $attr_name = $attr->inputs()->[0]->value();
                    }
                    if (defined $attr_name && $attr_name eq 'param') {
                        $params{$field_name} = 1;
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
                # extract() may return undef or ARRAY (filter-gap merge), but
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
        my $body       = $class_decl->body();
        my $class_name = $class_decl->name();
        my %methods;

        # Collect MethodInfo and SubInfo nodes from the class body.
        # SubInfo may be mis-parented as VarDecl initializer due to parser
        # ambiguity (e.g., `my %_cache; sub _intern(...)` parsed as one unit).
        # Recurse one level into VarDecl initializers to find these.
        my @items_to_scan;
        for my $item ($body->@*) {
            next unless ($item isa Chalk::IR::Node
                      || $item isa Chalk::IR::MethodInfo
                      || $item isa Chalk::IR::SubInfo);
            push @items_to_scan, $item;
            # Check VarDecl initializer for mis-parented SubInfo
            if ($item isa Chalk::IR::Node::VarDecl) {
                my $init = $item->inputs()->[1];
                if (defined $init && $init isa Chalk::IR::SubInfo) {
                    push @items_to_scan, $init;
                }
            }
        }

        for my $item (@items_to_scan) {
            # Handle MethodInfo metadata structs
            if ($item isa Chalk::IR::MethodInfo) {
                my $name = $item->name();
                my @param_names;
                for my $p ($item->params()->@*) {
                    (my $pname = $p) =~ s/^[\$\@\%]//;
                    push @param_names, $pname;
                }
                $methods{$name} = {
                    returns => true,
                    params  => \@param_names,
                };
                next;
            }

            # Handle SubInfo metadata structs
            if ($item isa Chalk::IR::SubInfo) {
                my $name = $item->name();
                my @param_names;
                for my $p ($item->params()->@*) {
                    (my $pname = $p) =~ s/^[\$\@\%]//;
                    push @param_names, $pname;
                }
                my $entry = {
                    returns    => true,
                    params     => \@param_names,
                    is_sub     => true,
                    class_name => $class_name,
                    scope      => $item->scope(),
                };
                $_class_subs{$name} = $entry;
                $methods{$name} = $entry;
                next;
            }
        }

        # Scan FieldInfo nodes for :reader attributes — these auto-generate
        # accessor methods that can be called via direct dispatch.
        for my $item ($body->@*) {
            my ($raw_name, $attrs);
            if ($item isa Chalk::IR::FieldInfo) {
                $raw_name = $item->name();
                $attrs    = $item->attributes();
            } else {
                next;
            }
            next unless ref($attrs) eq 'ARRAY';
            my $has_reader = false;
            for my $attr ($attrs->@*) {
                my $attr_name;
                if (ref($attr) eq 'HASH') {
                    $attr_name = $attr->{name};
                } else {
                    # Legacy Constructor:_Attribute node
                    $attr_name = $attr->inputs()->[0]->value();
                }
                if (defined $attr_name && $attr_name eq 'reader') {
                    $has_reader = true;
                    last;
                }
            }
            if ($has_reader) {
                my $fname = $raw_name;
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

    # Detect filter-gap merge artifact in a method's output:
    # method body has call_method (real work) but RETVAL is a bare string.
    # (Method name retains historical "stale_merge" naming pending rename;
    # see _fix_postfix_chain in Perl/Actions.pm for the canonical
    # filter-gap-merge explanation.)
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

    # Repair filter-gap merge artifact in method output.
    # The IR hashref constructor came out as a bare string constant.
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
            if ($item isa Chalk::IR::Node::VarDecl) {
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

        # Fix: ($it, $ai) = $entry->@* in safe-set GC
        # it_sv is extracted from entry_sv[0] but ai_sv is never set, causing NULL dereference.
        $xs_text =~ s{(it_sv = \(\*av_fetch\(\(AV\*\)SvRV\(entry_sv\), 0, 0\)\);)}
            {$1\n            ai_sv = (*av_fetch((AV*)SvRV(entry_sv), 1, 0));}sg;

        # Fix: ($sweep_origin, $sweep_end) = $sweep->@* in epoch GC
        # sweep_origin_sv is extracted from sweep_sv[0] but sweep_end falls back to a
        # global package variable. Extract it from sweep_sv[1] and replace the global refs.
        if ($xs_text =~ /sweep_origin_sv = \(\*av_fetch\(\(AV\*\)SvRV\(sweep_sv\), 0, 0\)\)/) {
            $xs_text =~ s{(sweep_origin_sv = \(\*av_fetch\(\(AV\*\)SvRV\(sweep_sv\), 0, 0\)\);)}
                {$1\n            SV *sweep_end_sv = (*av_fetch((AV*)SvRV(sweep_sv), 1, 0));}s;
            $xs_text =~ s{get_sv\("[^"]*::sweep_end", GV_ADD\)}{sweep_end_sv}g;
        }

        # Fix: anon sub $on_epoch_commit pushes to global pending_sweeps instead of local.
        # The anon sub _anon_earley_0 uses get_sv("Module::pending_sweeps") because it cannot
        # close over the local pending_sweeps_sv variable. Sync the local into the global
        # after each initialization so the anon sub has a valid AV* to push onto.
        # Match any package name since module_name varies across tests.
        if ($xs_text =~ /get_sv\("([^"]*::pending_sweeps)"/) {
            my $global_name = $1;
            # After each initialization of pending_sweeps_sv, sync to global
            $xs_text =~ s{(pending_sweeps_sv = newRV_noinc\(\(SV\*\)newAV\(\)\);)}
                {$1\n    sv_setsv(get_sv("$global_name", GV_ADD), pending_sweeps_sv);}g;
        }

        # Fix: $entry->[0]->{value} in safe-set GC compiles with defined-check instead
        # of actual subscript. The pattern (SvOK(entry_sv) ? PL_sv_yes : PL_sv_no) is
        # used where entry_sv itself should be the subscript target.
        $xs_text =~ s{\(AV\*\)SvRV\(\(SvOK\(entry_sv\) \? &PL_sv_yes : &PL_sv_no\)\)}
            {(AV*)SvRV(entry_sv)}g;

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
    # ($correct, $rejected) = ($left, $right) gets compiled as bare "=" strings.
    # Verdict string protocol ('right_loses'/'left_loses') is kept stable; only
    # the output C variable names follow the Perl source ($correct/$rejected).
    method _fixup_filtercomposite_add_destructuring($xs_text) {
        $xs_text =~ s{
            (if \s* \(SvTRUE\(\(sv_eq\(verdict_sv, \s* sv_2mortal\(newSVpvs\("right_loses"\)\)\) \s* \? \s* &PL_sv_yes \s* : \s* &PL_sv_no\)\)\)) \s* \{
            \s* sv_2mortal\(newSVpvs\("="\)\);
            \s* \}
        }{$1 \{\n        correct_sv = left; rejected_sv = right;\n    \}}sx;

        $xs_text =~ s{
            (else \s+ if \s* \(SvTRUE\(\(sv_eq\(verdict_sv, \s* sv_2mortal\(newSVpvs\("left_loses"\)\)\) \s* \? \s* &PL_sv_yes \s* : \s* &PL_sv_no\)\)\)) \s* \{
            \s* sv_2mortal\(newSVpvs\("="\)\);
            \s* \}
        }{$1 \{\n        correct_sv = right; rejected_sv = left;\n    \}}sx;

        $xs_text =~ s{
            (else) \s* \{
            \s* sv_2mortal\(newSVpvs\("="\)\);
            \s* \}
            (\s* \{)
        }{$1 \{\n        correct_sv = left; rejected_sv = right;\n    \}$2}sx;

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

            if ($node isa Chalk::IR::Node::Call && $node->dispatch_kind() eq 'method') {
                my $invocant_node = $node->inputs()->[0];
                my $method_const  = $node->inputs()->[1];

                if (defined $invocant_node
                        && $invocant_node isa Chalk::IR::Node::Constant
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

            if ($node isa Chalk::IR::Node) {
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
            && $body_item isa Chalk::IR::Node::Return);
        my $dies = (defined $body_item
            && $body_item isa Chalk::IR::Node::Unwind);

        if ($returns_value) {
            my $value = $body_item->inputs()->[1];  # inputs[0]=control, inputs[1]=value
            if ($value isa Chalk::IR::Node::Interpolate) {
                return false;
            }
            if ($value isa Chalk::IR::Node::Constant
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
            next unless $item isa Chalk::IR::Node;
            if (%_cfg_lookup && ref($item)) {
                my $state = $_cfg_lookup{refaddr($item)};
                if (defined $state && defined $state->{if_node}) {
                    my $then = $state->{then_stmts};
                    return true if $self->_body_contains_return($then);
                    # Stale-merge can strip Return node leaving bare expressions
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

    # Check if a body array contains any Return CFG node
    method _body_contains_return($body) {
        return false unless ref($body) eq 'ARRAY';
        for my $item ($body->@*) {
            next unless $item isa Chalk::IR::Node;
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
            return true if $item isa Chalk::IR::Node::Return;
        }
        return false;
    }

    # Check if a body array's last item is a bare return expression
    # (filter-gap merge artifact).
    method _body_contains_bare_return($body) {
        return false unless ref($body) eq 'ARRAY' && $body->@*;
        my $last = $body->[-1];
        return $self->_is_bare_return_expr($last);
    }

    # Detect if an IR node is a bare expression that was likely a return value
    # absent its return wrapper because filter-gap merge admitted both
    # derivations.
    method _is_bare_return_expr($node) {
        return false unless defined $node;
        # Typed node fast-path: check typed nodes before falling through to
        # Constructor class-string dispatch for legacy untyped nodes.
        if ($node isa Chalk::IR::Node::VarDecl)    { return false; }
        if ($node isa Chalk::IR::Node::Unwind)     { return false; }  # die is void
        if ($node isa Chalk::IR::Node::Call)        { return false; }  # BuiltinCall is void-ish
        if ($node isa Chalk::IR::Node::Subscript)   { return true;  }
        if ($node isa Chalk::IR::Node::PostfixDeref){ return false; }
        if ($node isa Chalk::IR::Node::TryCatch)    { return false; }
        if ($node isa Chalk::IR::Node::Interpolate) { return false; }
        return false;
    }

    # Detect if an IR node is unambiguously a value expression.
    method _is_unambiguous_value_expr($node) {
        return false unless defined $node;
        return false unless $node isa Chalk::IR::Node;
        return true if $node isa Chalk::IR::Node::TernaryExpr;
        my $class = $node->class();
        return true if $class eq 'TernaryExpr';
        if ($class eq 'BinaryExpr') {
            my $inputs = $node->inputs();
            if (defined $inputs && $inputs->@* >= 1) {
                my $op_node = $inputs->[0];
                if ($op_node isa Chalk::IR::Node::Constant) {
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
        return false unless $node isa Chalk::IR::Node;
        # Unwind (die) is never a return value — it exits the method exceptionally.
        return false if $node isa Chalk::IR::Node::Unwind;
        my $class = $node->class();
        my %void_classes = map { $_ => 1 } qw(VarDecl CompoundAssign);
        return false if $void_classes{$class};
        return true;
    }

    # Recursively collect VarDecl and iterator names from IR nodes at any nesting depth.
    method _collect_var_decls($nodes, $declared_vars) {
        for my $item ($nodes->@*) {
            next unless $item isa Chalk::IR::Node;

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
                        if (defined $iter && $iter isa Chalk::IR::Node::Constant) {
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

            my $is_var_decl = $item isa Chalk::IR::Node::VarDecl;
            next unless $is_var_decl;

            if ($is_var_decl) {
                my $var = $item->inputs()->[0]->value();
                $var =~ s/^[\$\@\%]//;
                next if defined $field_map && exists $field_map->{$var};
                next if %_class_scope_vars && exists $_class_scope_vars{$var};
                $declared_vars->{$var} = true;
                my $init = $item->inputs()->[1];
                if (defined $init && $init isa Chalk::IR::Node::VarDecl) {
                    $self->_collect_var_decls([$init], $declared_vars);
                }
                if (defined $init
                        && $init isa Chalk::IR::Node::TryCatch) {
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

            if ($node isa Chalk::IR::Node::Constant) {
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
            } elsif ($node isa Chalk::IR::Node) {
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
        # sv_setsv, hv_clear, av_clear return void — can't be wrapped as a return value
        return $val_expr if $val_expr =~ /^(?:sv_setsv|hv_clear|av_clear)\b/;
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

        if ($node isa Chalk::IR::Node::ArrayRef) {
            my $elements = $node->inputs()->[0];
            return '[]' if !$elements->@*;
        }

        if ($node isa Chalk::IR::Node::HashRef) {
            my $pairs = $node->inputs()->[0];
            return '{}' if !$pairs->@*;
        }

        if ($node isa Chalk::IR::Node::Constant) {
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
    # Walks SubscriptExpr, Return, and Unwind wrappers inward.
    method _find_exists_delete_in_chain($node) {
        my $cur = $node;
        while (defined $cur && $cur isa Chalk::IR::Node) {
            if ($cur isa Chalk::IR::Node::Call && $cur->dispatch_kind() eq 'builtin') {
                my $name = $cur->inputs()->[0]->value() // '';
                return $cur if $name eq 'exists' || $name eq 'delete';
                return;
            }
            if ($cur isa Chalk::IR::Node::Subscript) {
                $cur = $cur->inputs()->[0];
                next;
            }
            # Unwrap Return/Unwind wrappers (filter-gap merge artifacts)
            if ($cur isa Chalk::IR::Node::Return) {
                $cur = $cur->inputs()->[1];  # inputs[1] is the value
                next;
            }
            if ($cur isa Chalk::IR::Node::Unwind) {
                $cur = $cur->inputs()->[1];  # inputs[1] is exception args (arrayref)
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
        while (defined $cur && $cur isa Chalk::IR::Node) {
            if ($cur isa Chalk::IR::Node::Subscript) {
                push @subscripts, [$cur->inputs()->[1], $cur->inputs()->[2]->value()];
                $cur = $cur->inputs()->[0];
                next;
            }
            if ($cur isa Chalk::IR::Node::Call && $cur->dispatch_kind() eq 'builtin') {
                $builtin_name = $cur->inputs()->[0]->value();
                my $args = $cur->inputs()->[1];
                $base_node = $args->[0] if $args->@* > 0;
                last;
            }
            # Unwrap Return/Unwind wrappers (filter-gap merge artifacts)
            if ($cur isa Chalk::IR::Node::Return) {
                $cur = $cur->inputs()->[1];  # inputs[1] is the value
                next;
            }
            if ($cur isa Chalk::IR::Node::Unwind) {
                $cur = $cur->inputs()->[1];  # inputs[1] is exception args (arrayref)
                next;
            }
            last;
        }

        return unless defined $builtin_name && defined $base_node;

        # @subscripts is outermost-first; reverse to get innermost-first
        @subscripts = reverse @subscripts;

        my $base = $self->_emit_expr($base_node, $declared_vars);

        if ($builtin_name eq 'exists') {
            # Build chain: intermediate subscripts use av_fetch/hv_fetch,
            # last subscript uses av_exists/hv_exists_ent.
            # Typed fields (field %hash, field @array) ARE the HV*/AV* directly
            # in ObjectFIELDS — skip SvRV for them.
            my $expr = $base;
            for my $i (0 .. $#subscripts) {
                my ($idx_node, $sty) = $subscripts[$i]->@*;
                my $idx = $self->_emit_expr($idx_node, $declared_vars);
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
                my $idx = $self->_emit_expr($idx_node, $declared_vars);
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
        my $cond_expr = $self->_emit_expr($cond, $declared_vars);

        # Array variable in boolean context: check element count, not SvTRUE.
        # SvTRUE on an array reference is always true; av_len >= 0 matches
        # Perl's if (@array) semantics.
        my @lines;
        if ($cond isa Chalk::IR::Node::Constant
                && $cond->value() =~ /^\@/) {
            push @lines, "$prefix (av_len((AV*)SvRV($cond_expr)) >= 0) {";
        } else {
            push @lines, "$prefix (" . $self->_sv_true_wrap($cond_expr) . ") {";
        }
        for my $idx (0 .. $true_stmts->@* - 1) {
            my $stmt = $true_stmts->[$idx];
            my $is_last_in_then = ($idx == $true_stmts->@* - 1);
            # Stale-merge can strip Return node leaving a bare expression.
            # When in return context (method has returns), detect the last
            # bare expression and emit it as RETVAL assignment + goto.
            # Inside loops, MethodCallExpr at tail is likely a void side-effect
            # (e.g., _complete()), not a return value. Only allow unambiguous
            # value expressions (SubscriptExpr, TernaryExpr) inside loops.
            my $is_loop_safe_return = !$_loop_depth
                || $stmt isa Chalk::IR::Node::Subscript
                || $stmt isa Chalk::IR::Node::TernaryExpr;
            if ($_return_context && $is_loop_safe_return && $is_last_in_then
                    && $self->_is_bare_return_expr($stmt)) {
                my $val_expr = $self->_emit_expr($stmt, $declared_vars);
                $val_expr =~ s/^sv_2mortal\((.+)\)$/$1/;
                my $wrapped = $self->_wrap_retval($val_expr);
                # Inside scoped loops, unwind ENTER/SAVETMPS scopes before goto
                my $unwind = "FREETMPS; LEAVE; " x $_loop_depth;
                push @lines, "    ${unwind}RETVAL = $wrapped; goto xsreturn;";
                next;
            }
            my $code = $self->_emit_stmt($stmt, $declared_vars, false);
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
                my $code = $self->_emit_stmt($stmt, $declared_vars, false);
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
        my $cond_expr = $self->_emit_expr($cond, $declared_vars);

        my $region = $phi->region();
        my $values = $phi->inputs();  # arrayref of [val_a, val_b]
        my $val_a_expr = $self->_emit_expr($values->[0], $declared_vars);
        my $val_b_expr = $self->_emit_expr($values->[1], $declared_vars);

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
                    my $val = $self->_emit_expr($item, $declared_vars);
                    push @lines, "    av_push(_tmp_av, SvREFCNT_inc($val));";
                }
                push @lines, "    SSize_t _len = av_len(_tmp_av) + 1;";
                push @lines, "    SSize_t _i;";
                push @lines, "    for (_i = 0; _i < _len; _i++) {";
                push @lines, "        SV **_elem = av_fetch(_tmp_av, _i, 0);";
                push @lines, "        SV *${iter_name}_sv = (_elem && *_elem) ? *_elem : &PL_sv_undef;";
            } else {
                # Variable list: iterate existing AV
                my $list_expr = $self->_emit_expr($list, $declared_vars);
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
                my $code = $self->_emit_stmt($stmt, $declared_vars, false);
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
            if ($cond isa Chalk::IR::Node::VarDecl) {
                my $var_name = $cond->inputs()->[0]->value();
                $var_name =~ s/^[\$\@\%]//;
                my $init = $cond->inputs()->[1];
                if (defined $init
                        && $init isa Chalk::IR::Node::Call && $init->dispatch_kind() eq 'builtin'
                        && $init->inputs()->[0]->value() eq 'shift') {
                    my $shift_args = $init->inputs()->[1];
                    my $arr_arg = (ref($shift_args) eq 'ARRAY') ? $shift_args->[0] : $shift_args;
                    my $arr_expr = $self->_emit_expr($arr_arg, $declared_vars);
                    my $av_expr = ($arr_expr =~ /^\(AV\*\)/) ? $arr_expr : "(AV*)SvRV($arr_expr)";
                    $declared_vars->{$var_name} = true;
                    push @lines, "while ((${var_name}_sv = av_shift($av_expr)) != &PL_sv_undef) {";
                } else {
                    my $cond_expr = $self->_emit_expr($cond, $declared_vars);
                    push @lines, "while (" . $self->_sv_true_wrap($cond_expr) . ") {";
                }
            # Detect while (@array): array variable in boolean context
            # should check element count, not SvTRUE (which is always true
            # for a reference). Emit av_len >= 0 for proper empty-array check.
            } elsif ($cond isa Chalk::IR::Node::Constant
                    && $cond->value() =~ /^\@/) {
                my $cond_expr = $self->_emit_expr($cond, $declared_vars);
                push @lines, "while (av_len((AV*)SvRV($cond_expr)) >= 0) {";
            } else {
                my $cond_expr = $self->_emit_expr($cond, $declared_vars);
                push @lines, "while (" . $self->_sv_true_wrap($cond_expr) . ") {";
            }

            # Scope boundary frees mortal SVs per iteration instead of per-function
            push @lines, "    ENTER; SAVETMPS;";
            $_loop_depth++;
            for my $stmt ($body_stmts->@*) {
                my $code = $self->_emit_stmt($stmt, $declared_vars, false);
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
            if ($cond isa Chalk::IR::Node::VarDecl) {
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
            my $code = $self->_emit_stmt($stmt, $declared_vars, false);
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
            my $code = $self->_emit_stmt($stmt, $declared_vars, false);
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
    method _emit_stmt($node, $declared_vars, $is_last = true) {
        return undef unless defined $node;

        # Check cfg_state lookup for control flow dispatch
        if ($self->_get_cfg_lookup()->%* && ref($node)) {
            my $state = $self->_get_cfg_lookup()->{refaddr($node)};
            if (defined $state) {
                if (defined $state->{if_node}) {
                    # loop_jump: emit 'if (!cond) continue;' instead of block
                    if (defined $state->{loop_jump}) {
                        return $self->_emit_loop_jump(
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

        # Typed node fast-path: handle computation types before falling through
        # to Constructor class-string dispatch for legacy untyped nodes.
        if ($node isa Chalk::IR::Node::VarDecl) { return $self->_emit_var_decl($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::Return)  { return $self->_emit_return_stmt($node, $declared_vars, $is_last); }
        if ($node isa Chalk::IR::Node::Unwind)  { return $self->_emit_die_call($node, $declared_vars); }

        # Typed IR nodes that aren't VarDecl: emit as expression statements
        if ($node isa Chalk::IR::Node) {
            return $self->_emit_expr($node, $declared_vars) . ";";
        }

        if ($node isa Chalk::IR::Node::Constant) {
            # Loop control keywords: next->continue, last->break, return->return in C
            my $val = $node->value() // '';
            # Inside scoped loops (ENTER/SAVETMPS per iteration), must
            # FREETMPS/LEAVE before continue/break to avoid leaking the scope.
            if ($val eq 'next')   { return $self->_get_loop_depth() ? "{ FREETMPS; LEAVE; continue; }" : "continue;"; }
            if ($val eq 'last')   { return $self->_get_loop_depth() ? "{ FREETMPS; LEAVE; break; }" : "break;"; }
            if ($val eq 'return') { return "return;"; }
            return $self->_emit_expr($node, $declared_vars) . ";";
        }

        return "/* unknown node */";
    }

    method _emit_const_expr($node, $declared_vars) {
        my $val = $node->value();
        my $ct  = $node->const_type();

        # Variable reference — look up from hash or local C var
        if ($ct eq 'variable' || $val =~ /^[\$\@\%]/) {
            my $var = $val;
            $var =~ s/^[\$\@\%]//;
            # $#$arrayref — last index of array referenced by scalar
            # IR value: $#$item_types -> after sigil strip: #$item_types
            # Also handles $#array -> after sigil strip: #array
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
            # globals set by _emit_regex_match wrapper
            if ($var =~ /^\d+$/) {
                return "get_sv(\"::_c$var\", GV_ADD)";
            }
            # Class-scope static variable — check before declared_vars because
            # _collect_var_decls may create a local SV* for VarDecl in the
            # method body, but the actual shared value lives in the static.
            if ($self->_get_class_scope_vars()->%* && exists $self->_get_class_scope_vars()->{$var}) {
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
                if ($self->_get_class_scope_vars()->%* && exists $self->_get_class_scope_vars()->{$var}) {
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
        if ($self->_get_use_constants()->%* && exists $self->_get_use_constants()->{$val}) {
            return "sv_2mortal(newSViv(${\$self->_get_use_constants()->{$val}}))";
        }

        # String literal — sv_2mortal prevents leaks when used as sub-expressions
        my $escaped = $self->_escape_c_string($val);
        return "sv_2mortal(newSVpvs(\"$escaped\"))";
    }

    method _emit_interp_expr($node, $declared_vars) {
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
                # globals set by _emit_regex_match wrapper
                if ($var =~ /^\d+$/) {
                    $src = "get_sv(\"::_c$var\", GV_ADD)";
                } elsif ($self->_get_class_scope_vars()->%* && exists $self->_get_class_scope_vars()->{$var}) {
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

    method _emit_binary_expr($node, $declared_vars) {
        my $op    = $node->inputs()->[0]->value();
        my $left  = $self->_emit_expr($node->inputs()->[1], $declared_vars);
        my $right = $self->_emit_expr($node->inputs()->[2], $declared_vars);

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

        # Numeric ops — sv_2mortal prevents leaks when used as sub-expressions.
        # Type specialization: when operands are known Int (from emitted C
        # expression patterns), use SvIV/newSViv for integer arithmetic.
        if ($op eq '+' || $op eq '-' || $op eq '*') {
            my $l_int = _is_int_expr($left);
            my $r_int = _is_int_expr($right);
            if ($l_int && $r_int) {
                my $l_val = $l_int ? _extract_int_val($left) : "SvIV($left)";
                my $r_val = $r_int ? _extract_int_val($right) : "SvIV($right)";
                return "sv_2mortal(newSViv($l_val $op $r_val))";
            }
            return "sv_2mortal(newSVnv(SvNV($left) $op SvNV($right)))";
        }
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
        # Guard against arrayrefs: filter-gap merge in the IR can replace
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

    method _emit_unary_expr($node, $declared_vars) {
        my $op      = $node->inputs()->[0]->value();
        my $operand = $self->_emit_expr($node->inputs()->[1], $declared_vars);

        if ($op eq '!')   { return "(SvTRUE($operand) ? &PL_sv_no : &PL_sv_yes)"; }
        if ($op eq 'not') { return "(SvTRUE($operand) ? &PL_sv_no : &PL_sv_yes)"; }
        if ($op eq '-')   { return "sv_2mortal(newSVnv(-SvNV($operand)))"; }
        if ($op eq '\\')  { return "newRV_inc($operand)"; }
        if ($op eq '$#')  { return "sv_2mortal(newSViv(av_len((AV*)SvRV($operand))))"; }

        return "NULL /* unsupported unary: $op */";
    }

    method _emit_subscript_expr($node, $declared_vars) {
        my $target = $node->inputs()->[0];
        my $index  = $node->inputs()->[1];
        my $style  = $node->inputs()->[2]->value();

        # Handle exists/delete with misparented subscript chain:
        # IR produces SubscriptExpr(BuiltinCall(exists, [$var]), $key) or
        # SubscriptExpr(Return(ctrl, BuiltinCall(exists, [$var])), $key)
        # Collect the full subscript chain and emit native C exists/delete.
        {
            my $builtin = $self->_find_exists_delete_in_chain($node);
            if (defined $builtin) {
                my $native = $self->_build_exists_delete_native($node, $declared_vars);
                return $native if defined $native;
            }
        }

        # Handle filter-gap merge artifact: return [EXPR] admitted as
        # SubscriptExpr("return", EXPR, "array") instead of Return(ctrl, [EXPR]).
        # The inner EXPR (e.g., map builtin) already produces the array content,
        # so emit it directly — the map handler wraps results in newRV_noinc(AV*).
        if ($style eq 'array'
                && defined $target
                && $target isa Chalk::IR::Node::Constant
                && $target->value() eq 'return') {
            return $self->_emit_expr($index, $declared_vars);
        }

        # Coderef call: $f->($arg1, $arg2) — emit call_sv with arguments.
        if ($style eq 'call') {
            # __SUB__->() recursion: emit direct C call to current static helper.
            # The Earley parser admits a derivation without an __SUB__ invocant
            # via filter-gap merge, so target is undef. Detect: undef target +
            # inside a my sub body. ASSUMPTION: the only coderef calls with
            # undef target inside my-sub bodies are __SUB__ recursion. If a
            # different coderef call (e.g., $callback->($arg)) is similarly
            # missing its target via filter-gap merge, this heuristic would
            # incorrectly emit a self-recursive call.
            my $is_sub_recursion = (!defined $target
                && length $self->_get_current_sub_name());
            if ($is_sub_recursion) {
                my $helper_name = $self->_get_current_slug() . '_' . $self->_get_current_sub_name();
                my @c_args;
                if (ref($index) eq 'ARRAY') {
                    for my $arg ($index->@*) {
                        push @c_args, $self->_emit_expr($arg, $declared_vars);
                    }
                } elsif (defined $index) {
                    push @c_args, $self->_emit_expr($index, $declared_vars);
                }
                my $call_args = @c_args
                    ? 'aTHX_ ' . join(', ', @c_args)
                    : 'aTHX';
                return "$helper_name($call_args)";
            }

            my $tgt = defined $target
                ? $self->_emit_expr($target, $declared_vars)
                : 'self';
            my @push_stmts;
            if (ref($index) eq 'ARRAY') {
                for my $arg ($index->@*) {
                    my $arg_expr = $self->_emit_expr($arg, $declared_vars);
                    push @push_stmts, "XPUSHs($arg_expr)";
                }
            } elsif (defined $index) {
                my $arg_expr = $self->_emit_expr($index, $declared_vars);
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
                ? $self->_emit_expr($target, $declared_vars)
                : 'self';
            return "({ dSP; ENTER; SAVETMPS; PUSHMARK(SP); PUTBACK; "
                 . "call_sv($tgt, G_SCALAR); SPAGAIN; SV *_cr = SvREFCNT_inc(POPs); "
                 . "PUTBACK; FREETMPS; LEAVE; _cr; })";
        }

        my $tgt = defined $target
            ? $self->_emit_expr($target, $declared_vars)
            : 'self';

        # Built-in Perl hash variables (%ENV, %SIG, %INC) are compiled by
        # _emit_const_expr as get_sv (scalar lookup), but subscript access
        # needs get_hv (hash lookup). Detect and fix: wrap get_hv result in a
        # reference so the SvRV dereference below works correctly.
        if ($style eq 'hash' && defined $target) {
            my $is_const = $target isa Chalk::IR::Node::Constant;
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
            my $idx = $self->_emit_expr($index, $declared_vars);
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
        my $key = $self->_emit_expr($index, $declared_vars);
        # SvPV atomically stringifies and returns both pointer and length.
        # SvPV_nolen + SvCUR is unsafe: SvCUR on a pure IV reads garbage memory.
        return "({ SV *_hk = $key; STRLEN _hkl; char *_hkp = SvPV(_hk, _hkl); (*hv_fetch($hv, _hkp, _hkl, 1)); })";
    }

    method _emit_postfix_deref_expr($node, $declared_vars) {
        my $target = $node->inputs()->[0];
        my $sigil  = $node->inputs()->[1]->value();

        my $tgt = defined $target
            ? $self->_emit_expr($target, $declared_vars)
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

    method _emit_ternary_expr($node, $declared_vars) {
        my $cond  = $self->_emit_expr($node->inputs()->[0], $declared_vars);
        my $true  = $self->_emit_expr($node->inputs()->[1], $declared_vars);
        my $false = $self->_emit_expr($node->inputs()->[2], $declared_vars);

        return "(SvTRUE($cond) ? $true : $false)";
    }

    method _emit_hash_ref_expr($node, $declared_vars) {
        my $pairs = $node->inputs()->[0];
        if (!$pairs->@*) {
            return "newRV_noinc((SV*)newHV())";
        }
        # Populate hash with key/value pairs via hv_store
        my @stores;
        for (my $i = 0; $i < $pairs->@*; $i += 2) {
            my $key_node = $pairs->[$i];
            # Detect hash spread: %$var as a key means copy all entries from var
            if ($key_node isa Chalk::IR::Node::Constant
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
            my $key = $self->_emit_expr($key_node, $declared_vars);
            my $val = $self->_emit_expr($pairs->[$i + 1], $declared_vars);
            # SvPV atomically stringifies: SvPV_nolen + SvCUR is unsafe on pure IVs
            push @stores, "{ SV *_hk = $key; STRLEN _hkl; char *_hkp = SvPV(_hk, _hkl); hv_store(_hv, _hkp, _hkl, SvREFCNT_inc($val), 0); }";
        }
        return "({ HV *_hv = newHV(); " . join("; ", @stores) . "; newRV_noinc((SV*)_hv); })";
    }

    method _emit_array_ref_expr($node, $declared_vars) {
        my $elements = $node->inputs()->[0];
        if (!$elements->@*) {
            return "newRV_noinc((SV*)newAV())";
        }
        # Populate array with elements via av_push
        my @pushes;
        for my $elem ($elements->@*) {
            my $val = $self->_emit_expr($elem, $declared_vars);
            push @pushes, "av_push(_av, SvREFCNT_inc($val))";
        }
        return "({ AV *_av = newAV(); " . join("; ", @pushes) . "; newRV_noinc((SV*)_av); })";
    }

    method _emit_regex_match($node, $declared_vars) {
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
                my $tgt = $self->_emit_expr($target, $declared_vars);
                return "({ sv_setsv(DEFSV, $tgt); eval_pv(\"$escaped\", TRUE); })";
            }
            return "eval_pv(\"$escaped\", TRUE)";
        }

        # Build a unique static variable name for the compiled regex
        my $rx_var = "_rx_" . $self->_inc_regex_counter();

        # Wrap flags as inline modifiers: pattern -> (?flags:pattern)
        my $full_pat = length($flags) ? "(?$flags:$raw_pat)" : $raw_pat;

        # Escape the pattern for C string literal
        my $c_pat = $self->_escape_c_string($full_pat);

        # Store regex patterns to declare as statics at top of generated file
        $self->_push_regex_static({ var => $rx_var, pat => $c_pat });

        my $tgt;
        if (defined $target) {
            $tgt = $self->_emit_expr($target, $declared_vars);
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

    method _emit_regex_subst($node, $declared_vars) {
        my $target      = $node->inputs()->[0];
        my $pattern     = $node->inputs()->[1]->value();
        my $replacement = $node->inputs()->[2]->value();
        my $flags       = $node->inputs()->[3]->value();

        my $escaped = $self->_escape_c_string("\$_ =~ s/$pattern/$replacement/$flags");
        if (defined $target) {
            my $tgt = $self->_emit_expr($target, $declared_vars);
            return "({ sv_setsv(DEFSV, $tgt); eval_pv(\"$escaped\", TRUE); sv_setsv($tgt, DEFSV); $tgt; })";
        }
        return "eval_pv(\"$escaped\", TRUE)";
    }

    method _emit_keys_list($hash_node, $declared_vars) {
        my $hash = $self->_emit_expr($hash_node, $declared_vars);
        my $hv_expr;
        if ($hash_node isa Chalk::IR::Node::PostfixDeref) {
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

    method _emit_backtick_expr($node, $declared_vars) {
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        my $cmd = $perl_target->_emit_expr($node->inputs()->[0]);
        my $escaped = $self->_escape_c_string("`$cmd`");
        return "eval_pv(\"$escaped\", TRUE)";
    }

    method _emit_compound_assign_expr($node, $declared_vars) {
        my $op     = $node->inputs()->[0]->value();
        my $target = $node->inputs()->[1];
        my $value  = $node->inputs()->[2];

        my $tgt = $self->_emit_expr($target, $declared_vars);
        my $val = $self->_emit_expr($value, $declared_vars);

        if ($op eq '.=') {
            return "({ sv_catsv($tgt, $val); $tgt; })";
        }
        if ($op eq '+=') {
            return "({ sv_setiv($tgt, SvIV($tgt) + SvIV($val)); $tgt; })";
        }
        if ($op eq '-=') {
            return "({ sv_setiv($tgt, SvIV($tgt) - SvIV($val)); $tgt; })";
        }
        if ($op eq '//=') {
            # Class-scope statics are NULL-initialized; check pointer first,
            # then use SvREFCNT_inc to take ownership of the assigned value.
            return "({ if (!$tgt || !SvOK($tgt)) { $tgt = SvREFCNT_inc_simple($val); } $tgt; })";
        }

        return "/* $op not supported */";
    }

    method _emit_var_decl_expr($node, $declared_vars) {
        my $var  = $node->inputs()->[0]->value();
        $var =~ s/^[\$\@\%]//;
        my $init = $node->inputs()->[1];

        # Field variables use ObjectFIELDS accessor with sv_setsv,
        # locals use direct C pointer assignment
        if (defined $self->_get_field_map() && exists $self->_get_field_map()->{$var}) {
            my $idx = $self->_get_field_map()->{$var};
            my $accessor = "ObjectFIELDS(SvRV(self))[$idx]";
            if (defined $init) {
                my $init_expr = $self->_emit_expr($init, $declared_vars);
                return "({ sv_setsv($accessor, $init_expr); $accessor; })";
            }
            return "({ sv_setsv($accessor, &PL_sv_undef); $accessor; })";
        }

        # Class-scope variables in expression context: evaluate init (if any)
        # and return the static. Statement-level resets (hv_clear etc.) are
        # handled by _emit_var_decl.
        if ($self->_get_class_scope_vars()->%* && exists $self->_get_class_scope_vars()->{$var}) {
            my $info = $self->_get_class_scope_vars()->{$var};
            if (defined $init) {
                my $init_expr = $self->_emit_expr($init, $declared_vars);
                return "({ $init_expr; $info->{static_name}; })";
            }
            return $info->{static_name};
        }

        my $c_var = "${var}_sv";
        if (defined $init) {
            my $init_expr = $self->_emit_expr($init, $declared_vars);
            return "({ $c_var = $init_expr; $c_var; })";
        }
        return "({ $c_var = &PL_sv_undef; $c_var; })";
    }

    method _emit_var_decl($node, $declared_vars) {
        my $raw_var = $node->inputs()->[0]->value();
        my ($sigil) = $raw_var =~ /^([\$\@\%])/;
        my $var = $raw_var;
        $var =~ s/^[\$\@\%]//;
        my $init = $node->inputs()->[1];

        # Default value for uninitialized variables depends on sigil:
        # %hash -> empty hashref, @array -> empty arrayref, $scalar -> undef
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
        if (defined $init && $init isa Chalk::IR::Node::VarDecl) {
            my $inner_stmt = $self->_emit_var_decl($init, $declared_vars);
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
            } elsif ($self->_get_class_scope_vars()->%* && exists $self->_get_class_scope_vars()->{$var}) {
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
                my $init_expr = $self->_emit_expr($init, $declared_vars);
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
        if ($self->_get_class_scope_vars()->%* && exists $self->_get_class_scope_vars()->{$var}) {
            my $info = $self->_get_class_scope_vars()->{$var};
            my $sname = $info->{static_name};
            if (defined $init) {
                my $init_expr = $self->_emit_expr($init, $declared_vars);
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
            # TryCatchStmt as VarDecl init is a filter-gap merge artifact.
            # The variable is declared with undef, then assigned inside the
            # try block. Split into: declare var, then emit try/catch statement.
            if ($init isa Chalk::IR::Node::TryCatch) {
                my $try_stmt = $self->_emit_stmt($init, $declared_vars);
                return "${var}_sv = $default_val;\n$try_stmt";
            }
            my $init_expr = $self->_emit_expr($init, $declared_vars);
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

    method _emit_return_stmt($node, $declared_vars, $is_last = true) {
        my $value = $node->inputs()->[1];  # inputs[0]=control, inputs[1]=value
        my $val_expr = $self->_emit_expr($value, $declared_vars);
        $val_expr =~ s/^sv_2mortal\((.+)\)$/$1/;
        my $retval = $self->_wrap_retval($val_expr);
        if ($is_last) {
            return "RETVAL = $retval;";
        }
        # Inside scoped loops, unwind ENTER/SAVETMPS scopes before goto
        my $unwind = "FREETMPS; LEAVE; " x $self->_get_loop_depth();
        return "${unwind}RETVAL = $retval; goto xsreturn;";
    }

    method _emit_die_call($node, $declared_vars = undef) {
        my $args = $node->inputs()->[1];
        my $msg = '';
        if (ref($args) eq 'ARRAY' && $args->@*) {
            my $first = $args->[0];
            if ($first isa Chalk::IR::Node::Constant) {
                $msg = $self->_escape_c_string($first->value());
            } elsif (defined $declared_vars) {
                # Non-constant arg (e.g. string interpolation): emit as expression
                my $expr = $self->_emit_expr($first, $declared_vars);
                return "croak(\"%s\", SvPV_nolen($expr));";
            }
        }
        return "croak(\"%s\", \"$msg\");";
    }

    method _emit_compound_assign_stmt($node, $declared_vars) {
        return $self->_emit_compound_assign_expr($node, $declared_vars) . ";";
    }

    method _emit_loop_jump($jump_keyword, $if_node, $declared_vars) {
        my $cond = $if_node->inputs()->[1];
        my $cond_expr = $self->_emit_expr($cond, $declared_vars);
        my $c_keyword = $jump_keyword eq 'last' ? 'break' : 'continue';
        # Inside scoped loops (ENTER/SAVETMPS per iteration), must
        # FREETMPS/LEAVE before continue/break to avoid leaking the scope.
        my $sv_cond = $self->_sv_true_wrap($cond_expr);
        if ($self->_get_loop_depth()) {
            return "if ($sv_cond) { FREETMPS; LEAVE; $c_keyword; }";
        }
        return "if ($sv_cond) $c_keyword;";
    }

    method _emit_expr($node, $declared_vars) {
        return 'NULL' unless defined $node;

        if ($node isa Chalk::IR::Node::Constant) {
            return $self->_emit_const_expr($node, $declared_vars);
        }

        # Typed node fast-paths for computation types during transition.
        # These nodes may arrive as either the new typed class or old Constructor.
        if ($node isa Chalk::IR::Node::Interpolate)  { return $self->_emit_interp_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::Subscript)    { return $self->_emit_subscript_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::PostfixDeref) { return $self->_emit_postfix_deref_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::VarDecl)      { return $self->_emit_var_decl_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::Return) {
            # Return used as expression: filter-gap merge artifact.
            # Unwrap and emit the inner value (inputs[1]) as an expression.
            return $self->_emit_expr($node->inputs()->[1], $declared_vars);
        }
        if ($node isa Chalk::IR::Node::Unwind) {
            # Unwind used as expression: filter-gap merge artifact.
            # Emit croak in a statement expression — croak never returns.
            my $croak = $self->_emit_die_call($node, $declared_vars);
            return "({ $croak &PL_sv_undef; })";
        }
        if ($node isa Chalk::IR::Node::Call) {
            if ($node->dispatch_kind() eq 'method')  { return $self->_emit_method_call_expr($node, $declared_vars); }
            if ($node->dispatch_kind() eq 'builtin') { return $self->_emit_builtin_call($node, $declared_vars); }
        }
        if ($node isa Chalk::IR::Node::TernaryExpr)       { return $self->_emit_ternary_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::StructRef)         { return $self->_emit_struct_ref_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::StructFieldAccess) { return $self->_emit_field_access_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::CompoundAssign)    { return $self->_emit_compound_assign_expr($node, $declared_vars); }
        if ($node isa Chalk::IR::Node::Not) {
            # Logical negation: emit as ternary that swaps yes/no.
            my $operand_expr = $self->_emit_expr($node->operand(), $declared_vars);
            return "(SvTRUE($operand_expr) ? &PL_sv_no : &PL_sv_yes)";
        }
        if ($node isa Chalk::IR::Node::And) {
            # Short-circuit &&: evaluate left; if true return right, else return PL_sv_no.
            my $left_expr  = $self->_emit_expr($node->left(),  $declared_vars);
            my $right_expr = $self->_emit_expr($node->right(), $declared_vars);
            return "(SvTRUE($left_expr) ? $right_expr : &PL_sv_no)";
        }
        if ($node isa Chalk::IR::Node::Or) {
            # Short-circuit ||: evaluate left; if true return left, else return right.
            my $left_expr  = $self->_emit_expr($node->left(),  $declared_vars);
            my $right_expr = $self->_emit_expr($node->right(), $declared_vars);
            return "(SvTRUE($left_expr) ? $left_expr : $right_expr)";
        }
        if ($node isa Chalk::IR::Node::ArrayRef) {
            # Array reference constructor: build a new AV and populate with elements.
            my $elems = $node->inputs()->[0];
            my @elem_nodes = (ref($elems) eq 'ARRAY') ? $elems->@* : ();
            if (!@elem_nodes) {
                return "sv_2mortal(newRV_noinc((SV*)newAV()))";
            }
            my @pushes;
            my $av_var = '_arr' . refaddr($node) % 9999;
            push @pushes, "AV *$av_var = newAV()";
            for my $elem (@elem_nodes) {
                my $elem_expr = $self->_emit_expr($elem, $declared_vars);
                push @pushes, "av_push($av_var, SvREFCNT_inc($elem_expr))";
            }
            push @pushes, "sv_2mortal(newRV_noinc((SV*)$av_var))";
            return '({ ' . join('; ', @pushes) . '; })';
        }

        # All computation types are now typed (via shim).
        # No Constructor computation nodes reach here.

        return "NULL /* unsupported */";
    }

    # Emit C code for StructRef: allocate SV with struct bytes, write fields.
    method _emit_struct_ref_expr($node, $declared_vars) {
        my $schema_name = $node->inputs()->[0]->value();
        my $field_vals  = $node->inputs()->[1];

        my $schema = $_struct_schemas->{$schema_name};
        unless (defined $schema) {
            return "NULL /* unknown schema $schema_name */";
        }

        my @fields = $schema->{fields}->@*;
        my @lines;
        push @lines, "SV *_struct_sv = newSV(sizeof($schema_name))";
        push @lines, "SvPOK_on(_struct_sv)";
        push @lines, "SvCUR_set(_struct_sv, sizeof($schema_name))";
        push @lines, "$schema_name *_sp = ($schema_name *)SvPVX(_struct_sv)";

        for my $i (0 .. $#fields) {
            my $fname  = $fields[$i]{name};
            my $c_type = $fields[$i]{c_type};
            my $val_node = (defined $field_vals && $i < scalar($field_vals->@*))
                ? $field_vals->[$i]
                : undef;
            my $val_expr = defined $val_node
                ? $self->_emit_expr($val_node, $declared_vars)
                : ($c_type eq 'IV' ? '0' : 'NULL');

            if ($c_type eq 'IV') {
                # IV field: extract integer from SV
                push @lines, "_sp->$fname = SvIV($val_expr)";
            } else {
                # SV* field: store pointer directly
                push @lines, "_sp->$fname = $val_expr";
            }
        }

        return "({ " . join("; ", @lines) . "; _struct_sv; })";
    }

    # Emit C code for FieldAccess: cast SvPVX to struct pointer, access field.
    method _emit_field_access_expr($node, $declared_vars) {
        my $schema_name = $node->inputs()->[0]->value();
        my $field_name  = $node->inputs()->[1]->value();
        my $target      = $node->inputs()->[2];

        my $tgt = defined $target
            ? $self->_emit_expr($target, $declared_vars)
            : 'self';

        my $schema = $_struct_schemas->{$schema_name};
        my $c_type = 'SV *';  # default
        if (defined $schema) {
            for my $f ($schema->{fields}->@*) {
                if ($f->{name} eq $field_name) {
                    $c_type = $f->{c_type};
                    last;
                }
            }
        }

        my $access = "(($schema_name *)SvPVX($tgt))->$field_name";

        if ($c_type eq 'IV') {
            # IV field: wrap in newSViv for SV* context
            return "newSViv($access)";
        }

        return $access;
    }

    # Public wrappers for testing emit methods directly.
    method emit_struct_ref($node, $declared_vars) {
        return $self->_emit_struct_ref_expr($node, $declared_vars);
    }

    method emit_field_access($node, $declared_vars) {
        return $self->_emit_field_access_expr($node, $declared_vars);
    }

    # Generate C typedef declarations for all struct schemas.
    method generate_typedefs() {
        return '' unless keys $_struct_schemas->%*;

        my @typedefs;
        for my $sname (sort keys $_struct_schemas->%*) {
            my @fields = $_struct_schemas->{$sname}{fields}->@*;
            my @field_lines;
            for my $f (@fields) {
                my $pad = ($f->{c_type} eq 'IV') ? '   ' : '';
                push @field_lines, "    $f->{c_type}$pad $f->{name};";
            }
            push @typedefs, "typedef struct {\n"
                . join("\n", @field_lines) . "\n"
                . "} $sname;";
        }

        return join("\n\n", @typedefs) . "\n";
    }

    # Check if a C expression is known to produce an integer value.
    # Used by _emit_binary_expr for type-directed operator specialization.
    sub _is_int_expr($expr) {
        # sv_2mortal(newSViv(...)) — integer wrapped in mortal
        return true if $expr =~ /^sv_2mortal\(newSViv\(/;
        return false;
    }

    # Extract the integer value from a known-integer C expression.
    # Returns a C expression suitable for use in arithmetic.
    sub _extract_int_val($expr) {
        # sv_2mortal(newSViv(N)) → N (parenthesized to preserve C precedence)
        if ($expr =~ /^sv_2mortal\(newSViv\((.+)\)\)$/) {
            return "($1)";
        }
        # newSViv(N) inside other wrappers → SvIV(expr)
        return "SvIV($expr)";
    }

}

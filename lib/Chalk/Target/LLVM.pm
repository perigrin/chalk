# ABOUTME: SoN->LLVM IR lowering pass for the typed-representation model (G4 Array/Hash added).
# ABOUTME: Lowers typed SoN graphs to LLVM IR text: arithmetic, control-flow, Str, and Array/Hash aggregates.
package Chalk::Target::LLVM;
use 5.42.0;
use utf8;

# I4/I5: LLVM is the typed-IR-tier backend; it isa Chalk::IR::Target (not Chalk::Target).
# Chalk::Target is the Bootstrap-tier base (generate/generate_distribution);
# Chalk::IR::Target is the typed-IR-tier base (lower). Keeping them separate ensures
# Bootstrap targets do not inherit an alien lower() stub.
use parent 'Chalk::IR::Target';

use Chalk::IR::Node::Coerce;
use Chalk::IR::Schedule::Dominators;
use Chalk::IR::Schedule::Elaborate;
use Chalk::IR::ClassInfo;
use Chalk::IR::MethodInfo;
use Chalk::MOP::Field;

# lower($return_node) -> $llvm_ir_text
#
# Accepts a Return node whose value chain is typed (each value-def carries a
# representation). Emits LLVM IR text that, when run through lli, prints the
# computed value and exits 0.
#
# Supported representations: Int (i64), Num (double). Scalar is a GAP.
#
# Observable output: printf with the correct format per result representation:
#   Int -> "%d\n"  (printed as decimal integer)
#   Num -> "%g\n"  (printed as shortest decimal, matches perl's default)
#
# No libperl: this backend does not link or call any Perl C-API function.
# A value of representation Scalar reaching this backend is a GAP.
#
# Supported ops:
#   Constant (Int or Num)
#   Add, Subtract, Multiply (Int -> i64 add/sub/mul)
#   Divide (Num -> fdiv double; Int repr on Divide is a GAP — Perl / is float)
#   Modulo (Int -> perl-semantics sign-corrected srem)
#   Coerce (Int->Num: sitofp; Num->Int: fptosi)
#   And, Or (short-circuit branch+phi)
#   If, Region, Proj (conditional branch with merge phi)
#   Loop (loop header with back-edge and phi)
#
# Placement rationale: this is a production backend, not test infrastructure.
# lib/Chalk/IR/Target/ is the natural home for named lowering targets
# (parallel to the C/XS corner). Keeping it here avoids the drift pattern
# of temporary t/lib infrastructure that never gets promoted.
# lower($class, $return_node) -> $llvm_ir_text
#
# Main entry point. Builds the dominator tree + scoped-elaboration pass
# automatically from the return node, then delegates to lower_with_elaboration.
# Placement is driven by the Elaborate pass; defs-dominate-uses holds by
# construction via the scoped value map.
sub lower {
    my ($class, $return_node) = @_;

    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($return_node);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($return_node, $dom);
    return $class->lower_with_elaboration($return_node, $elab);
}

# _encode_c_string($str) -> LLVM c"..." compatible escaped string (module-level helper)
#
# Converts a Perl string to the LLVM c"..." literal encoding.
# In LLVM IR, c"..." accepts \XX hex escapes for non-printable bytes and
# backslash characters. The NUL terminator is added by the caller.
#
# For ASCII printable chars (0x20-0x7E except \ and "), emit as-is.
# For all others and for \ and ", emit as \XX (2 hex digits).
# _require_repr($node, $where) -> $repr
#
# Assert that $node has a defined representation and return it. Dies loudly
# (GAP) if representation is undef, naming $where so callers can locate the
# offending site. Used at every lowering site that reads node->representation
# to prevent silent undef -> 'Int' defaulting which masks TypeInference gaps.
#
# Distinction from the outer `defined $node ? (...) : 'Int'` pattern: that
# outer default handles a *missing optional node* (legitimate — e.g. a method
# body that has not been wired yet). This helper guards a *present node* whose
# representation field was never set, which is always a TypeInference gap.
sub _require_repr {
    my ($node, $where) = @_;
    my $r = $node->representation;
    die "GAP: $where reached LLVM backend with NO representation (undef) — "
      . "fix TypeInference so this node carries an explicit repr before lowering."
        unless defined $r;
    return $r;
}

sub _encode_c_string {
    my ($str) = @_;
    my $out = '';
    for my $i (0 .. length($str) - 1) {
        my $byte = ord(substr($str, $i, 1));
        if ($byte >= 0x20 && $byte <= 0x7e && $byte != ord('\\') && $byte != ord('"')) {
            $out .= chr($byte);
        } else {
            $out .= sprintf('\\%02X', $byte);
        }
    }
    return $out;
}

# _emit_str_to_num_helper() -> LLVM IR text for the @chalk_str_to_num helper function
#
# Emits a module-level helper that implements perl's leading-numeric rule:
#   - Skip leading ASCII whitespace (0x09,0x0A,0x0B,0x0C,0x0D,0x20)
#   - If the non-whitespace start is "0x" or "0X", return 0.0 immediately
#     (perl does NOT parse hex: "0x10" -> 0, not 16)
#   - Otherwise call libc strtod on the remaining bytes
#   - strtod handles sign, digits, decimal point, exponent — matching perl exactly
#     for all other leading-numeric forms
#
# This is a runtime-free implementation (strtod is host-C, not libperl).
# The helper is defined as internal linkage (not exported).
#
# Algorithm in LLVM IR pseudo-code:
#   ptr2 = ptr + skip_whitespace(ptr, len)
#   rem_len = len - (ptr2 - ptr)
#   if rem_len >= 2 && ptr2[0]=='0' && (ptr2[1]=='x'||ptr2[1]=='X'): return 0.0
#   endptr = null
#   result = strtod(ptr2, &endptr)
#   return result
#
# We use a simple loop for whitespace-skipping.
sub _emit_str_to_num_helper {
    # The helper is emitted as LLVM IR text. We use a direct implementation
    # with a loop for whitespace skipping and a branch for the 0x check.
    return <<'END_HELPER';
define internal double @chalk_str_to_num(i8* %ptr, i64 %len) {
entry:
  ; Whitespace skip: advance ptr while current byte is whitespace and within len.
  ; Whitespace chars: tab(9) LF(10) VT(11) FF(12) CR(13) space(32).
  ; We use a loop: %cur_ptr iterates forward, %remaining counts bytes left.
  br label %ws_check

ws_check:
  %cur_ptr = phi i8* [ %ptr, %entry ], [ %next_ptr, %ws_body ]
  %remaining = phi i64 [ %len, %entry ], [ %rem_next, %ws_body ]
  %have_bytes = icmp sgt i64 %remaining, 0
  br i1 %have_bytes, label %ws_load, label %after_ws

ws_load:
  %byte = load i8, i8* %cur_ptr
  %b_as_i32 = sext i8 %byte to i32
  ; Check: is byte a whitespace char? (9,10,11,12,13,32)
  %is_tab   = icmp eq i32 %b_as_i32, 9
  %is_lf    = icmp eq i32 %b_as_i32, 10
  %is_vt    = icmp eq i32 %b_as_i32, 11
  %is_ff    = icmp eq i32 %b_as_i32, 12
  %is_cr    = icmp eq i32 %b_as_i32, 13
  %is_sp    = icmp eq i32 %b_as_i32, 32
  %is_ws1   = or i1 %is_tab, %is_lf
  %is_ws2   = or i1 %is_vt, %is_ff
  %is_ws3   = or i1 %is_cr, %is_sp
  %is_ws12  = or i1 %is_ws1, %is_ws2
  %is_ws    = or i1 %is_ws12, %is_ws3
  br i1 %is_ws, label %ws_body, label %after_ws

ws_body:
  %next_ptr = getelementptr inbounds i8, i8* %cur_ptr, i64 1
  %rem_next = sub i64 %remaining, 1
  br label %ws_check

after_ws:
  ; cur_ptr now points to first non-whitespace byte (or end of string).
  ; remaining = bytes left from cur_ptr.
  %rem_after = phi i64 [ %remaining, %ws_check ], [ %remaining, %ws_load ]
  %ptr_after = phi i8* [ %cur_ptr, %ws_check ], [ %cur_ptr, %ws_load ]

  ; Check for "0x" or "0X" prefix -> return 0.0 immediately.
  ; Only if remaining >= 2 and ptr_after[0]=='0' and ptr_after[1]=='x'|'X'.
  %have_two = icmp sge i64 %rem_after, 2
  br i1 %have_two, label %check_0x, label %call_strtod

check_0x:
  %b0 = load i8, i8* %ptr_after
  %is_zero = icmp eq i8 %b0, 48    ; '0' = 48
  br i1 %is_zero, label %check_x, label %call_strtod

check_x:
  %ptr1 = getelementptr inbounds i8, i8* %ptr_after, i64 1
  %b1 = load i8, i8* %ptr1
  %is_lc_x = icmp eq i8 %b1, 120  ; 'x' = 120
  %is_uc_x = icmp eq i8 %b1, 88   ; 'X' = 88
  %is_hex = or i1 %is_lc_x, %is_uc_x
  br i1 %is_hex, label %return_zero, label %call_strtod

return_zero:
  ret double 0.0

call_strtod:
  ; Use ptr_after (whitespace-skipped) for strtod. strtod handles the rest.
  ; endptr can be null (we don't need it).
  %result = call double @strtod(i8* %ptr_after, i8** null)
  ret double %result
}
END_HELPER
}

# _method_fn_type($result_repr) -> LLVM fn type string (no asterisk; add * for ptr)
# Returns the LLVM function TYPE string for a method with the given result repr.
# Used in both vtable bitcast expressions and call-site casts.
sub _method_fn_type {
    my ($result_repr) = @_;
    return 'i64 (i8*)' if !defined $result_repr || $result_repr eq 'Int';
    return '%StrPair (i8*)' if $result_repr eq 'Str';
    return 'i1 (i8*)'   if $result_repr eq 'Bool';
    return 'double (i8*)' if $result_repr eq 'Num';
    die "LLVM MOP: unsupported method return repr '$result_repr'";
}

# _method_fn_llvm_ret_type($repr) -> LLVM return type for method function header
sub _method_fn_llvm_ret_type {
    my ($repr) = @_;
    return 'i64'      if !defined $repr || $repr eq 'Int';
    return '%StrPair' if $repr eq 'Str';
    return 'i1'       if $repr eq 'Bool';
    return 'double'   if $repr eq 'Num';
    die "LLVM MOP: unsupported method return repr '$repr' for fn return type";
}

# ---------------------------------------------------------------------------
# Class registry: scan graph for ClassDecl/MethodDef/FieldDef/ClassInfo nodes.
# ---------------------------------------------------------------------------

# _class_name_from_class_node($node) -> $name
#
# Returns the class name from either a ClassDecl (->class_name) or a
# ClassInfo (->name). Dies if neither accessor is available.
sub _class_name_from_class_node {
    my ($node) = @_;
    return undef unless defined $node;
    # ClassInfo uses ->name; ClassDecl uses ->class_name
    return $node->name       if $node->can('name') && !$node->can('class_name');
    return $node->class_name if $node->can('class_name');
    return $node->name       if $node->can('name');
    die "LLVM MOP: cannot determine class name from node type " . ref($node);
}

# _populate_registry_from_classinfo(\%registry, $ci) -> void
#
# Populates %registry from a Chalk::IR::ClassInfo object.
# Mirrors the ClassDecl path in _scan_class_registry so downstream
# emission (_emit_class_registry_ir) is unchanged.
sub _populate_registry_from_classinfo {
    my ($registry, $ci) = @_;
    my $cname = $ci->name;
    $registry->{$cname} //= { methods => [], fields => [], adjusts => [], parent => undef };
    $registry->{$cname}{parent} //= $ci->parent;

    my $mslot = scalar @{ $registry->{$cname}{methods} };

    # Methods from ClassInfo->methods (each is a MethodInfo)
    for my $mi (@{ $ci->methods // [] }) {
        my $mname     = $mi->name;
        my $body_node = $mi->body_node;
        # Derive return_repr from body_node's representation if body_node is present
        # and return_repr field was not explicitly set; use 'Int' as fallback.
        my $ret_repr;
        if (defined $mi->return_repr) {
            $ret_repr = $mi->return_repr;
        } elsif (defined $body_node) {
            $ret_repr = _require_repr($body_node, 'MethodInfo.body_node');
        } else {
            $ret_repr = 'Int';
        }
        unless (grep { ($_->{name} // '') eq $mname } @{ $registry->{$cname}{methods} }) {
            push @{ $registry->{$cname}{methods} }, {
                name        => $mname,
                body_node   => $body_node,
                return_repr => $ret_repr,
                vtable_slot => $mslot++,
            };
        }
    }

    # Fields from ClassInfo->fields (each is a MOP::Field)
    for my $mf (@{ $ci->fields // [] }) {
        my $fname       = $mf->name;
        my $fidx        = $mf->fieldix;
        my $is_param    = $mf->is_param    // false;
        my $has_reader  = $mf->has_reader  // false;
        my $has_default = $mf->has_default // false;
        my $def_node    = $mf->default_value;
        my $f_repr      = $mf->type // 'Int';
        unless (grep { ($_->{field_index} // -1) == $fidx } @{ $registry->{$cname}{fields} }) {
            push @{ $registry->{$cname}{fields} }, {
                name         => $fname,
                field_index  => $fidx,
                is_param     => $is_param,
                has_reader   => $has_reader,
                has_default  => $has_default,
                default_node => $def_node,
                field_repr   => $f_repr,
            };
        }
        # :reader synthesis
        if ($has_reader) {
            unless (grep { ($_->{name} // '') eq $fname } @{ $registry->{$cname}{methods} }) {
                push @{ $registry->{$cname}{methods} }, {
                    name               => $fname,
                    body_node          => undef,
                    return_repr        => $f_repr,
                    vtable_slot        => $mslot++,
                    is_reader_synth    => 1,
                    reader_field_index => $fidx,
                };
            }
        }
    }

    # adjusts: each entry is an arrayref of body IR nodes (the ADJUST block statements)
    for my $adj_nodes (@{ $ci->adjusts // [] }) {
        # adj_nodes is an arrayref of IR nodes (field stores, etc.)
        push @{ $registry->{$cname}{adjusts} }, {
            body_nodes => (ref $adj_nodes eq 'ARRAY' ? $adj_nodes : [$adj_nodes]),
        };
    }
}

# _scan_class_registry($return_node) -> \%registry
#
# Walks all reachable nodes from $return_node and collects:
#   ClassDecl nodes -> class name, parent name
#   MethodDef nodes -> method name, body_node, return_repr, owning class
#   FieldDef nodes  -> field metadata, owning class
#
# Returns a hashref: { class_name => { methods => [...], fields => [...], parent => str } }
# where each method entry is { name, vtable_slot, body_node, return_repr }
# and each field entry is { name, field_index, is_param, has_reader, has_default, default_node }.
sub _scan_class_registry {
    my ($return_node) = @_;

    my %registry;  # class_name -> { methods, fields, parent, adjusts }
    my %visited;

    # Walk the entire reachable graph
    my @queue = ($return_node);
    while (@queue) {
        my $node = shift @queue;
        next unless defined $node;
        my $id = $node->id;
        next if $visited{$id}++;

        # ClassInfo: canonical metadata object (no ->operation method).
        # Populate registry directly from its fields/methods.
        if (ref($node) && $node->isa('Chalk::IR::ClassInfo')) {
            _populate_registry_from_classinfo(\%registry, $node);
            # ClassInfo has no ->inputs; its methods/fields are embedded.
            # Enqueue MethodInfo body_nodes so their sub-graphs are reachable.
            for my $mi (@{ $node->methods // [] }) {
                push @queue, $mi->body_node if defined $mi->body_node;
            }
            # Enqueue parent_ci so the parent's registry entry is populated.
            push @queue, $node->parent_ci if $node->can('parent_ci') && defined $node->parent_ci;
            next;
        }

        my $op = $node->can('operation') ? $node->operation : '';

        # Enqueue all inputs
        if ($node->can('inputs') && defined $node->inputs) {
            push @queue, grep { defined $_ } $node->inputs->@*;
        }
        if ($node->can('control_in') && defined $node->control_in) {
            push @queue, $node->control_in;
        }
    }

    # Resolve :isa inheritance: for each class with a parent, copy inherited
    # method slots from the parent into the child's vtable (compile-time MRO flatten).
    # This is done AFTER the full scan so all parent classes are in the registry.
    for my $cname (keys %registry) {
        my $parent = $registry{$cname}{parent};
        next unless defined $parent;
        my $parent_reg = $registry{$parent};
        unless (defined $parent_reg) {
            die "LLVM MOP: class '$cname' has :isa($parent) but '$parent' is not declared in this graph";
        }
        # Copy parent methods into child that don't already exist in child
        for my $pmeth (@{ $parent_reg->{methods} }) {
            unless (grep { ($_->{name} // '') eq $pmeth->{name} } @{ $registry{$cname}{methods} }) {
                push @{ $registry{$cname}{methods} }, {
                    %$pmeth,
                    vtable_slot => scalar(@{ $registry{$cname}{methods} }),
                    inherited_from => $parent,
                };
            }
        }
    }

    return \%registry;
}

# _emit_class_registry_ir(\%registry, $ctx) -> @llvm_lines
#
# Emits all class-related LLVM IR declarations: type defs, vtable globals,
# class-name constants, and method body define functions.
# Returns a list of LLVM IR text lines to prepend to the module.
sub _emit_class_registry_ir {
    my ($registry, $ctx) = @_;
    my @lines;

    # Determine if any method returns Str -> need %StrPair type
    my $need_strpair = 0;
    for my $cname (sort keys %$registry) {
        my $reg = $registry->{$cname};
        for my $m (@{ $reg->{methods} }) {
            $need_strpair = 1 if ($m->{return_repr} // '') eq 'Str';
        }
    }

    if ($need_strpair) {
        push @lines, '; StrPair: {i8* ptr, i64 len} for Str method return values';
        push @lines, '%StrPair = type { i8*, i64 }';
        $ctx->{_need_strpair} = 1;
        $ctx->{_strpair_emitted} = 1;  # I3: track emission to prevent double-declare in post-class re-emit
    }

    for my $cname (sort keys %$registry) {
        my $reg     = $registry->{$cname};
        my $methods = $reg->{methods} // [];
        my $fields  = $reg->{fields}  // [];

        # Sort fields by field_index to ensure consistent struct layout
        my @sorted_fields = sort { ($a->{field_index} // 0) <=> ($b->{field_index} // 0) } @$fields;

        # 1. Vtable type: { i8* class-name, i8* slot0, i8* slot1, ... }
        my $vt_type = '%' . $cname . '.vt';
        my $n_slots = scalar @$methods;
        my @vt_elems = ('i8*');  # slot 0 = class-name ptr
        push @vt_elems, ('i8*') x $n_slots;
        push @lines, "$vt_type = type { " . join(', ', @vt_elems) . " }  ; vtable for $cname";

        # 2. Object struct type: { %Cls.vt*, %Slot, %Slot, ... }
        my $obj_type = '%' . $cname . '.obj';
        my @obj_elems = ($vt_type . '*');  # slot 0 = vtable ptr
        push @obj_elems, ('%Slot') x scalar(@sorted_fields);  # one %Slot per field
        push @lines, "$obj_type = type { " . join(', ', @obj_elems) . " }  ; object struct for $cname";

        # 3. Class-name string constant
        my $cn_name_global = '@' . $cname . '__class_name';
        my $cn_bytes = length($cname) + 1;  # +1 for NUL
        my $cn_enc   = _encode_c_string($cname);
        push @lines, "$cn_name_global = private unnamed_addr constant [$cn_bytes x i8] c\"$cn_enc\\00\", align 1";

        # 4. Method body functions (one define per method)
        for my $minfo (@$methods) {
            my $mname     = $minfo->{name};
            my $fn_name   = '@' . $cname . '__' . $mname;
            my $ret_repr  = $minfo->{return_repr} // 'Int';
            my $fn_ret    = _method_fn_llvm_ret_type($ret_repr);

            if ($minfo->{inherited_from}) {
                # Inherited method: emit a wrapper that forwards to the parent's impl
                my $parent = $minfo->{inherited_from};
                my $parent_fn = '@' . $parent . '__' . $mname;
                push @lines, "define internal $fn_ret $fn_name(i8* %self) {";
                push @lines, 'entry:';
                if ($ret_repr eq 'Str') {
                    push @lines, "  %r = call %StrPair $parent_fn(i8* %self)";
                    push @lines, '  ret %StrPair %r';
                }
                elsif ($ret_repr eq 'Num') {
                    push @lines, "  %r = call double $parent_fn(i8* %self)";
                    push @lines, '  ret double %r';
                }
                elsif ($ret_repr eq 'Bool') {
                    push @lines, "  %r = call i1 $parent_fn(i8* %self)";
                    push @lines, '  ret i1 %r';
                }
                else {
                    push @lines, "  %r = call i64 $parent_fn(i8* %self)";
                    push @lines, '  ret i64 %r';
                }
                push @lines, '}';
                push @lines, '';
                next;
            }

            if ($minfo->{is_reader_synth}) {
                # :reader synthesized method: load field at field_index and return
                my $fidx     = $minfo->{reader_field_index};
                my $slot_idx = $fidx + 1;
                push @lines, "define internal $fn_ret $fn_name(i8* %self) {  ; :reader for field $fidx";
                push @lines, 'entry:';
                push @lines, "  %obj = bitcast i8* %self to %${cname}.obj*";
                # Load defined bit
                push @lines, "  %def_gep = getelementptr inbounds %${cname}.obj, %${cname}.obj* %obj, i64 0, i32 $slot_idx, i32 0";
                push @lines, '  %def = load i1, i1* %def_gep';
                # Load payload
                push @lines, "  %pay_gep = getelementptr inbounds %${cname}.obj, %${cname}.obj* %obj, i64 0, i32 $slot_idx, i32 1";
                push @lines, '  %pay = load i64, i64* %pay_gep';
                if ($ret_repr eq 'Str') {
                    # payload = StrPair* (as i64) -> cast back and return {ptr, len}
                    push @lines, '  %pair_ptr = inttoptr i64 %pay to %StrPair*';
                    push @lines, '  %pp_gep = getelementptr inbounds %StrPair, %StrPair* %pair_ptr, i64 0, i32 0';
                    push @lines, '  %sp = load i8*, i8** %pp_gep';
                    push @lines, '  %lp_gep = getelementptr inbounds %StrPair, %StrPair* %pair_ptr, i64 0, i32 1';
                    push @lines, '  %sl = load i64, i64* %lp_gep';
                    push @lines, '  %r0 = insertvalue %StrPair undef, i8* %sp, 0';
                    push @lines, '  %r1 = insertvalue %StrPair %r0, i64 %sl, 1';
                    push @lines, '  ret %StrPair %r1';
                }
                else {
                    push @lines, '  ret i64 %pay';
                }
                push @lines, '}';
                push @lines, '';
                next;
            }

            my $body_node = $minfo->{body_node};
            unless (defined $body_node) {
                push @lines, "define internal $fn_ret $fn_name(i8* %self) { entry: ret ${fn_ret} 0 }  ; stub (no body)";
                push @lines, '';
                next;
            }

            # Lower the method body into a fresh context
            my $body_ctx = Chalk::Target::LLVM::Context->new;
            $body_ctx->{_in_method_body} = 1;
            $body_ctx->{_method_self_name} = '%self';
            $body_ctx->{_method_class_name} = $cname;
            $body_ctx->{_method_name} = $mname;  # I1: used to prefix str_const globals uniquely
            $body_ctx->{class_registry} = $registry;
            $body_ctx->{_need_strpair}  = $ctx->{_need_strpair} // 0;

            # Lower the body value node into the method body context
            my $body_val = $body_ctx->lower_value($body_node);

            push @lines, "define internal $fn_ret $fn_name(i8* %self) {  ; method body for ${cname}::${mname}";
            push @lines, 'entry:';

            # Emit all instructions from the body context
            my $body_blocks = $body_ctx->blocks;
            for my $i (0 .. $#$body_blocks) {
                my $blk = $body_blocks->[$i];
                if ($i > 0) {
                    push @lines, $blk->{label} . ':';
                }
                push @lines, $blk->{insts}->@*;
                if (defined $blk->{terminator}) {
                    push @lines, $blk->{terminator};
                }
            }

            # Emit return instruction
            if ($ret_repr eq 'Str') {
                my $len_ref = $body_ctx->{_str_len_table}{$body_val};
                if (defined $len_ref) {
                    push @lines, "  %ret_r0 = insertvalue %StrPair undef, i8* $body_val, 0";
                    push @lines, "  %ret_r1 = insertvalue %StrPair %ret_r0, i64 $len_ref, 1";
                    push @lines, '  ret %StrPair %ret_r1';
                }
                else {
                    # Compute strlen at runtime
                    push @lines, "  %ret_len = call i64 \@strlen(i8* $body_val)";
                    push @lines, "  %ret_r0 = insertvalue %StrPair undef, i8* $body_val, 0";
                    push @lines, "  %ret_r1 = insertvalue %StrPair %ret_r0, i64 %ret_len, 1";
                    push @lines, '  ret %StrPair %ret_r1';
                }
            }
            elsif ($ret_repr eq 'Num') {
                push @lines, "  ret double $body_val";
            }
            elsif ($ret_repr eq 'Bool') {
                push @lines, "  ret i1 $body_val";
            }
            else {
                push @lines, "  ret i64 $body_val";
            }
            push @lines, '}';
            push @lines, '';

            # Propagate ALL _need_* flags from the method body context up to the main ctx.
            # The prologue is assembled before method bodies are lowered; it reads these
            # flags from $ctx to decide which helpers/declarations to emit.  Any flag set
            # only on $body_ctx would be invisible to the prologue, producing .ll that
            # references undeclared globals/helpers (F6 bug).
            for my $flag (qw(
                _need_malloc_memcpy
                _need_strpair
                _need_bool_str_globals
                _need_str_to_num_helper
                _need_memcmp
                _need_aggregate_types
            )) {
                $ctx->{$flag} = 1 if $body_ctx->{$flag};
            }

            # Emit string constant globals from the method body INLINE (before the define).
            # They cannot go in the main prologue (already emitted); place them here in
            # the class section, before the function that references them.
            if (defined $body_ctx->{_str_globals} && @{ $body_ctx->{_str_globals} }) {
                for my $g (@{ $body_ctx->{_str_globals} }) {
                    my ($gname, $content, $blen) = @$g;
                    my $total = $blen + 1;
                    my $enc = Chalk::Target::LLVM::_encode_c_string($content);
                    push @lines, "$gname = private unnamed_addr constant [$total x i8] c\"$enc\\00\", align 1";
                }
            }
        }

        # 5. Vtable global: @Cls__vtable = { class-name-ptr, fn-ptr0, fn-ptr1, ... }
        my $vt_global = '@' . $cname . '__vtable';
        my @vt_init;
        push @vt_init, "i8* getelementptr inbounds ([$cn_bytes x i8], [$cn_bytes x i8]* $cn_name_global, i64 0, i64 0)";
        for my $minfo (@$methods) {
            my $mname   = $minfo->{name};
            my $fn_name = '@' . $cname . '__' . $mname;
            my $ret_repr = $minfo->{return_repr} // 'Int';
            my $fn_type_str = _method_fn_type($ret_repr);
            push @vt_init, "i8* bitcast ($fn_type_str* $fn_name to i8*)";
        }
        push @lines, "$vt_global = private unnamed_addr constant $vt_type { " . join(', ', @vt_init) . " }  ; vtable for $cname";
        push @lines, '';
    }

    return @lines;
}

# lower_with_elaboration($class, $ret_node, $elab) -> $llvm_ir_text
#
# Variant of lower() that accepts a pre-computed Elaborate pass result for
# phi placement at Region merge points. The $elab object carries emitted_phis()
# — the list of { block_id, vd_id, incoming => [...] } records that the
# elaboration pass determined should be phi nodes at merge blocks. The LLVM
# backend places phis using the dominator-tree scoped value map.
sub lower_with_elaboration {
    my ($class, $return_node, $elab) = @_;

    # Pre-scan for ClassDecl/MethodDef/FieldDef nodes and build a class registry.
    # The registry drives class-type declarations, vtable globals, and method body
    # emission — all of which must appear BEFORE @main in the LLVM module.
    my $class_registry = _scan_class_registry($return_node);

    # Build a context that knows the elaboration phi plan.
    my $ctx = Chalk::Target::LLVM::ElaboratedContext->new(elab => $elab,
        class_registry => $class_registry);

    # Classes require %Slot (for fields) and malloc (for New).
    # Set these flags early so the prologue emits them even before body lowering.
    if (defined $class_registry && %$class_registry) {
        $ctx->{_need_aggregate_types} = 1;
        $ctx->{_need_malloc_memcpy}   = 1;
    }

    # Process the control chain — VarDecl/Assign/If/Loop.
    # ElaboratedContext._process_if_node uses the elab phis for phi placement.
    #
    # When Return.control_in is a Region (not an If/Loop directly), we walk via
    # the Region's head back-pointer to find the If/Loop that owns it, then
    # continue from head.control_in. This matches the Elaborate pass's M2 path.
    {
        my @chain;
        my $ctrl = $return_node->control_in;
        while (defined $ctrl) {
            my $op = $ctrl->can('operation') ? $ctrl->operation : '';
            if ($op eq 'Region') {
                # Region-as-control_in: push the owning If/Loop (the head) so
                # process_control_node handles it correctly, then continue from
                # the head's control_in predecessor.
                my $head = $ctrl->can('head') ? $ctrl->head : undef;
                if (defined $head) {
                    push @chain, $head;
                    $ctrl = $head->can('control_in') ? $head->control_in : undef;
                }
                else {
                    push @chain, $ctrl;
                    last;
                }
            }
            else {
                push @chain, $ctrl;
                $ctrl = $ctrl->can('control_in') ? $ctrl->control_in : undef;
            }
        }
        for my $node (reverse @chain) {
            $ctx->process_control_node($node);
        }
    }

    my $value_node  = $return_node->inputs->[0];
    my $result_ref  = $ctx->lower_value($value_node);
    my $result_repr = $value_node->representation;

    my @lines;
    push @lines, '; Generated by Chalk::Target::LLVM (elaboration pass) - dominator-tree placement';
    push @lines, '';

    # Type-tagged output: both sides (perl oracle and lli) emit a canonical tag
    # so Bool is distinguishable from its Str coercion. Tags: Int:<n> Num:<g> Bool:1/Bool:
    # Format strings and string constants are per-representation, libperl-free.
    if (!defined $result_repr || $result_repr eq 'Int') {
        # "Int:%d\n" = 7 bytes: 'I','n','t',':','%','d','\n','\0' = [8 x i8]
        push @lines, '@fmt = private unnamed_addr constant [8 x i8] c"Int:%d\0A\00", align 1';
    }
    elsif ($result_repr eq 'Num') {
        # Finite path: "Num:%g\n\0" = 8 bytes = [8 x i8]
        push @lines, '@fmt = private unnamed_addr constant [8 x i8] c"Num:%g\0A\00", align 1';
        # Non-finite path: perl-style capitalized faces for Inf/-Inf/NaN.
        # The LLVM epilogue detects non-finite via fcmp and uses these constants.
        # "Num:Inf\n\0"  = 9 bytes = [9 x i8]
        # "Num:-Inf\n\0" = 10 bytes = [10 x i8]
        # "Num:NaN\n\0"  = 9 bytes = [9 x i8]
        # "%s\0"         = 3 bytes = [3 x i8]
        push @lines, '@num_inf_str  = private unnamed_addr constant [9 x i8]  c"Num:Inf\0A\00",  align 1';
        push @lines, '@num_ninf_str = private unnamed_addr constant [10 x i8] c"Num:-Inf\0A\00", align 1';
        push @lines, '@num_nan_str  = private unnamed_addr constant [9 x i8]  c"Num:NaN\0A\00",  align 1';
        push @lines, '@fmt_num_s    = private unnamed_addr constant [3 x i8]  c"%s\00",           align 1';
    }
    elsif ($result_repr eq 'Bool') {
        # Bool prints either "Bool:1\n" (true) or "Bool:\n" (false).
        # We use two string constants and a select instruction.
        # "Bool:1\n\0" = 8 bytes = [8 x i8]
        # "Bool:\n\0"  = 7 bytes = [7 x i8]
        push @lines, '@bool_true_str  = private unnamed_addr constant [8 x i8] c"Bool:1\0A\00", align 1';
        push @lines, '@bool_false_str = private unnamed_addr constant [7 x i8] c"Bool:\0A\00",  align 1';
        # printf format for %s: "Bool:" is already baked into the string constants;
        # use printf("%s", selected_ptr) to emit the full tagged line.
        push @lines, '@fmt_s = private unnamed_addr constant [3 x i8] c"%s\00", align 1';
    }
    elsif ($result_repr eq 'Str') {
        # Str result: two possible print paths depending on whether we have a
        # compile-time-tracked length or only a NUL-terminated pointer.
        #
        # Path A (length-tracked, from Constant/Concat/VarDecl Str values):
        #   printf("Str:%.*s\n", (i32)len, ptr)
        #   Format: "Str:%.*s\n\0" = S,t,r,:,%,.,*,s,\n,\0 = 10 bytes = [10 x i8]
        #   This is correct for any byte content (including embedded NULs in theory).
        #
        # Path B (NUL-terminated only, from Coerce(Bool->Str) or unknown-length):
        #   printf("Str:%s\n", ptr)
        #   Format: "Str:%s\n\0" = 8 bytes = [8 x i8]
        #   Both Bool-face strings are NUL-terminated globals — correct for ASCII.
        #
        # We emit both format globals; the epilogue selects at lower_with_elaboration
        # time based on whether the context has a tracked length for the result.
        #
        # Bool string-face globals for Coerce(Bool->Str):
        # "1\0" = [2 x i8]; "\0" = [1 x i8] (NUL only = empty string)
        push @lines, '@coerce_bool_str_true  = private unnamed_addr constant [2 x i8] c"1\00", align 1';
        push @lines, '@coerce_bool_str_false = private unnamed_addr constant [1 x i8] c"\00",   align 1';
        # Path B format (NUL-terminated fallback):
        push @lines, '@fmt_str = private unnamed_addr constant [8 x i8] c"Str:%s\0A\00", align 1';
        # Path A format (length-precision):
        push @lines, '@fmt_str_len = private unnamed_addr constant [10 x i8] c"Str:%.*s\0A\00", align 1';
    }
    elsif ($result_repr eq 'Undef') {
        # Undef result: print "Undef:\n" (8 bytes including NUL terminator).
        # "Undef:\n\0" = U,n,d,e,f,:,\n,\0 = 8 bytes = [8 x i8]
        # A fixed string constant — no format arguments needed; use printf("%s", ptr).
        push @lines, '@undef_str  = private unnamed_addr constant [8 x i8] c"Undef:\0A\00", align 1';
        push @lines, '@fmt_s_u    = private unnamed_addr constant [3 x i8] c"%s\00", align 1';
    }
    elsif ($result_repr eq 'Slot') {
        # Slot result: a tagged-scalar {i1 defined, i64 payload} from array/hash reads.
        # If defined=true: print "Int:<payload>\n". If defined=false: print "Undef:\n".
        # "Int:%d\n\0" = 8 bytes; "Undef:\n\0" = 8 bytes.
        push @lines, '@fmt_slot_int   = private unnamed_addr constant [8 x i8] c"Int:%d\0A\00",  align 1';
        push @lines, '@fmt_slot_undef = private unnamed_addr constant [8 x i8] c"Undef:\0A\00",  align 1';
        push @lines, '@fmt_slot_s     = private unnamed_addr constant [3 x i8] c"%s\00",          align 1';
    }
    else {
        die "LLVM backend (elaboration): cannot emit return of repr=$result_repr";
    }

    # When body lowering set _need_bool_str_globals (Coerce(Bool->Str) used
    # internally in a non-Str-return graph), emit those globals now. They are
    # always emitted for a Str result repr (above); this branch handles the
    # case where the return is not Str but the body contains a Coerce(Bool->Str)
    # in the MAIN graph (not a method body — method bodies are handled post-class).
    if ($ctx->{_need_bool_str_globals} && $result_repr ne 'Str') {
        push @lines, '@coerce_bool_str_true  = private unnamed_addr constant [2 x i8] c"1\00", align 1';
        push @lines, '@coerce_bool_str_false = private unnamed_addr constant [1 x i8] c"\00",   align 1';
        $ctx->{_bool_str_globals_emitted} = 1;
    }

    push @lines, '';
    push @lines, 'declare i32 @printf(i8* nocapture readonly, ...)';

    # Emit string-constant globals collected during body lowering.
    # Each Constant(:Str) node emits a private global; the names are stashed in
    # _str_globals as [ $global_name, $content, $byte_len ] triples. We emit
    # them here (before the function body) so they appear in the module before @main.
    if (defined $ctx->{_str_globals}) {
        push @lines, '';
        for my $g ($ctx->{_str_globals}->@*) {
            my ($gname, $content, $blen) = @$g;
            my $total = $blen + 1;  # +1 for NUL terminator
            # Encode the bytes as a c"..." literal (NUL is \00).
            my $enc = _encode_c_string($content);
            push @lines, "$gname = private unnamed_addr constant [$total x i8] c\"$enc\\00\", align 1";
        }
    }

    # Declare malloc/memcpy when Str concat or aggregate operations were emitted.
    # These are plain C host-interface functions — NOT libperl.
    if ($ctx->{_need_malloc_memcpy}) {
        push @lines, 'declare i8* @malloc(i64)';
        push @lines, 'declare i8* @memcpy(i8*, i8*, i64)';
    }

    # Declare memcmp when hash key comparison operations were emitted.
    if ($ctx->{_need_memcmp}) {
        push @lines, 'declare i32 @memcmp(i8* nocapture readonly, i8* nocapture readonly, i64)';
        $ctx->{_memcmp_emitted} = 1;
    }

    # Emit LLVM type declarations for Array/Hash aggregate structures when needed.
    # %Slot = { i1 defined, i64 payload } (16 bytes with padding)
    # %Array = { i64 len, i64 cap, %Slot* elems }
    # %HashEntry = { i8* key_ptr, i64 key_len, i32 key_enc, i1 val_def, i64 val_pay }
    # %Hash = { i64 count, i64 cap, %HashEntry* entries }
    if ($ctx->{_need_aggregate_types}) {
        push @lines, '%Slot       = type { i1, i64 }';
        push @lines, '%Array      = type { i64, i64, %Slot* }';
        push @lines, '%HashEntry  = type { i8*, i64, i32, i1, i64 }';
        push @lines, '%Hash       = type { i64, i64, %HashEntry* }';
    }

    # Emit @chalk_str_to_num helper + strtod declaration when Coerce(Str->Num) is used.
    #
    # The helper implements perl's leading-numeric rule: skip whitespace, then parse
    # a decimal number (no hex). The one divergence from libc strtod: strtod parses
    # "0x10" as 16.0, but perl returns 0. We pre-check for "0x"/"0X" and return 0.0.
    #
    # strtod is a plain C library function (host interface, NOT libperl). The
    # chalk_str_to_num function is a module-local helper; no external linkage needed.
    if ($ctx->{_need_str_to_num_helper}) {
        push @lines, '';
        push @lines, 'declare double @strtod(i8* nocapture readonly, i8** nocapture)';
        push @lines, '';
        # @chalk_str_to_num(i8* %ptr, i64 %len) -> double
        # Implements perl's leading-numeric rule (decimal only; "0x..." -> 0.0).
        push @lines, _emit_str_to_num_helper();
        $ctx->{_str_to_num_helper_emitted} = 1;
    }

    # Emit class-related IR: type declarations, vtable globals, class-name constants,
    # strlen declaration (for Str field reads), and method body functions.
    # Classes always require %Slot (aggregate types) and malloc.
    #
    # IMPORTANT: method body lowering (inside _emit_class_registry_ir) may set
    # additional _need_* flags on $ctx via the propagation in that function.
    # Those flags are checked AGAIN below (post-class emission) to emit any
    # helpers/declarations that method bodies needed but the prologue did not emit
    # (because the prologue runs before method bodies are lowered — F6 fix).
    if (defined $class_registry && %$class_registry) {
        push @lines, '';
        push @lines, 'declare i64 @strlen(i8* nocapture readonly)';
        my @class_lines = _emit_class_registry_ir($class_registry, $ctx);
        push @lines, @class_lines;
    }

    # Post-class emission: emit any helpers/declarations that method bodies
    # flagged via _need_* propagation but that the pre-class prologue did not emit.
    # Each check is guarded by "was it already emitted?" (only applicable for
    # _need_bool_str_globals when result_repr ne Str, and _need_str_to_num_helper).
    if ($ctx->{_need_bool_str_globals} && $result_repr ne 'Str') {
        # Only emit if the Str-prologue path (which always includes these globals)
        # did NOT already emit them. The Str-prologue emits them unconditionally
        # when result_repr eq 'Str'; for all other reprs, we must emit here if needed.
        # To avoid duplicate definitions, we track whether they were already emitted.
        # The prologue emits them only when result_repr eq 'Str' (lines ~668-669) or
        # when _need_bool_str_globals was already set on $ctx before class-lowering.
        # Since we only reach here when result_repr ne 'Str', the prologue cannot have
        # emitted them (it checks `$result_repr ne 'Str'` too), so we need to emit now
        # IF the flag was newly set by method-body propagation (not by the main graph).
        # Guard: if the prologue already emitted them (result_repr ne Str path at line 710),
        # they'll be duplicated. We use $ctx->{_bool_str_globals_emitted} to track this.
        unless ($ctx->{_bool_str_globals_emitted}) {
            push @lines, '';
            push @lines, '@coerce_bool_str_true  = private unnamed_addr constant [2 x i8] c"1\00", align 1';
            push @lines, '@coerce_bool_str_false = private unnamed_addr constant [1 x i8] c"\00",   align 1';
            $ctx->{_bool_str_globals_emitted} = 1;
        }
    }
    if ($ctx->{_need_str_to_num_helper} && !$ctx->{_str_to_num_helper_emitted}) {
        push @lines, '';
        push @lines, 'declare double @strtod(i8* nocapture readonly, i8** nocapture)';
        push @lines, '';
        push @lines, _emit_str_to_num_helper();
        $ctx->{_str_to_num_helper_emitted} = 1;
    }
    # Post-class re-emit for _need_memcmp: a method body doing Subscript(Hash)
    # sets _need_memcmp on $body_ctx (propagated to $ctx by G.5), but the prologue
    # memcmp declare runs BEFORE method bodies lower. If the flag was set only by a
    # method body, the prologue missed it. Emit here, guarded by _memcmp_emitted so
    # a non-method hash op + a method hash op cannot double-declare.
    if ($ctx->{_need_memcmp} && !$ctx->{_memcmp_emitted}) {
        push @lines, 'declare i32 @memcmp(i8* nocapture readonly, i8* nocapture readonly, i64)';
        $ctx->{_memcmp_emitted} = 1;
    }

    # Post-class re-emit for _need_strpair (I3):
    # %StrPair is declared by _emit_class_registry_ir only when some method RETURNS Str
    # (the LOCAL $need_strpair scan at line ~366 checks return_repr). But _need_strpair
    # is also set during lower_value (e.g. _lower_new at ~3545 when binding a Str :param
    # field), which runs BEFORE _emit_class_registry_ir. If the class has no Str-returning
    # method (LOCAL scan returns 0) but a Str :param is bound, _lower_new emits %StrPair*
    # references without %StrPair being declared — lli rejects. The _strpair_emitted flag
    # (set at the existing line-376 emit site) prevents double-declare.
    if ($ctx->{_need_strpair} && !$ctx->{_strpair_emitted}) {
        push @lines, '; StrPair: {i8* ptr, i64 len} for Str values (post-class re-emit, I3)';
        push @lines, '%StrPair = type { i8*, i64 }';
        $ctx->{_strpair_emitted} = 1;
    }

    push @lines, '';
    push @lines, 'define i32 @main() {';

    my $blocks = $ctx->blocks;
    for my $i (0 .. $#$blocks) {
        my $block = $blocks->[$i];
        push @lines, $block->{label} . ':';
        push @lines, $block->{insts}->@*;
        if (defined $block->{terminator}) {
            push @lines, $block->{terminator};
        }
    }

    if (!defined $result_repr || $result_repr eq 'Int') {
        push @lines, "  %result_i32 = trunc i64 $result_ref to i32";
        push @lines, '  %fmt_ptr = getelementptr inbounds [8 x i8], [8 x i8]* @fmt, i64 0, i64 0';
        push @lines, '  call i32 (i8*, ...) @printf(i8* %fmt_ptr, i32 %result_i32)';
    }
    elsif ($result_repr eq 'Num') {
        # Non-finite detection: fcmp uno for NaN; fcmp oeq against +Inf/-Inf constants.
        # Perl formats non-finite as Inf/-Inf/NaN (capitalized); C %g gives lowercase.
        # We branch on non-finite and print the perl-style string constants instead.
        push @lines, "  %is_nan   = fcmp uno double $result_ref, $result_ref      ; NaN iff unordered with itself";
        push @lines, "  %is_pinf  = fcmp oeq double $result_ref, 0x7FF0000000000000  ; +Inf";
        push @lines, "  %is_ninf  = fcmp oeq double $result_ref, 0xFFF0000000000000  ; -Inf";
        push @lines, '  %is_nf_in = or i1 %is_pinf, %is_ninf';
        push @lines, '  %is_nf    = or i1 %is_nan,  %is_nf_in';
        push @lines, '  br i1 %is_nf, label %print_nf, label %print_fin';
        push @lines, '';
        push @lines, 'print_nf:';
        push @lines, '  %nf_pinf_ptr = getelementptr inbounds [9 x i8],  [9 x i8]*  @num_inf_str,  i64 0, i64 0';
        push @lines, '  %nf_ninf_ptr = getelementptr inbounds [10 x i8], [10 x i8]* @num_ninf_str, i64 0, i64 0';
        push @lines, '  %nf_nan_ptr  = getelementptr inbounds [9 x i8],  [9 x i8]*  @num_nan_str,  i64 0, i64 0';
        push @lines, '  %nf_inf_sel  = select i1 %is_pinf, i8* %nf_pinf_ptr, i8* %nf_ninf_ptr   ; +Inf or -Inf';
        push @lines, '  %nf_str      = select i1 %is_nan,  i8* %nf_nan_ptr,  i8* %nf_inf_sel    ; NaN overrides';
        push @lines, '  %fmt_num_s_ptr = getelementptr inbounds [3 x i8], [3 x i8]* @fmt_num_s, i64 0, i64 0';
        push @lines, '  call i32 (i8*, ...) @printf(i8* %fmt_num_s_ptr, i8* %nf_str)';
        push @lines, '  br label %print_done';
        push @lines, '';
        push @lines, 'print_fin:';
        push @lines, '  %fmt_ptr = getelementptr inbounds [8 x i8], [8 x i8]* @fmt, i64 0, i64 0';
        push @lines, "  call i32 (i8*, ...) \@printf(i8* %fmt_ptr, double $result_ref)";
        push @lines, '  br label %print_done';
        push @lines, '';
        push @lines, 'print_done:';
    }
    elsif ($result_repr eq 'Bool') {
        # Select between "Bool:1\n" and "Bool:\n" based on the i1 result.
        push @lines, "  %bool_true_ptr  = getelementptr inbounds [8 x i8], [8 x i8]* \@bool_true_str,  i64 0, i64 0";
        push @lines, "  %bool_false_ptr = getelementptr inbounds [7 x i8], [7 x i8]* \@bool_false_str, i64 0, i64 0";
        push @lines, "  %bool_str_ptr   = select i1 $result_ref, i8* %bool_true_ptr, i8* %bool_false_ptr";
        push @lines, '  %fmt_s_ptr      = getelementptr inbounds [3 x i8], [3 x i8]* @fmt_s, i64 0, i64 0';
        push @lines, '  call i32 (i8*, ...) @printf(i8* %fmt_s_ptr, i8* %bool_str_ptr)';
    }
    elsif ($result_repr eq 'Str') {
        # Print as "Str:<value>\n" using the type-tag format.
        # Path A: length-tracked (from Constant/Concat/VarDecl Str nodes).
        #   Use printf("Str:%.*s\n", (i32)len, ptr) — correct for exactly len bytes.
        # Path B: NUL-terminated only (from Coerce(Bool->Str) or unknown-length).
        #   Use printf("Str:%s\n", ptr) — correct for NUL-terminated ASCII.
        my $len_ref = $ctx->_str_len_for($result_ref);
        if (defined $len_ref) {
            # Path A: length-tracked
            my $len32 = '%result_str_len32';
            push @lines, "  $len32 = trunc i64 $len_ref to i32  ; Str output: len i64->i32 for printf precision";
            push @lines, '  %fmt_str_len_ptr = getelementptr inbounds [10 x i8], [10 x i8]* @fmt_str_len, i64 0, i64 0';
            push @lines, "  call i32 (i8*, ...) \@printf(i8* %fmt_str_len_ptr, i32 $len32, i8* $result_ref)";
        }
        else {
            # Path B: NUL-terminated fallback (Coerce(Bool->Str) etc.)
            push @lines, '  %fmt_str_ptr = getelementptr inbounds [8 x i8], [8 x i8]* @fmt_str, i64 0, i64 0';
            push @lines, "  call i32 (i8*, ...) \@printf(i8* %fmt_str_ptr, i8* $result_ref)";
        }
    }
    elsif ($result_repr eq 'Undef') {
        # Undef result: always prints "Undef:\n". The result_ref is the i1 defined-bit
        # (always false for Constant(undef)), which is not used for printing — the
        # output is the fixed "Undef:\n" string constant regardless of the bit value.
        push @lines, '  %undef_str_ptr = getelementptr inbounds [8 x i8], [8 x i8]* @undef_str, i64 0, i64 0';
        push @lines, '  %fmt_s_u_ptr   = getelementptr inbounds [3 x i8], [3 x i8]* @fmt_s_u, i64 0, i64 0';
        push @lines, '  call i32 (i8*, ...) @printf(i8* %fmt_s_u_ptr, i8* %undef_str_ptr)';
    }
    elsif ($result_repr eq 'Slot') {
        # Slot result: tagged-scalar from array/hash read.
        # result_ref is the i1 defined-bit SSA ref.
        # The payload (i64) is retrieved from _slot_payload{result_ref}.
        #
        # Branch on defined-bit:
        #   defined=true  -> print "Int:<payload>\n"
        #   defined=false -> print "Undef:\n"
        my $def_bit  = $result_ref;
        my $pay_val  = $ctx->{_slot_payload}{$def_bit}
            // die "LLVM backend: Slot result missing payload in _slot_payload table";
        my $def_lbl  = $ctx->_fresh_label('slot_def');
        my $und_lbl  = $ctx->_fresh_label('slot_und');
        my $end_lbl  = $ctx->_fresh_label('slot_end');

        push @lines, "  br i1 $def_bit, label \%$def_lbl, label \%$und_lbl";
        push @lines, '';
        push @lines, "$def_lbl:";
        my $pay32 = $ctx->_fresh;
        push @lines, "  $pay32 = trunc i64 $pay_val to i32  ; Slot defined: truncate payload for printf %d";
        push @lines, '  %slot_fmt_int_ptr = getelementptr inbounds [8 x i8], [8 x i8]* @fmt_slot_int, i64 0, i64 0';
        push @lines, "  call i32 (i8*, ...) \@printf(i8* %slot_fmt_int_ptr, i32 $pay32)";
        push @lines, "  br label \%$end_lbl";
        push @lines, '';
        push @lines, "$und_lbl:";
        push @lines, '  %slot_fmt_undef_ptr = getelementptr inbounds [8 x i8], [8 x i8]* @fmt_slot_undef, i64 0, i64 0';
        push @lines, '  call i32 (i8*, ...) @printf(i8* %slot_fmt_undef_ptr)';
        push @lines, "  br label \%$end_lbl";
        push @lines, '';
        push @lines, "$end_lbl:";
    }

    push @lines, '  ret i32 0';
    push @lines, '}';

    return join("\n", @lines) . "\n";
}

# ---------------------------------------------------------------------------
# Internal lowering context
# ---------------------------------------------------------------------------
package Chalk::Target::LLVM::Context;
use 5.42.0;
use utf8;

# Re-export helpers from the main package so unqualified calls in this
# package resolve correctly (both packages share the same implementation).
*_require_repr              = \&Chalk::Target::LLVM::_require_repr;
*_class_name_from_class_node = \&Chalk::Target::LLVM::_class_name_from_class_node;

# _method_fn_type($result_repr) -> LLVM fn type string for method signatures.
# Duplicate of the module-level sub; both packages need it to avoid cross-package calls.
sub _method_fn_type {
    my ($result_repr) = @_;
    return 'i64 (i8*)' if !defined $result_repr || $result_repr eq 'Int';
    return '%StrPair (i8*)' if $result_repr eq 'Str';
    return 'i1 (i8*)'   if $result_repr eq 'Bool';
    return 'double (i8*)' if $result_repr eq 'Num';
    die "LLVM MOP: unsupported method return repr '$result_repr'";
}

sub new {
    my ($class) = @_;
    # Each block is: { label => 'name', insts => [...], terminator => str|undef }
    # The entry block is always first and is never terminated by this emitter
    # during straight-line code — the lower() epilogue adds the final ret.
    my $entry_block = { label => 'entry', insts => [], terminator => undef };
    return bless {
        blocks         => [$entry_block],   # ordered list of basic blocks
        current_idx    => 0,                # index into blocks of current block
        counter        => 0,
        block_counter  => 0,
        cache     => {},     # node id -> llvm_ref (%tmp_N)
        var_table => {},     # VarDecl node id -> current SSA value ref
                             # Used for SSA-value threading of lexical scalars:
                             # VarDecl stores its init SSA ref here; Assign updates
                             # it; PadAccess reads it. Models straight-line SSA
                             # without needing alloca/store/load for simple cases.
        # Str representation tracking (G3):
        #   _str_globals    => [ [$global_name, $content, $byte_len], ... ]
        #     String constant globals to emit in the module prologue.
        #   _str_len_table  => { $ssa_ptr_ref => $len_ssa_ref_or_literal }
        #     Maps each Str SSA ptr ref to its length (i64). Used by the output
        #     epilogue to emit printf("Str:%.*s\n", len, ptr) for exactly len bytes.
        #   _need_malloc_memcpy => bool
        #     Set when a Concat node is lowered; triggers malloc/memcpy declarations.
        _str_globals          => [],
        _str_len_table        => {},
        _need_malloc_memcpy   => 0,
        _need_str_to_num_helper => 0,
        # G4 Array/Hash aggregate tracking:
        #   _need_aggregate_types => bool
        #     Set when any Array/Hash node is lowered; triggers type struct declarations.
        #   _need_memcmp => bool
        #     Set when Subscript(Hash) is lowered; triggers memcmp declaration.
        #   _arr_table => { node_id => '%arr_ptr_ref' }
        #     Maps ArrayRef/Assign(Array-lvalue) node id -> LLVM %Array* pointer ref.
        #   _hash_table => { node_id => '%hash_ptr_ref' }
        #     Maps HashRef/Assign(Hash-lvalue) node id -> LLVM %Hash* pointer ref.
        _need_aggregate_types => 0,
        _need_memcmp          => 0,
        _arr_table            => {},
        _hash_table           => {},
        # Slot repr tracking: parallel to _undef_defined_bit/_undef_payload for Undef.
        # Maps the SSA def-bit ref -> SSA payload ref (i64).
        # Used by the Slot return epilogue to retrieve both fields.
        _slot_payload => {},
        # G5 MOP: class registry (class_name -> { methods, fields, ... }).
        # Set by ElaboratedContext::new via the pre-scan in lower_with_elaboration.
        # Also set on method-body sub-contexts via direct hash assignment.
        class_registry => {},
        # G5 MOP: StrPair type needed (Str-returning methods)
        _need_strpair => 0,
        # G5 MOP: method body context flags
        _in_method_body      => 0,
        _method_self_name    => undef,
        _method_class_name   => undef,
    }, $class;
}

# _str_len_for($ptr_ref) -> $len_ref_or_undef
# Returns the tracked length SSA ref/literal for a Str SSA ptr reference,
# or undef if the length is not tracked (e.g. for Coerce(Bool->Str) values).
sub _str_len_for {
    my ($self, $ptr_ref) = @_;
    return $self->{_str_len_table}{$ptr_ref};
}

# blocks() -> arrayref of { label, insts, terminator }
sub blocks { $_[0]->{blocks} }

# instructions() -> the insts arrayref of the current block.
# Maintained for backward compatibility with callers that read this directly.
sub instructions { $_[0]->{blocks}[ $_[0]->{current_idx} ]{insts} }

# _emit($inst) -> push $inst into the current block's instruction list.
sub _emit {
    my ($self, $inst) = @_;
    push $self->{blocks}[ $self->{current_idx} ]{insts}->@*, $inst;
}

# _set_terminator($term) -> set the current block's terminator instruction.
# A block must have exactly one terminator. Call this before _new_block().
sub _set_terminator {
    my ($self, $term) = @_;
    $self->{blocks}[ $self->{current_idx} ]{terminator} = $term;
}

# _new_block($label) -> $label
# Start a new basic block with the given label. All subsequent _emit() calls
# go into this block. Returns the label string for use in phi/branch args.
sub _new_block {
    my ($self, $label) = @_;
    my $block = { label => $label, insts => [], terminator => undef };
    push $self->{blocks}->@*, $block;
    $self->{current_idx} = $#{ $self->{blocks} };
    return $label;
}

# _current_block_label() -> the label of the current block.
sub _current_block_label {
    my ($self) = @_;
    return $self->{blocks}[ $self->{current_idx} ]{label};
}

# _fresh_label($hint) -> unique block label string
sub _fresh_label {
    my ($self, $hint) = @_;
    $self->{block_counter}++;
    return $hint . $self->{block_counter};
}

sub _fresh {
    my ($self) = @_;
    $self->{counter}++;
    return '%tmp_' . $self->{counter};
}

# lower_value($node) -> $llvm_ref (a string like "%tmp_1" or "1" for constants)
# Recursively lowers the data sub-graph rooted at $node, accumulating
# LLVM IR instructions into the current basic block. Returns the LLVM value
# reference (SSA name or immediate) for the node's result.
sub lower_value {
    my ($self, $node) = @_;

    # Cache: if we already lowered this node (hash-cons sharing), reuse the
    # previously computed SSA ref — except for PadAccess nodes.
    #
    # PadAccess nodes are EXCLUDED from the cache-hit path: they must read the
    # current var_table entry at the moment they are lowered. var_table is
    # updated by Assign (and by phi emission at merge points), so a PadAccess
    # for a reassigned variable must see the post-assign value, not a cached
    # pre-assign SSA ref. Bypassing the cache here ensures every PadAccess
    # re-invokes _lower_padaccess, which reads var_table[vd_id] and is always
    # program-point-correct. See t/bootstrap/ir/llvm-reassign-soundness.t for
    # the adversarial proof that this model is sound across straight-line,
    # branch, and loop shapes.
    my $id = $node->id();
    my $op = $node->operation();
    if ($op ne 'PadAccess' && exists $self->{cache}{$id}) {
        return $self->{cache}{$id};
    }

    if ($op eq 'Constant') {
        return $self->_lower_constant($node);
    }
    elsif ($op eq 'Add') {
        return $self->_lower_binop_int($node, 'add');
    }
    elsif ($op eq 'Subtract') {
        return $self->_lower_binop_int($node, 'sub');
    }
    elsif ($op eq 'Multiply') {
        return $self->_lower_binop_int($node, 'mul');
    }
    elsif ($op eq 'Divide') {
        return $self->_lower_divide($node);
    }
    elsif ($op eq 'Modulo') {
        return $self->_lower_modulo($node);
    }
    elsif ($op eq 'Coerce') {
        return $self->_lower_coerce($node);
    }
    elsif ($op eq 'VarDecl') {
        return $self->_lower_vardecl($node);
    }
    elsif ($op eq 'PadAccess') {
        return $self->_lower_padaccess($node);
    }
    elsif ($op eq 'Assign' || $op eq 'CompoundAssign') {
        return $self->_lower_assign($node);
    }
    elsif ($op eq 'TernaryExpr') {
        return $self->_lower_ternary($node);
    }
    elsif ($op eq 'NumGt' || $op eq 'NumLt' || $op eq 'NumGe' || $op eq 'NumLe'
        || $op eq 'NumEq' || $op eq 'NumNe') {
        return $self->_lower_icmp_int($node);
    }
    elsif ($op eq 'Not') {
        return $self->_lower_not($node);
    }
    elsif ($op eq 'And') {
        return $self->_lower_and($node);
    }
    elsif ($op eq 'Or') {
        return $self->_lower_or($node);
    }
    elsif ($op eq 'DefinedOr') {
        return $self->_lower_defined_or($node);
    }
    elsif ($op eq 'Defined') {
        return $self->_lower_defined($node);
    }
    elsif ($op eq 'Concat') {
        return $self->_lower_concat($node);
    }
    elsif ($op eq 'Phi') {
        return $self->_lower_phi($node);
    }
    elsif ($op eq 'If') {
        return $self->_lower_if($node);
    }
    elsif ($op eq 'Region') {
        return $self->_lower_region($node);
    }
    elsif ($op eq 'Proj') {
        return $self->_lower_proj($node);
    }
    elsif ($op eq 'Loop') {
        return $self->_lower_loop($node);
    }
    elsif ($op eq 'ArrayRef') {
        return $self->_lower_array_ref($node);
    }
    elsif ($op eq 'HashRef') {
        return $self->_lower_hash_ref($node);
    }
    elsif ($op eq 'Length') {
        return $self->_lower_length($node);
    }
    elsif ($op eq 'Subscript') {
        return $self->_lower_subscript($node);
    }
    elsif ($op eq 'PostfixDeref') {
        return $self->_lower_postfix_deref($node);
    }
    # FieldAccess in a method body context: load from $self's struct
    elsif ($op eq 'FieldAccess' && $self->{_in_method_body}) {
        return $self->_lower_field_access_in_method($node);
    }
    elsif ($op eq 'Ref' && defined $node->inputs->[0]
        && defined $node->inputs->[0]->representation
        && $node->inputs->[0]->representation eq 'Object') {
        return $self->_lower_ref_of_object($node);
    }
    # Call(dispatch_kind='method'): vtable-slot dispatch, canonical form of MethodCall.
    # inputs[0] = invocant (obj node), inputs[1] = ClassInfo (class reference).
    # name = method name. return repr from node->representation.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'method') {
        return $self->_lower_call_method($node);
    }
    else {
        if (defined $node->representation && $node->representation eq 'Scalar') {
            die "GAP: node op=$op repr=Scalar reached LLVM backend — cannot lower runtime-free. "
              . "This value requires libperl; it is a GAP on the L corner.";
        }
        die "LLVM backend: cannot lower op=$op (not in literal-arithmetic slice)";
    }
}

sub _lower_constant {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    my $val  = $node->value;

    if (!defined $repr) {
        # Undef representation: the TypeInference pass did not annotate this node.
        # Die loudly instead of silently defaulting to Int — this masks upstream
        # TypeInference bugs as plausible integer output (F7 fix / G.6).
        # Consistent with _ensure_i1 which already dies on undef-repr inputs.
        die "GAP: Constant node has no representation at lowering time "
          . "(value=${\(defined $val ? $val : 'undef')}). "
          . "Fix TypeInference to annotate this node, or set the representation explicitly.";
    }
    if ($repr eq 'Scalar') {
        die "GAP: Constant node with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    if ($repr eq 'Int') {
        # Int constant -> i64 immediate via add i64 0, VALUE
        my $ref = $self->_fresh;
        $self->_emit("  $ref = add i64 0, $val          ; Constant($val, repr=Int -> i64)");
        $self->{cache}{$node->id} = $ref;
        return $ref;
    }
    elsif ($repr eq 'Num') {
        # Num constant -> double immediate
        my $ref = $self->_fresh;
        $self->_emit("  $ref = fadd double 0.0, $val    ; Constant($val, repr=Num -> double)");
        $self->{cache}{$node->id} = $ref;
        return $ref;
    }
    elsif ($repr eq 'Str') {
        # Str constant -> private global + GEP to get i8* ptr.
        # The Str representation is {ptr, len, encoding}; here encoding=0 (ASCII/default).
        # We track the ptr as the SSA value and record the byte-length in _str_len_table.
        # The private global is emitted in the module prologue.
        #
        # For a Constant node whose value is the string content (e.g., "hello"),
        # the byte length = length($val) (UTF-8 byte count; all corpus cases are ASCII).
        # The name-constant Constant("s") :Str for VarDecl names is also Str repr but
        # should not be printed — it is used only as a VarDecl name marker. We lower
        # it to the same ptr-to-global pattern; the len is tracked but unused for names.
        my $byte_len = do { use bytes; length($val) };
        my $total    = $byte_len + 1;  # +1 for NUL terminator

        # Allocate a unique global name for this string constant.
        # I1: when lowering inside a method body, prefix by class/method so that
        # two method bodies (each starting a fresh counter at 0) do not both emit
        # @str_const_0 — which would be a duplicate symbol in the module.
        # Method bodies set _in_method_body=1 and carry _method_class_name/_method_name.
        my $gidx    = scalar @{ $self->{_str_globals} };
        my $gname;
        if ($self->{_in_method_body}
            && defined $self->{_method_class_name}
            && defined $self->{_method_name}) {
            my $cls_slug  = $self->{_method_class_name};
            my $meth_slug = $self->{_method_name};
            $gname = "\@${cls_slug}__${meth_slug}__str_const_${gidx}";
        } else {
            $gname = "\@str_const_$gidx";
        }
        push $self->{_str_globals}->@*, [$gname, $val, $byte_len];

        # GEP to get i8* from the global array.
        my $ref = $self->_fresh;
        $self->_emit("  $ref = getelementptr inbounds [$total x i8], [$total x i8]* $gname, i64 0, i64 0  ; Constant(\"$val\", Str) -> i8* ptr");

        # Record the byte-length as a compile-time literal for the output epilogue.
        $self->{_str_len_table}{$ref} = $byte_len;

        $self->{cache}{$node->id} = $ref;
        return $ref;
    }
    elsif ($repr eq 'Undef') {
        # Undef constant -> an i1 defined-bit of false (0).
        #
        # The Undef representation carries a single i1 "defined" bit. For a
        # Constant(undef), that bit is always false (= not defined). We emit
        # it via alloca+store+load so the value is RUNTIME-opaque: an LLVM
        # optimizer cannot constant-fold or dead-code-eliminate the branch in
        # DefinedOr even with -O3, because the alloca/store/load sequence is
        # a memory-barrier that defeats scalar replacement without mem2reg.
        #
        # The "payload" (what the variable holds when it is defined) is not
        # needed for a Constant(undef): the defined bit is always false, so
        # the payload is never read. We still record a payload of i64 0 in
        # _undef_payload so that DefinedOr can phi-merge the LHS payload
        # when the defined path is taken (the optimizer will eliminate the
        # dead path but the IR must be well-formed).
        my $slot = $self->_fresh;
        $self->_emit("  $slot = alloca i1                            ; Constant(undef): defined-bit slot");
        $self->_emit("  store i1 false, i1* $slot                   ; Constant(undef): store false = not defined");
        my $defined_bit = $self->_fresh;
        $self->_emit("  $defined_bit = load i1, i1* $slot           ; Constant(undef): load defined bit (runtime-opaque)");

        # Record the defined bit so DefinedOr can retrieve it.
        $self->{_undef_defined_bit}{ $node->id } = $defined_bit;
        # Payload for undef LHS: i64 0 (never read on the undef path).
        my $payload = $self->_fresh;
        $self->_emit("  $payload = add i64 0, 0                     ; Constant(undef): payload i64 0 (never used)");
        $self->{_undef_payload}{ $node->id } = $payload;

        # The canonical SSA ref for an Undef-typed node is its defined bit (i1).
        # DefinedOr retrieves the payload via _undef_payload when needed.
        $self->{cache}{ $node->id } = $defined_bit;
        return $defined_bit;
    }
    else {
        die "LLVM backend: cannot lower Constant with repr=$repr";
    }
}

sub _lower_binop_int {
    my ($self, $node, $llvm_op) = @_;

    my $repr = $node->representation;
    my $op   = $node->operation;
    unless (defined $repr) {
        die "GAP: $op node has no representation at lowering time. "
          . "Fix TypeInference to annotate this node (G.6/F7).";
    }
    die "GAP: $op with repr=Scalar reached LLVM backend" if $repr eq 'Scalar';

    my $inputs  = $node->inputs;
    my $lhs_ref = $self->lower_value($inputs->[0]);
    my $rhs_ref = $self->lower_value($inputs->[1]);

    my $ref = $self->_fresh;
    $self->_emit("  $ref = $llvm_op i64 $lhs_ref, $rhs_ref  ; $op(repr=Int) -> i64 $llvm_op");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

sub _lower_divide {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    my $op   = $node->operation;

    # Divide with Int representation is a correctness trap: Perl `/` is always
    # floating-point division (3/4 == 0.75), not truncating integer division.
    # An Int-repr Divide would silently emit sdiv which miscompiles vs perl.
    # The correct path: give the Divide node Num representation and Coerce the
    # Int operands to Num before dividing.
    if (!defined $repr || $repr eq 'Int') {
        die "GAP: op=Divide with repr=" . ($repr // 'undef')
          . " — Perl `/` is float division; lower as Num (fdiv double) not i64 sdiv. "
          . "Set Divide representation to 'Num' and Coerce Int operands to Num.";
    }
    if ($repr eq 'Scalar') {
        die "GAP: Divide with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    # Num representation: fdiv double
    my $inputs  = $node->inputs;
    my $lhs_ref = $self->lower_value($inputs->[0]);
    my $rhs_ref = $self->lower_value($inputs->[1]);

    my $ref = $self->_fresh;
    $self->_emit("  $ref = fdiv double $lhs_ref, $rhs_ref  ; Divide(repr=Num) -> fdiv double");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

sub _lower_modulo {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    my $op   = $node->operation;

    if (defined $repr && $repr eq 'Scalar') {
        die "GAP: Modulo with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }
    if (defined $repr && $repr eq 'Num') {
        die "LLVM backend: Modulo with repr=Num not supported (fmod semantics differ from perl %)";
    }

    # Int representation: perl-semantics sign-corrected modulo.
    #
    # Perl `%` follows the SIGN of the RIGHT operand (the divisor), matching
    # mathematical modulo. LLVM `srem` follows the sign of the LEFT operand
    # (the dividend), like C `%`. For mixed-sign inputs these differ:
    #   perl:  -7 % 3 == 2    (positive, sign of divisor 3)
    #   srem:  -7 srem 3 == -1 (negative, sign of dividend -7)
    #
    # Sign-correction formula (branchless via select):
    #   t = a srem b
    #   needs_fix = (t != 0) AND ((t XOR b) < 0)   ; signs differ and remainder nonzero
    #   if needs_fix: t = t + b
    #
    # In LLVM IR (branchless with icmp + select):
    #   %t     = srem i64 %a, %b
    #   %xorv  = xor  i64 %t, %b
    #   %nonz  = icmp ne  i64 %t, 0
    #   %sneg  = icmp slt i64 %xorv, 0
    #   %fix   = and  i1  %nonz, %sneg
    #   %adj   = add  i64 %t, %b
    #   %res   = select i1 %fix, i64 %adj, i64 %t

    my $inputs  = $node->inputs;
    my $lhs_ref = $self->lower_value($inputs->[0]);
    my $rhs_ref = $self->lower_value($inputs->[1]);

    my $t    = $self->_fresh;
    my $xorv = $self->_fresh;
    my $nonz = $self->_fresh;
    my $sneg = $self->_fresh;
    my $fix  = $self->_fresh;
    my $adj  = $self->_fresh;
    my $res  = $self->_fresh;

    $self->_emit("  $t    = srem i64 $lhs_ref, $rhs_ref    ; Modulo step 1: srem (C/LLVM semantics)");
    $self->_emit("  $xorv = xor  i64 $t, $rhs_ref          ; Modulo step 2: signs-differ test");
    $self->_emit("  $nonz = icmp ne  i64 $t, 0              ; Modulo step 3: remainder nonzero?");
    $self->_emit("  $sneg = icmp slt i64 $xorv, 0           ; Modulo step 4: signs differ?");
    $self->_emit("  $fix  = and  i1  $nonz, $sneg           ; Modulo step 5: fix needed?");
    $self->_emit("  $adj  = add  i64 $t, $rhs_ref           ; Modulo step 6: adjusted value");
    $self->_emit("  $res  = select i1 $fix, i64 $adj, i64 $t ; Modulo step 7: perl-semantics result");

    $self->{cache}{$node->id} = $res;
    return $res;
}

# _lower_concat: emit Str concatenation as malloc+memcpy.
#
# Str = { ptr: i8*, len: i64, enc: i32 } where enc=0 (ASCII/default).
# Concat(a, b) allocates a new buffer of len(a)+len(b)+1 bytes (NUL term),
# copies a's bytes then b's bytes, returns the new ptr.
#
# The length of the result is tracked in _str_len_table for the output epilogue.
# The allocation is malloc (not alloca) — SOUND for G4 aggregates where Str values
# escape function frames. alloca would be unsound once a Str escapes its defining frame.
# The malloc leak is acceptable for main()-returns-then-process-exits patterns.
#
# Both operands must have Str representation; lengths must be tracked in
# _str_len_table. If a length is not tracked, the operation cannot be lowered safely.
sub _lower_concat {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    if (defined $repr && $repr ne 'Str') {
        die "GAP: Concat with repr=$repr reached LLVM backend — Concat requires Str operands";
    }

    my $inputs  = $node->inputs;
    my $lhs_ref = $self->lower_value($inputs->[0]);
    my $rhs_ref = $self->lower_value($inputs->[1]);

    # Look up the lengths of both operands.
    my $len_a = $self->_str_len_for($lhs_ref);
    my $len_b = $self->_str_len_for($rhs_ref);
    unless (defined $len_a && defined $len_b) {
        die "GAP: Concat cannot lower — one or both operand lengths not tracked in _str_len_table. "
          . "Only Str values produced by Constant(:Str) or Concat(:Str) have tracked lengths.";
    }

    # Compute result length = len_a + len_b. Emit as LLVM add i64 if either is
    # an SSA ref (not a literal); use the literal sum if both are literals.
    my $len_sum;
    if ($len_a =~ /^\d+$/ && $len_b =~ /^\d+$/) {
        # Both compile-time literals: compute the sum at codegen time.
        $len_sum = $len_a + $len_b;
    }
    else {
        # At least one is an SSA ref: emit add i64.
        my $la_ref = $len_a =~ /^\d+$/ ? $len_a : $len_a;
        my $lb_ref = $len_b =~ /^\d+$/ ? $len_b : $len_b;
        $len_sum = $self->_fresh;
        $self->_emit("  $len_sum = add i64 $la_ref, $lb_ref  ; Concat: total byte-len");
    }

    # Allocate: malloc(len_a + len_b + 1) — +1 for NUL terminator.
    my $total;
    if ($len_sum =~ /^\d+$/) {
        $total = $len_sum + 1;
    }
    else {
        $total = $self->_fresh;
        $self->_emit("  $total = add i64 $len_sum, 1  ; Concat: +1 for NUL terminator");
    }
    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 $total)  ; Concat: allocate result buffer");

    # Copy a's bytes (len_a bytes from lhs_ref into buf).
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $lhs_ref, i64 $len_a)  ; Concat: copy lhs");

    # Advance write ptr by len_a.
    my $buf_b = $self->_fresh;
    $self->_emit("  $buf_b = getelementptr inbounds i8, i8* $buf, i64 $len_a  ; Concat: ptr after lhs");

    # Copy b's bytes (len_b+1 bytes including NUL from rhs_ref — or len_b+1 bytes).
    # We copy len_b+1 to include the source NUL, completing the NUL terminator of result.
    my $copy_b_len;
    if ($len_b =~ /^\d+$/) {
        $copy_b_len = $len_b + 1;
    }
    else {
        $copy_b_len = $self->_fresh;
        $self->_emit("  $copy_b_len = add i64 $len_b, 1  ; Concat: rhs copy len +1 for NUL");
    }
    $self->_emit("  call i8* \@memcpy(i8* $buf_b, i8* $rhs_ref, i64 $copy_b_len)  ; Concat: copy rhs+NUL");

    # Track the result length and mark that malloc/memcpy declarations are needed.
    $self->{_str_len_table}{$buf} = $len_sum;
    $self->{_need_malloc_memcpy}  = 1;

    $self->{cache}{$node->id} = $buf;
    return $buf;
}

sub _lower_coerce {
    my ($self, $node) = @_;

    my $from = $node->from_repr;
    my $to   = $node->to_repr;
    my $input_ref = $self->lower_value($node->inputs->[0]);
    my $ref = $self->_fresh;

    if ($from eq 'Int' && $to eq 'Num') {
        $self->_emit("  $ref = sitofp i64 $input_ref to double  ; Coerce[Int->Num]");
    }
    elsif ($from eq 'Num' && $to eq 'Int') {
        $self->_emit("  $ref = fptosi double $input_ref to i64  ; Coerce[Num->Int]");
    }
    # Coerce(*->Bool) = truthiness: produce i1 from the input's machine type.
    elsif ($to eq 'Bool' && $from eq 'Int') {
        # Int truthiness: nonzero -> true (1), zero -> false (0).
        $self->_emit("  $ref = icmp ne i64 $input_ref, 0  ; Coerce[Int->Bool] truthiness");
    }
    elsif ($to eq 'Bool' && $from eq 'Num') {
        # Num truthiness: nonzero -> true, zero (including -0.0) -> false.
        $self->_emit("  $ref = fcmp une double $input_ref, 0.0  ; Coerce[Num->Bool] truthiness");
    }
    elsif ($to eq 'Bool' && $from eq 'Bool') {
        # Identity coercion — just pass through.
        $self->{cache}{$node->id} = $input_ref;
        return $input_ref;
    }
    # Coerce(Bool->Num) = 0 (false) or 1 (true): zero-extend i1 to i64.
    elsif ($from eq 'Bool' && $to eq 'Num') {
        $self->_emit("  $ref = zext i1 $input_ref to i64  ; Coerce[Bool->Num] 0/1");
    }
    # Coerce(Bool->Int) = 0/1: zero-extend i1 to i64 (same as Bool->Num for integers).
    elsif ($from eq 'Bool' && $to eq 'Int') {
        $self->_emit("  $ref = zext i1 $input_ref to i64  ; Coerce[Bool->Int] 0/1");
    }
    # Coerce(Bool->Str) = select between "" and "1" string-face constants.
    # The Str representation is not fully modelled yet (G3), but the Bool string-face
    # is only two constant strings and can be lowered as a select i1 between them.
    # Returns an i8* that points to the selected string constant.
    elsif ($from eq 'Bool' && $to eq 'Str') {
        # These globals will be emitted by the return-path epilogue when repr=Bool.
        # For Coerce(Bool->Str) used internally (not at return), we re-emit locally.
        my $true_g  = '@coerce_bool_str_true';
        my $false_g = '@coerce_bool_str_false';
        # The globals are declared at the module level by the emitter when needed.
        # We flag that they're needed so the prologue includes them.
        $self->{_need_bool_str_globals} = true;
        my $tp  = $self->_fresh;
        my $fp  = $self->_fresh;
        $self->_emit("  $tp = getelementptr inbounds [2 x i8], [2 x i8]* $true_g,  i64 0, i64 0  ; Coerce[Bool->Str] true ptr");
        $self->_emit("  $fp = getelementptr inbounds [1 x i8], [1 x i8]* $false_g, i64 0, i64 0  ; Coerce[Bool->Str] false ptr");
        $self->_emit("  $ref = select i1 $input_ref, i8* $tp, i8* $fp  ; Coerce[Bool->Str] select");
    }
    # Coerce(Str->Num): perl leading-numeric rule.
    # "3abc"->3, "abc"->0, " 42"->42, "3.14x"->3.14, ""->0, ".5"->0.5,
    # "0x10"->0 (perl does NOT parse hex).
    #
    # Implementation: call a module-level helper @chalk_str_to_num(i8* ptr, i64 len)
    # -> double. The helper uses libc strtod (host-C, NOT libperl) with a pre-check
    # that returns 0.0 for any string starting with "0x" or "0X" (the one known
    # divergence between strtod and perl's rule). strtod matches perl for all other
    # leading-numeric forms. See G3 implementation notes.
    elsif ($from eq 'Str' && $to eq 'Num') {
        my $ptr_ref = $input_ref;
        my $len_ref = $self->_str_len_for($ptr_ref) // 0;
        # Flag that the str-to-num helper + strtod declaration are needed.
        $self->{_need_str_to_num_helper} = 1;
        $self->_emit("  $ref = call double \@chalk_str_to_num(i8* $ptr_ref, i64 $len_ref)  ; Coerce[Str->Num] leading-numeric");
    }
    # Coerce(Str->Bool): perl's string truthiness rule.
    # false iff the string is "" (empty) or exactly "0".
    # "0.0","00","0 " etc. are all TRUE (only exact "0" and "" are false).
    #
    # Implementation: branchless LLVM IR:
    #   is_empty = (len == 0)
    #   first_byte = load i8 from ptr (safe since we gep+load conditionally)
    #   is_zero_char = (first_byte == '0')
    #   is_single_char = (len == 1)
    #   is_single_zero = (is_single_char AND is_zero_char)
    #   is_false = (is_empty OR is_single_zero)
    #   result = NOT is_false  (true iff not false)
    elsif ($from eq 'Str' && $to eq 'Bool') {
        my $ptr_ref = $input_ref;
        my $len_ref = $self->_str_len_for($ptr_ref) // 0;
        # is_empty = (len == 0)
        my $is_empty = $self->_fresh;
        $self->_emit("  $is_empty = icmp eq i64 $len_ref, 0  ; Coerce[Str->Bool]: len==0 check");
        # Load the first byte conditionally: use select to get '0' when empty
        # (the byte doesn't matter when empty; we AND with is_single_zero anyway).
        # Safe approach: GEP ptr (valid even at length 0 for constant globals),
        # load the byte, then mask out the result with is_single_zero.
        my $first_byte_ptr = $self->_fresh;
        $self->_emit("  $first_byte_ptr = getelementptr inbounds i8, i8* $ptr_ref, i64 0  ; Coerce[Str->Bool]: ptr to first byte");
        my $first_byte = $self->_fresh;
        $self->_emit("  $first_byte = load i8, i8* $first_byte_ptr  ; Coerce[Str->Bool]: load first byte");
        # is_zero_char = (first_byte == '0' = 48)
        my $is_zero_char = $self->_fresh;
        $self->_emit("  $is_zero_char = icmp eq i8 $first_byte, 48  ; Coerce[Str->Bool]: first byte == '0'");
        # is_single_char = (len == 1)
        my $is_single = $self->_fresh;
        $self->_emit("  $is_single = icmp eq i64 $len_ref, 1  ; Coerce[Str->Bool]: len==1 check");
        # is_single_zero = is_single AND is_zero_char
        my $is_single_zero = $self->_fresh;
        $self->_emit("  $is_single_zero = and i1 $is_single, $is_zero_char  ; Coerce[Str->Bool]: single-zero check");
        # is_false = is_empty OR is_single_zero
        my $is_false = $self->_fresh;
        $self->_emit("  $is_false = or i1 $is_empty, $is_single_zero  ; Coerce[Str->Bool]: is false?");
        # result = NOT is_false -> true iff non-empty and not "0"
        $self->_emit("  $ref = xor i1 $is_false, true  ; Coerce[Str->Bool]: invert -> Bool");
    }
    elsif ($from eq 'Scalar' || $to eq 'Scalar') {
        die "GAP: Coerce involving Scalar reached LLVM backend — cannot lower runtime-free.";
    }
    else {
        die "LLVM backend: cannot lower Coerce[$from->$to]";
    }

    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# _lower_not: emit UnaryNot(Bool)->Bool.
#
# Perl `!` takes the TRUTHINESS of its operand (regardless of the operand's
# representation) and returns a genuine Bool (is_bool=1).
#
# Implementation:
#   1. Lower the operand. Produce an i1 via _ensure_i1 (coerces Int to Bool
#      if needed: icmp ne i64 %x, 0).
#   2. Emit: %result = xor i1 %cond, true   ; logical negation
#
# The result is i1 (Bool representation), which is then returned or used as
# a condition in the enclosing expression.
sub _lower_not {
    my ($self, $node) = @_;

    my $repr = $node->representation;

    my $inputs   = $node->inputs;
    my $operand  = $inputs->[0];
    my $op_ref   = $self->lower_value($operand);
    my $op_repr  = $operand->representation;
    die "LLVM backend: Not operand has no representation set — cannot determine i1 vs i64"
        unless defined $op_repr;

    # Convert operand to i1 (truthiness) if it is not already Bool.
    my $cond_ref = $self->_ensure_i1($op_ref, $op_repr);

    my $ref = $self->_fresh;
    $self->_emit("  $ref = xor i1 $cond_ref, true  ; Not: logical negation -> Bool(i1)");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# _ensure_i1($ref, $repr) -> $i1_ref
#
# If $repr is 'Bool', the value is already i1 — return $ref unchanged.
# If $repr is 'Int', emit an icmp ne i64 %ref, 0 to produce a truthiness i1.
# If $repr is 'Num', emit an fcmp une double %ref, 0.0.
# This is Coerce(*->Bool) = truthiness, used inline by _lower_not.
sub _ensure_i1 {
    my ($self, $ref, $repr) = @_;
    die "LLVM backend: _ensure_i1 called with undef repr — operand must have a representation set"
        unless defined $repr;

    return $ref if $repr eq 'Bool';

    my $cond = $self->_fresh;
    if ($repr eq 'Int') {
        $self->_emit("  $cond = icmp ne i64 $ref, 0  ; _ensure_i1: Int truthiness -> i1");
    }
    elsif ($repr eq 'Num') {
        $self->_emit("  $cond = fcmp une double $ref, 0.0  ; _ensure_i1: Num truthiness -> i1");
    }
    else {
        die "LLVM backend: _ensure_i1 cannot convert repr=$repr to i1";
    }
    return $cond;
}

# ---------------------------------------------------------------------------
# SSA-value threading for lexical scalar variables (Phase 3c)
#
# Model: straight-line code only (no branches, no loops). VarDecl stores its
# initialized SSA value in var_table[vd_id]. PadAccess reads it. Assign and
# CompoundAssign update it. This covers A1, A4, C1, C2, K1, K2 from the
# gap-map without needing alloca+store+load (LLVM mem2reg would do the same
# optimization anyway; we do it directly at the IR level).
#
# The var_table is keyed by VarDecl node id. PadAccess locates its VarDecl
# via inputs->[0]. Assign locates the VarDecl via inputs->[0] (the lhs
# PadAccess), then inputs->[0] of that (the VarDecl).
# ---------------------------------------------------------------------------

# _lower_vardecl: store the initializer's SSA value in var_table; return it.
sub _lower_vardecl {
    my ($self, $node) = @_;

    my $repr = _require_repr($node, 'VarDecl');
    if ($repr eq 'Scalar') {
        die "GAP: VarDecl with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $init_node = $node->inputs->[1];    # inputs[1] = init value (or undef)
    my $init_ref;
    if (defined $init_node) {
        $init_ref = $self->lower_value($init_node);
    }
    else {
        # No initializer: use a zero/empty value for the type.
        if ($repr eq 'Str') {
            die "GAP: VarDecl with repr=Str and no initializer reached LLVM backend — "
              . "uninit Str is not yet lowered (would require an empty-string global).";
        }
        my $zero = $self->_fresh;
        if ($repr eq 'Num') {
            $self->_emit("  $zero = fadd double 0.0, 0.0  ; VarDecl uninit Num -> 0.0");
        }
        else {
            $self->_emit("  $zero = add i64 0, 0  ; VarDecl uninit Int -> 0");
        }
        $init_ref = $zero;
    }

    # Store the SSA value in the var_table under this VarDecl's id.
    # Also record the representation for this VarDecl so the if/else merge
    # phi can derive the correct LLVM type (B2 fix).
    $self->{var_table}{ $node->id }  = $init_ref;
    $self->{cache}{ $node->id }      = $init_ref;
    $self->{_vd_repr}{ $node->id }   = $repr;

    # Undef representation: propagate the defined-bit and payload from the init
    # node to this VarDecl, indexed by VarDecl id. DefinedOr looks up the payload
    # by the PadAccess node's VarDecl id to complete the phi merge.
    if ($repr eq 'Undef' && defined $init_node) {
        my $init_id = $init_node->id;
        if (exists $self->{_undef_defined_bit}{$init_id}) {
            $self->{_undef_defined_bit}{ $node->id } = $self->{_undef_defined_bit}{$init_id};
        }
        if (exists $self->{_undef_payload}{$init_id}) {
            $self->{_undef_payload}{ $node->id } = $self->{_undef_payload}{$init_id};
        }
    }

    return $init_ref;
}

# _lower_padaccess: read the current SSA value from the var_table.
sub _lower_padaccess {
    my ($self, $node) = @_;

    my $repr = _require_repr($node, 'PadAccess');
    if ($repr eq 'Scalar') {
        die "GAP: PadAccess with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    # Locate the VarDecl via inputs->[0].
    my $vd = $node->inputs->[0];
    unless (defined $vd) {
        die "LLVM backend: PadAccess has no VarDecl input (inputs->[0] is undef); "
          . "hand-authored graphs must wire PadAccess.inputs[0] = VarDecl";
    }

    # Ensure the VarDecl has been lowered (it may be in the data-chain, in
    # which case lower_value(VarDecl) processes it here; or it was already
    # processed by process_control_node).
    my $vd_id = $vd->id;
    unless (exists $self->{var_table}{$vd_id}) {
        $self->lower_value($vd);
    }

    my $val_ref = $self->{var_table}{$vd_id};
    unless (defined $val_ref) {
        die "LLVM backend: PadAccess var_table has no entry for VarDecl id=$vd_id";
    }

    # PadAccess emits no instructions; it returns the current SSA ref from
    # var_table. Cache it so non-PadAccess nodes that take this as an input
    # (e.g. an Add that shares the same PadAccess) get the same %tmp ref.
    # lower_value() always bypasses the cache for PadAccess ops (the cache-hit
    # path checks $op ne 'PadAccess') so this write is only used by non-PadAccess
    # consumers of the same node id — a safe sharing pattern.
    $self->{cache}{ $node->id } = $val_ref;

    # Undef representation: propagate _undef_defined_bit and _undef_payload
    # from the VarDecl to this PadAccess node id. DefinedOr looks up the
    # payload by the LHS node's id (the PadAccess), not the VarDecl's id.
    if ($repr eq 'Undef') {
        if (exists $self->{_undef_defined_bit}{$vd_id}) {
            $self->{_undef_defined_bit}{ $node->id } = $self->{_undef_defined_bit}{$vd_id};
        }
        if (exists $self->{_undef_payload}{$vd_id}) {
            $self->{_undef_payload}{ $node->id } = $self->{_undef_payload}{$vd_id};
        }
    }

    return $val_ref;
}

# _lower_assign: lower the RHS value and update the target.
# Returns the new SSA value (the RHS).
# Two modes:
#  (a) Subscript-lvalue: inputs[0] is a Subscript node → emit an element store
#      (bounds-checked slot write into the container array or hash).
#  (b) Scalar rebind: inputs[0] is a PadAccess(VarDecl) or VarDecl →
#      update var_table with the new SSA value.
sub _lower_assign {
    my ($self, $node) = @_;

    my $repr = _require_repr($node, 'Assign');
    if ($repr eq 'Scalar') {
        die "GAP: Assign with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $lhs = $node->inputs->[0];
    my $rhs = $node->inputs->[1];

    my $rhs_ref = $self->lower_value($rhs);

    # Mode (fa): FieldAccess-lvalue — field store into a class object struct.
    # Dissolves F9: the FieldAccess carries field_stash (class name) explicitly,
    # so no ambient _method_class_name is needed to identify the class.
    # The object pointer still comes from the ambient _method_self_name (the
    # implicit $self in method and ADJUST body contexts).
    if (defined $lhs && $lhs->can('operation') && $lhs->operation eq 'FieldAccess') {
        my $field_index = $lhs->field_index;
        my $class_name  = $lhs->field_stash;
        my $val_repr    = _require_repr($rhs, 'Assign(FieldAccess-lvalue).rhs');
        my $slot_idx    = $field_index + 1;
        # Self pointer: must be in method/ADJUST body context
        my $obj_raw = $self->{_method_self_name}
            // die "LLVM MOP: Assign(FieldAccess-lvalue) used outside method/ADJUST body context "
                 . "— _method_self_name not set";
        my $obj_typed = $self->_fresh;
        $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; Assign(FieldAccess-lvalue): typed self");
        # Store defined=true
        my $def_gep = $self->_fresh;
        $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 0  ; FieldAccess-lvalue[$field_index] defined");
        $self->_emit("  store i1 true, i1* $def_gep  ; FieldAccess-lvalue[$field_index] defined=true");
        # Store payload
        my $pay_gep = $self->_fresh;
        $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 1  ; FieldAccess-lvalue[$field_index] payload");
        my $pay_i64 = $self->_fresh;
        if ($val_repr eq 'Bool') {
            $self->_emit("  $pay_i64 = zext i1 $rhs_ref to i64  ; Bool->i64 FieldAccess-lvalue");
        } else {
            $self->_emit("  $pay_i64 = add i64 0, $rhs_ref  ; identity: $val_repr->i64 FieldAccess-lvalue");
        }
        $self->_emit("  store i64 $pay_i64, i64* $pay_gep  ; FieldAccess-lvalue[$field_index] payload");
        $self->{cache}{ $node->id } = $pay_i64;
        return $pay_i64;
    }

    # Mode (a): Subscript-lvalue — element store into Array or Hash.
    if (defined $lhs && $lhs->operation eq 'Subscript') {
        my $container = $lhs->inputs->[0];
        my $key_idx   = $lhs->inputs->[1];
        my $ctr_repr  = $container->representation // '';

        if ($ctr_repr eq 'Array' || $ctr_repr eq 'ArrayRef') {
            # Array element store: bounds-checked (same as _lower_array_write body).
            $self->{_need_aggregate_types} = 1;

            # Get the Array* (from _arr_table for ArrayRef containers).
            my $arr_ref;
            if ($ctr_repr eq 'ArrayRef') {
                $self->lower_value($container);
                unless (exists $self->{_arr_table}{ $container->id }) {
                    my $i8 = $self->{cache}{ $container->id };
                    my $arr = $self->_fresh;
                    $self->_emit("  $arr = bitcast i8* $i8 to %Array*  ; Assign(Array-lvalue): i8* -> Array*");
                    $self->{_arr_table}{ $container->id } = $arr;
                }
                $arr_ref = $self->{_arr_table}{ $container->id };
            }
            else {
                $arr_ref = $self->lower_value($container);
            }
            my $idx_ref = $self->lower_value($key_idx);

            # Load elems pointer and write the slot.
            my $elem_ptr = $self->_fresh;
            my $elems    = $self->_fresh;
            $self->_emit("  $elem_ptr = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 2  ; Assign(Array-lvalue): elems ptr");
            $self->_emit("  $elems = load %Slot*, %Slot** $elem_ptr  ; Assign(Array-lvalue): load elems");
            my $slot_def = $self->_fresh;
            my $slot_pay = $self->_fresh;
            $self->_emit("  $slot_def = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx_ref, i32 0  ; Assign(Array-lvalue): slot def ptr");
            $self->_emit("  $slot_pay = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx_ref, i32 1  ; Assign(Array-lvalue): slot pay ptr");
            $self->_emit("  store i1 true, i1* $slot_def  ; Assign(Array-lvalue): defined=true");
            # If the rhs is a pointer-repr value (ArrayRef/HashRef), ptrtoint before
            # storing into the i64 payload slot — mirrors _lower_array_ref 3164-3172.
            my $rhs_repr = $rhs->representation // '';
            my $rhs_i64;
            if ($rhs_repr eq 'ArrayRef' || $rhs_repr eq 'HashRef') {
                $rhs_i64 = $self->_fresh;
                $self->_emit("  $rhs_i64 = ptrtoint i8* $rhs_ref to i64  ; Assign(Array-lvalue): ptr rhs -> i64");
            }
            else {
                $rhs_i64 = $rhs_ref;
            }
            $self->_emit("  store i64 $rhs_i64, i64* $slot_pay  ; Assign(Array-lvalue): store value");

            $self->{cache}{ $node->id } = $rhs_ref;
            return $rhs_ref;
        }
        elsif ($ctr_repr eq 'Hash' || $ctr_repr eq 'HashRef') {
            # Hash element store: linear-scan key lookup and value update (same body as _lower_hash_write).
            $self->{_need_aggregate_types} = 1;
            $self->{_need_malloc_memcpy}   = 1;
            $self->{_need_memcmp}          = 1;

            my $hash_ref;
            if ($ctr_repr eq 'HashRef') {
                $self->lower_value($container);
                unless (exists $self->{_hash_table}{ $container->id }) {
                    my $i8 = $self->{cache}{ $container->id };
                    my $hash = $self->_fresh;
                    $self->_emit("  $hash = bitcast i8* $i8 to %Hash*  ; Assign(Hash-lvalue): i8* -> Hash*");
                    $self->{_hash_table}{ $container->id } = $hash;
                }
                $hash_ref = $self->{_hash_table}{ $container->id };
            }
            else {
                $hash_ref = $self->lower_value($container);
            }
            my $wkey_ref = $self->lower_value($key_idx);
            # See HashRead: a 0-length key makes the memcmp match any entry.
            # Die loudly on an untracked length rather than default to 0.
            my $wkey_len = $self->_str_len_for($wkey_ref)
                // die "GAP: Assign(Hash-lvalue) key (ref=$wkey_ref) has no tracked "
                     . "length — would emit a 0-length memcmp matching any entry.";

            my $cnt_ptr = $self->_fresh;
            my $ent_ptr = $self->_fresh;
            my $count   = $self->_fresh;
            my $ents    = $self->_fresh;
            $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 0  ; Assign(Hash-lvalue): count ptr");
            $self->_emit("  $ent_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 2  ; Assign(Hash-lvalue): entries ptr");
            $self->_emit("  $count = load i64, i64* $cnt_ptr  ; Assign(Hash-lvalue): load count");
            $self->_emit("  $ents  = load %HashEntry*, %HashEntry** $ent_ptr  ; Assign(Hash-lvalue): load entries");

            my $lbl_wloop = $self->_fresh_label('hwalp');
            my $lbl_wchk  = $self->_fresh_label('hwchk');
            my $lbl_wcmp  = $self->_fresh_label('hwcmp');
            my $lbl_wupd  = $self->_fresh_label('hwupd');
            my $lbl_wnxt  = $self->_fresh_label('hwnxt');
            my $lbl_wend  = $self->_fresh_label('hwend');
            my $lbl_wpre  = $self->_current_block_label;
            my $wi_next   = $self->_fresh;

            $self->_set_terminator("  br label \%$lbl_wloop");
            $self->_new_block($lbl_wloop);
            my $wi_phi = $self->_fresh;
            $self->_emit("  $wi_phi = phi i64 [ 0, \%$lbl_wpre ], [ $wi_next, \%$lbl_wnxt ]  ; Assign(Hash-lvalue): loop counter");
            my $wcond = $self->_fresh;
            $self->_emit("  $wcond = icmp ult i64 $wi_phi, $count  ; Assign(Hash-lvalue): i < count?");
            $self->_set_terminator("  br i1 $wcond, label \%$lbl_wchk, label \%$lbl_wend");

            $self->_new_block($lbl_wchk);
            my $went_p   = $self->_fresh;
            my $went_kpp = $self->_fresh;
            my $went_klp = $self->_fresh;
            my $went_vpp = $self->_fresh;
            my $went_kp  = $self->_fresh;
            my $went_kl  = $self->_fresh;
            $self->_emit("  $went_p   = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $wi_phi  ; Assign(Hash-lvalue): entry ptr");
            $self->_emit("  $went_kpp = getelementptr inbounds %HashEntry, %HashEntry* $went_p, i32 0, i32 0  ; Assign(Hash-lvalue): key_ptr field");
            $self->_emit("  $went_klp = getelementptr inbounds %HashEntry, %HashEntry* $went_p, i32 0, i32 1  ; Assign(Hash-lvalue): key_len field");
            $self->_emit("  $went_vpp = getelementptr inbounds %HashEntry, %HashEntry* $went_p, i32 0, i32 4  ; Assign(Hash-lvalue): val_pay field");
            $self->_emit("  $went_kp  = load i8*,  i8**  $went_kpp  ; Assign(Hash-lvalue): entry key ptr");
            $self->_emit("  $went_kl  = load i64,  i64*  $went_klp  ; Assign(Hash-lvalue): entry key len");
            my $wlen_eq = $self->_fresh;
            $self->_emit("  $wlen_eq = icmp eq i64 $went_kl, $wkey_len  ; Assign(Hash-lvalue): len eq");
            $self->_set_terminator("  br i1 $wlen_eq, label \%$lbl_wcmp, label \%$lbl_wnxt");

            $self->_new_block($lbl_wcmp);
            my $wcmp_res  = $self->_fresh;
            my $wis_match = $self->_fresh;
            $self->_emit("  $wcmp_res  = call i32 \@memcmp(i8* nocapture readonly $went_kp, i8* nocapture readonly $wkey_ref, i64 $wkey_len)  ; Assign(Hash-lvalue): key memcmp");
            $self->_emit("  $wis_match = icmp eq i32 $wcmp_res, 0  ; Assign(Hash-lvalue): key match?");
            $self->_set_terminator("  br i1 $wis_match, label \%$lbl_wupd, label \%$lbl_wnxt");

            $self->_new_block($lbl_wupd);
            # If the rhs is a pointer-repr value (ArrayRef/HashRef), ptrtoint before
            # storing into the i64 payload slot — mirrors the array-lvalue branch
            # above (and _lower_array_ref). Without this guard a ref value emits
            # `store i64 i8*`, which is invalid IR.
            my $wrhs_repr = $rhs->representation // '';
            my $wrhs_i64;
            if ($wrhs_repr eq 'ArrayRef' || $wrhs_repr eq 'HashRef') {
                $wrhs_i64 = $self->_fresh;
                $self->_emit("  $wrhs_i64 = ptrtoint i8* $rhs_ref to i64  ; Assign(Hash-lvalue): ptr rhs -> i64");
            }
            else {
                $wrhs_i64 = $rhs_ref;
            }
            $self->_emit("  store i64 $wrhs_i64, i64* $went_vpp  ; Assign(Hash-lvalue): update val_payload");
            $self->_set_terminator("  br label \%$lbl_wend");

            $self->_new_block($lbl_wnxt);
            $self->_emit("  $wi_next = add i64 $wi_phi, 1  ; Assign(Hash-lvalue): i++");
            $self->_set_terminator("  br label \%$lbl_wloop");

            $self->_new_block($lbl_wend);

            $self->{cache}{ $node->id } = $rhs_ref;
            return $rhs_ref;
        }
        else {
            die "GAP: Assign(Subscript-lvalue) container has repr=$ctr_repr; "
              . "only Array/ArrayRef element stores are lowered runtime-free.";
        }
    }

    # Mode (b): scalar rebind — find the VarDecl the lhs points to.
    my $vd = $lhs;
    if (defined $vd && $vd->operation eq 'PadAccess') {
        $vd = $lhs->inputs->[0];
    }
    unless (defined $vd && $vd->operation eq 'VarDecl') {
        die "LLVM backend: Assign lhs must be a PadAccess(VarDecl), VarDecl, or Subscript(lvalue); "
          . "got " . (defined $vd ? $vd->operation : 'undef');
    }

    $self->{var_table}{ $vd->id } = $rhs_ref;
    $self->{cache}{ $node->id }   = $rhs_ref;
    return $rhs_ref;
}

# ---------------------------------------------------------------------------
# Comparison operators and TernaryExpr (Phase 3c — D6 ternary/select path)
#
# Numeric comparisons lower to LLVM icmp instructions (signed for i64),
# producing i1 results (Bool representation). These are used as conditions
# for select (TernaryExpr) and eventually for branch instructions.
#
# LLVM icmp predicate mapping (signed integers):
#   NumGt -> sgt (signed greater-than)
#   NumLt -> slt (signed less-than)
#   NumGe -> sge (signed greater-or-equal)
#   NumLe -> sle (signed less-or-equal)
#   NumEq -> eq  (equality, sign-independent)
#   NumNe -> ne  (inequality, sign-independent)
#
# TernaryExpr ($cond ? $true : $false) lowers to `select` when:
#   - condition has Bool representation (i1, from icmp)
#   - both branches have Int representation (i64)
# This covers D6 from the gap-map without needing Phi or basic blocks.
# ---------------------------------------------------------------------------

my %ICMP_PREDICATE = (
    NumGt => 'sgt',
    NumLt => 'slt',
    NumGe => 'sge',
    NumLe => 'sle',
    NumEq => 'eq',
    NumNe => 'ne',
);

sub _lower_icmp_int {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    my $op   = $node->operation;

    if (defined $repr && $repr eq 'Scalar') {
        die "GAP: $op with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $pred = $ICMP_PREDICATE{$op}
        or die "LLVM backend: unknown comparison op=$op";

    my $inputs  = $node->inputs;
    my $lhs_ref = $self->lower_value($inputs->[0]);
    my $rhs_ref = $self->lower_value($inputs->[1]);

    my $ref = $self->_fresh;
    $self->_emit("  $ref = icmp $pred i64 $lhs_ref, $rhs_ref  ; $op(Bool) -> i1 icmp $pred");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

sub _lower_ternary {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    my $op   = $node->operation;

    if (defined $repr && $repr eq 'Scalar') {
        die "GAP: TernaryExpr with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $inputs    = $node->inputs;
    my $cond_node = $inputs->[0];
    my $true_node = $inputs->[1];
    my $fals_node = $inputs->[2];

    # Lower the condition: must produce an i1 (Bool representation).
    my $cond_ref = $self->lower_value($cond_node);

    # Lower the true and false branches: must be same type (Int -> i64).
    my $true_ref = $self->lower_value($true_node);
    my $fals_ref = $self->lower_value($fals_node);

    # Determine the branch type for the select.
    my $true_repr = _require_repr($true_node, 'TernaryExpr.true_branch');
    my $fals_repr = _require_repr($fals_node, 'TernaryExpr.false_branch');

    my $branch_type;
    if ($true_repr eq 'Int' && $fals_repr eq 'Int') {
        $branch_type = 'i64';
    }
    elsif ($true_repr eq 'Num' && $fals_repr eq 'Num') {
        $branch_type = 'double';
    }
    else {
        die "LLVM backend: TernaryExpr branches have mismatched or unsupported types "
          . "(true=$true_repr, false=$fals_repr)";
    }

    my $ref = $self->_fresh;
    $self->_emit("  $ref = select i1 $cond_ref, $branch_type $true_ref, $branch_type $fals_ref"
        . "  ; TernaryExpr -> select");
    $self->{cache}{$node->id} = $ref;
    return $ref;
}

# ---------------------------------------------------------------------------
# Short-circuit logical operators: And (&&) and Or (||)
#
# Both operators return ONE OF THEIR OPERANDS, not a boolean.
# Implementation uses basic blocks + conditional branch + phi.
#
# And(a, b):
#   Evaluate a. Test a != 0 (truthy). If true -> evaluate b, go to end.
#   If false -> skip b, go to end with a.
#   phi merges: [a from entry/prior-block] or [b from rhs-block].
#
# Or(a, b):
#   Evaluate a. Test a != 0 (truthy). If true -> skip b, go to end with a.
#   If false -> evaluate b, go to end.
#   phi merges: [a from entry/prior-block] or [b from rhs-block].
#
# The RHS is evaluated INSIDE a separate block (short-circuit: side effects
# in the RHS only happen if the test takes the rhs branch).
# ---------------------------------------------------------------------------

sub _lower_and {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    if (defined $repr && $repr eq 'Scalar') {
        die "GAP: And with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $inputs = $node->inputs;
    my $lhs_node = $inputs->[0];
    my $rhs_node = $inputs->[1];

    # Validate LHS repr: only Int operands use the icmp ne i64 truthiness path.
    # G.7/F8: die loudly on non-Int operands instead of silently reinterpreting
    # Bool(i1) or Num(double) as i64 (which would miscompile).
    my $lhs_repr = $lhs_node->representation;
    unless (defined $lhs_repr) {
        die "GAP: And (&&) LHS operand has no representation at lowering time (G.7/F8). "
          . "Fix TypeInference to annotate the operand.";
    }
    unless ($lhs_repr eq 'Int') {
        die "GAP: And (&&) LHS operand has repr=$lhs_repr; only Int truthiness is lowered "
          . "runtime-free via icmp ne i64 (G.7/F8). "
          . "Insert an explicit Coerce(*->Bool) node before the And, or fix TypeInference.";
    }

    # I2: Validate RHS repr identically to LHS.
    # A non-Int RHS would cause the phi to mix i64 with i1/double = invalid LLVM.
    # The phi type is derived from the And node's repr (Int); merging a non-Int RHS
    # ref into an Int phi is invalid IR.  Die loudly rather than produce a bad phi.
    my $rhs_repr = $rhs_node->representation;
    unless (defined $rhs_repr) {
        die "GAP: And (&&) RHS operand has no representation at lowering time (I2/G.7/F8). "
          . "Fix TypeInference to annotate the operand.";
    }
    unless ($rhs_repr eq 'Int') {
        die "GAP: And (&&) RHS operand has repr=$rhs_repr; only Int truthiness is lowered "
          . "runtime-free via icmp ne i64 (I2/G.7/F8). "
          . "Insert an explicit Coerce(*->Bool) node before the And, or fix TypeInference.";
    }

    # Lower the LHS in the current block.
    my $lhs_ref    = $self->lower_value($lhs_node);
    my $entry_label = $self->_current_block_label;

    # Test LHS truthiness (nonzero for Int).
    my $cond = $self->_fresh;
    $self->_emit("  $cond = icmp ne i64 $lhs_ref, 0  ; And: test lhs truthiness");

    # Allocate block labels.
    my $rhs_label = $self->_fresh_label('and.rhs.');
    my $end_label = $self->_fresh_label('and.end.');

    # Conditional branch: truthy -> rhs block; falsy -> end block with lhs.
    $self->_set_terminator("  br i1 $cond, label %$rhs_label, label %$end_label  ; And: short-circuit branch");

    # RHS block: evaluate the RHS, then jump to end.
    $self->_new_block($rhs_label);
    my $rhs_ref       = $self->lower_value($rhs_node);
    my $rhs_end_label = $self->_current_block_label;   # may differ if rhs has its own blocks
    $self->_set_terminator("  br label %$end_label  ; And: rhs falls through to end");

    # End block: phi merges lhs (falsy path) and rhs (truthy path).
    $self->_new_block($end_label);
    my $result = $self->_fresh;
    # G.7 guarantees the And node's own repr is Int (LHS guard above already died on
    # non-Int). The `// 'Int'` default is intentional: it handles the narrow case where
    # TypeInference annotated the LHS operands but did not annotate the And node itself.
    # In that case Int is the only correct choice (short-circuit of two Int operands
    # always yields Int). _require_repr is NOT used here to avoid a GAP-die on that
    # legitimate-but-unannotated case; the LHS guard provides the real safety net.
    my $llvm_type = _repr_to_llvm_type($repr // 'Int');
    $self->_emit("  $result = phi $llvm_type [ $lhs_ref, %$entry_label ], [ $rhs_ref, %$rhs_end_label ]  ; And: phi");

    $self->{cache}{$node->id} = $result;
    return $result;
}

sub _lower_or {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    if (defined $repr && $repr eq 'Scalar') {
        die "GAP: Or with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $inputs = $node->inputs;
    my $lhs_node = $inputs->[0];
    my $rhs_node = $inputs->[1];

    # Validate LHS repr: only Int operands use the icmp ne i64 truthiness path.
    # G.7/F8: die loudly on non-Int operands instead of silently reinterpreting
    # Bool(i1) or Num(double) as i64 (which would miscompile).
    my $lhs_repr = $lhs_node->representation;
    unless (defined $lhs_repr) {
        die "GAP: Or (||) LHS operand has no representation at lowering time (G.7/F8). "
          . "Fix TypeInference to annotate the operand.";
    }
    unless ($lhs_repr eq 'Int') {
        die "GAP: Or (||) LHS operand has repr=$lhs_repr; only Int truthiness is lowered "
          . "runtime-free via icmp ne i64 (G.7/F8). "
          . "Insert an explicit Coerce(*->Bool) node before the Or, or fix TypeInference.";
    }

    # I2: Validate RHS repr identically to LHS.
    # A non-Int RHS would cause the phi to mix i64 with i1/double = invalid LLVM.
    my $rhs_repr = $rhs_node->representation;
    unless (defined $rhs_repr) {
        die "GAP: Or (||) RHS operand has no representation at lowering time (I2/G.7/F8). "
          . "Fix TypeInference to annotate the operand.";
    }
    unless ($rhs_repr eq 'Int') {
        die "GAP: Or (||) RHS operand has repr=$rhs_repr; only Int truthiness is lowered "
          . "runtime-free via icmp ne i64 (I2/G.7/F8). "
          . "Insert an explicit Coerce(*->Bool) node before the Or, or fix TypeInference.";
    }

    # Lower the LHS in the current block.
    my $lhs_ref    = $self->lower_value($lhs_node);
    my $entry_label = $self->_current_block_label;

    # Test LHS truthiness (nonzero for Int).
    my $cond = $self->_fresh;
    $self->_emit("  $cond = icmp ne i64 $lhs_ref, 0  ; Or: test lhs truthiness");

    # Allocate block labels.
    my $rhs_label = $self->_fresh_label('or.rhs.');
    my $end_label = $self->_fresh_label('or.end.');

    # Conditional branch: truthy -> end block with lhs; falsy -> rhs block.
    $self->_set_terminator("  br i1 $cond, label %$end_label, label %$rhs_label  ; Or: short-circuit branch");

    # RHS block: evaluate the RHS, then jump to end.
    $self->_new_block($rhs_label);
    my $rhs_ref       = $self->lower_value($rhs_node);
    my $rhs_end_label = $self->_current_block_label;
    $self->_set_terminator("  br label %$end_label  ; Or: rhs falls through to end");

    # End block: phi merges lhs (truthy path) and rhs (falsy path).
    $self->_new_block($end_label);
    my $result = $self->_fresh;
    # G.7 guarantees the Or node's own repr is Int (LHS guard above already died on
    # non-Int). The `// 'Int'` default is intentional: same rationale as _lower_and —
    # handles the unannotated-Or-node case without a spurious GAP-die. See _lower_and.
    my $llvm_type = _repr_to_llvm_type($repr // 'Int');
    $self->_emit("  $result = phi $llvm_type [ $lhs_ref, %$entry_label ], [ $rhs_ref, %$rhs_end_label ]  ; Or: phi");

    $self->{cache}{$node->id} = $result;
    return $result;
}

# ---------------------------------------------------------------------------
# DefinedOr (//) and Defined lowering
#
# DefinedOr(lhs, rhs) :T — returns lhs when lhs is DEFINED, rhs otherwise.
# This is a definedness check, NOT a truthiness check (unlike || which uses
# icmp-ne-0). The definedness predicate is: is the value NOT Undef?
#
# Lowering strategy (static-dispatch on LHS representation):
#
#   LHS repr = Undef (always undef, static):
#     The LHS is an Undef-typed value. Its defined bit was set to false via
#     the alloca+store+load idiom in _lower_constant. We read it and branch:
#       br i1 %defined_bit, %dor.defined, %dor.undef
#     The phi in the end block merges LHS payload (defined path) or RHS value
#     (undef path). Since the defined bit is always false for Undef-typed LHS,
#     the optimizer is FREE to eliminate the dead defined path — but the IR
#     must be well-formed (both phi arms present) for lli to accept it.
#
#   LHS repr = Int / Num / Str / Bool (always defined, static):
#     A non-Undef typed value is always defined. The definedness check is a
#     static i1 true. We still emit the branch+phi structure for structural
#     uniformity, but the branch on i1 true always takes the defined path.
#     The optimizer eliminates the dead undef path.
#
# The result representation is that of the DefinedOr node itself (typically
# the RHS repr, e.g. Int when both operands are Int).
#
# RUNTIME-undef guarantee: the defined bit for Undef-typed LHS is emitted via
# alloca+store+load in _lower_constant, making it a runtime-opaque i1 that
# LLVM cannot constant-fold without mem2reg. See U3 test for verification.
# ---------------------------------------------------------------------------

sub _lower_defined_or {
    my ($self, $node) = @_;

    my $repr = $node->representation;
    if (defined $repr && $repr eq 'Scalar') {
        die "GAP: DefinedOr with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    my $inputs   = $node->inputs;
    my $lhs_node = $inputs->[0];
    my $rhs_node = $inputs->[1];

    my $lhs_repr = _require_repr($lhs_node, 'DefinedOr.lhs');

    # Lower the LHS. For Undef-typed LHS, this produces the defined bit (i1).
    # For Int/Num/Str/Bool-typed LHS, this produces the payload value.
    my $lhs_ref    = $self->lower_value($lhs_node);
    my $entry_label = $self->_current_block_label;

    # Get the definedness condition (i1).
    my $defined_cond;
    if ($lhs_repr eq 'Undef') {
        # The defined bit was set by _lower_constant to the alloca/load result.
        # lhs_ref IS the defined bit (i1 false for Constant(undef)).
        $defined_cond = $lhs_ref;
    }
    else {
        # Non-Undef LHS: always defined. Emit i1 true as a compile-time constant.
        # The optimizer will take the defined branch always, but the IR is
        # well-formed (both phi arms present).
        my $always_true = $self->_fresh;
        $self->_emit("  $always_true = add i1 0, 1              ; DefinedOr: non-Undef LHS always defined (i1 true)");
        $defined_cond = $always_true;
    }

    # Allocate block labels.
    my $undef_label = $self->_fresh_label('dor.undef.');
    my $end_label   = $self->_fresh_label('dor.end.');

    # Conditional branch: defined -> end with lhs; undef -> rhs block.
    $self->_set_terminator("  br i1 $defined_cond, label %$end_label, label %$undef_label  ; DefinedOr: definedness branch");

    # RHS block: evaluate the RHS, then jump to end.
    $self->_new_block($undef_label);
    my $rhs_ref       = $self->lower_value($rhs_node);
    my $undef_end_label = $self->_current_block_label;
    $self->_set_terminator("  br label %$end_label  ; DefinedOr: undef path falls through");

    # End block: phi merges lhs value (defined path) and rhs value (undef path).
    $self->_new_block($end_label);
    my $result = $self->_fresh;
    my $llvm_type = _repr_to_llvm_type($repr // 'Int');

    # LHS payload for the phi: when LHS is Undef-typed, use the recorded payload
    # (i64 0 for Constant(undef)) or a zero for the type. When LHS is a typed value,
    # lhs_ref IS the payload.
    my $lhs_phi_val;
    if ($lhs_repr eq 'Undef') {
        # The payload was recorded by _lower_constant in _undef_payload.
        $lhs_phi_val = $self->{_undef_payload}{ $lhs_node->id };
        unless (defined $lhs_phi_val) {
            # Fallback: emit a zero of the result type if no payload was recorded.
            $lhs_phi_val = $self->_fresh;
            if ($llvm_type eq 'double') {
                $self->_emit("  $lhs_phi_val = fadd double 0.0, 0.0  ; DefinedOr: undef LHS payload fallback (Num)");
            }
            else {
                $self->_emit("  $lhs_phi_val = add $llvm_type 0, 0  ; DefinedOr: undef LHS payload fallback");
            }
        }
    }
    else {
        $lhs_phi_val = $lhs_ref;
    }

    $self->_emit("  $result = phi $llvm_type [ $lhs_phi_val, %$entry_label ], [ $rhs_ref, %$undef_end_label ]  ; DefinedOr: phi");

    $self->{cache}{$node->id} = $result;
    return $result;
}

# _lower_defined: lower a Defined(operand) -> i1 definedness predicate.
#
# defined($x) is true iff $x is NOT Undef.
# Static dispatch on the operand's representation:
#   Undef repr: always false (the operand IS undef). Returns the stored defined bit.
#   Other repr: always true (Int/Num/Str/Bool are always defined). Returns i1 1.
sub _lower_defined {
    my ($self, $node) = @_;

    my $inputs  = $node->inputs;
    my $operand = $inputs->[0];
    my $op_repr = _require_repr($operand, 'Defined.operand');

    # Lower the operand to get its value ref (or defined bit for Undef-typed).
    my $op_ref = $self->lower_value($operand);

    if ($op_repr eq 'Undef') {
        # op_ref IS the defined bit (i1) from _lower_constant's alloca/load.
        $self->{cache}{$node->id} = $op_ref;
        return $op_ref;
    }
    else {
        # Non-Undef operand: always defined. Return i1 true.
        my $true_ref = $self->_fresh;
        $self->_emit("  $true_ref = add i1 0, 1  ; Defined($op_repr): always defined, returns i1 true");
        $self->{cache}{$node->id} = $true_ref;
        return $true_ref;
    }
}

# ---------------------------------------------------------------------------
# CFG node lowering: If, Proj, Region, Phi, Loop
#
# These implement control flow for if/else, while, foreach, and postfix forms.
#
# The hand-authored ir-blocks use these nodes directly. The emitter processes
# them during the control chain pre-pass AND when referenced from the value
# subgraph. Only value-producing nodes (Phi, Region's phi result) return a
# meaningful SSA ref; control-only nodes (If, Proj, Loop) return undef or a
# sentinel that should not be used as a value operand.
# ---------------------------------------------------------------------------

# _lower_if: emit the conditional branch for an If node.
# If nodes are control-flow-only; they do not produce a value themselves.
# Called during process_control_node for the control chain.
#
# inputs[0] = control predecessor (already lowered or unused here)
# inputs[1] = condition (a Bool/i1 value)
#
# After _lower_if emits the branch, the caller (_lower_if_region_pair or
# process_control_node) must set up the then/else/merge blocks.
sub _lower_if {
    my ($self, $node) = @_;

    # If is control-only; its "value" is a sentinel.
    # The actual branch emission is driven by process_control_node.
    # Here we just return a sentinel if called from lower_value context
    # (should not normally happen in well-authored ir-blocks).
    return undef;
}

# _lower_region: process the merge point.
# Region merges control from multiple predecessor blocks.
# Returns undef (control-only). Value merging happens via Phi nodes.
sub _lower_region {
    my ($self, $node) = @_;
    return undef;
}

# _lower_proj: Proj selects one output from a multi-output node (If, Loop).
# Returns undef (control-only).
sub _lower_proj {
    my ($self, $node) = @_;
    return undef;
}

# _lower_phi: emit a phi instruction merging values from predecessor blocks.
#
# The Phi node carries:
#   $phi->region : the Region merge node
#   $phi->inputs : the incoming values (one per predecessor)
#
# The emitter uses $phi->inputs and the already-determined predecessor block
# labels to emit:
#   %result = phi i64 [ %val_from_pred0, %pred0_label ], [ %val_from_pred1, %pred1_label ]
#
# ADVERSARIAL GUARD: a Phi with missing or undef incoming values must die
# loudly — empty or partially-undef inputs produce undef-poisoned phi IR
# that lli would silently miscompile.
sub _lower_phi {
    my ($self, $node) = @_;

    my $inputs = $node->inputs;
    unless (defined $inputs && scalar @$inputs > 0) {
        die "LLVM backend: Phi node has no incoming values (empty inputs) — "
          . "a missing predecessor edge would produce undef-poisoned phi IR; "
          . "every Phi must have at least one incoming value per predecessor block";
    }

    # Extended guard: reject any undef slot in the inputs array (H4/H5).
    # An undef incoming value means a predecessor edge was not wired — the
    # resulting phi instruction would reference an undefined SSA name, causing
    # a verifier error or silent miscompile in lli.
    for my $i (0 .. $#$inputs) {
        unless (defined $inputs->[$i]) {
            die "LLVM backend: Phi node (id=" . $node->id . ") has undef incoming "
              . "value at slot $i — every phi incoming slot must be a valid node "
              . "(missing predecessor wire); this would produce invalid phi IR";
        }
    }

    # The phi instruction has already been emitted by the if/loop lowering
    # machinery which drives block construction. This path handles Phi nodes
    # referenced directly from lower_value (the data-flow path). Return the
    # cached result if already emitted.
    if (exists $self->{cache}{ $node->id }) {
        return $self->{cache}{ $node->id };
    }

    die "LLVM backend: Phi node encountered in lower_value before its enclosing "
      . "if/loop structure was processed; author the ir-block so Region/If/Loop "
      . "appear in the control chain before Phi values are read";
}

# ---------------------------------------------------------------------------
# _repr_to_llvm_type($repr) -> LLVM type string
# ---------------------------------------------------------------------------
sub _repr_to_llvm_type {
    my ($repr) = @_;
    $repr //= 'Int';
    return 'i64'    if $repr eq 'Int';
    return 'double' if $repr eq 'Num';
    return 'i1'     if $repr eq 'Bool';
    return 'i8*'    if $repr eq 'Str';
    return 'i1'     if $repr eq 'Undef';   # Undef is represented as its defined-bit (i1 false)
    die "LLVM backend: no LLVM type for representation '$repr'";
}

# ---------------------------------------------------------------------------
# process_control_node: called during the control-chain pre-pass for each
# side-effect node in forward order. Processes VarDecl, Assign, CompoundAssign,
# If (with its Region pair), and Loop (with its exit Region).
# ---------------------------------------------------------------------------
sub process_control_node {
    my ($self, $node) = @_;
    my $op = $node->operation;
    if ($op eq 'VarDecl' || $op eq 'Assign' || $op eq 'CompoundAssign') {
        $self->lower_value($node);
    }
    elsif ($op eq 'If') {
        $self->_process_if_node($node);
    }
    elsif ($op eq 'Loop') {
        $self->_process_loop_node($node);
    }
    elsif ($op eq 'Call') {
        # Call(dispatch_kind='method') is the canonical form of MethodCall.
        # Side-effecting calls in the control chain must be lowered here so
        # their field mutations are emitted before subsequent reads.
        $self->lower_value($node);
    }
    # Other ops in the control chain (Return, Unwind, Region, Proj, Phi, etc.)
    # are either handled by their driving structure or ignored here.
}

# _process_if_node: forward to the concrete subclass.
# The base Context class does not implement if/else lowering directly;
# all if/else placement is performed by ElaboratedContext (see below),
# which uses the dominator-tree scoped value map to place phis at merge blocks.
sub _process_if_node {
    my ($self, $if_node) = @_;
    die ref($self) . ': _process_if_node called on base Context — use ElaboratedContext';
}

# _process_branch_from_if: lower the body of one If branch (then=0, else=1).
# Walks the consumers of the Proj node for this branch, executing any
# VarDecl/Assign side-effect nodes and leaving the current block at the
# end of the branch.
sub _process_branch_from_if {
    my ($self, $if_node, $branch_idx, $merge_label) = @_;

    # Find the Proj node for this branch: it is a consumer of the If node
    # with index == branch_idx.
    my $proj = _find_proj_consumer($if_node, $branch_idx);
    unless (defined $proj) {
        # No body for this branch — just jump to merge.
        $self->_set_terminator("  br label %$merge_label  ; if branch $branch_idx: no body, jump to merge");
        return;
    }

    # Walk consumers of the Proj node that are side-effect nodes (VarDecl,
    # Assign, CompoundAssign) or nested If/Loop nodes. These form the body
    # of the branch. Dispatch each through process_control_node so nested
    # If nodes are handled recursively via _process_if_node.
    my @body_nodes = _collect_branch_body($proj);
    for my $body_node (@body_nodes) {
        $self->process_control_node($body_node);
    }

    $self->_set_terminator("  br label %$merge_label  ; if branch $branch_idx: jump to merge");
}

# _wire_region_phis: find Phi nodes that are consumers of the Region node
# and ensure their results are cached under their node ids.
sub _wire_region_phis {
    my ($self, $region, $then_label, $else_label) = @_;

    my $consumers = $region->consumers // [];
    for my $phi_node (@$consumers) {
        next unless defined $phi_node && ref($phi_node);
        next unless $phi_node->can('operation') && $phi_node->operation eq 'Phi';

        # Skip if already cached.
        next if exists $self->{cache}{ $phi_node->id };

        my $inputs = $phi_node->inputs;
        unless (defined $inputs && scalar @$inputs >= 2) {
            die "LLVM backend: Phi node (id=" . $phi_node->id . ") attached to Region "
              . "has fewer than 2 incoming values — missing predecessor edge";
        }

        # Lower both incoming values (they should already be in cache from
        # branch processing above).
        my $then_val = $self->lower_value($inputs->[0]);
        my $else_val = $self->lower_value($inputs->[1]);

        my $repr = _require_repr($phi_node, 'Region.Phi');
        my $llvm_type = _repr_to_llvm_type($repr);
        my $result    = $self->_fresh;
        $self->_emit("  $result = phi $llvm_type [ $then_val, %$then_label ], [ $else_val, %$else_label ]  ; Region phi");
        $self->{cache}{ $phi_node->id } = $result;
    }
}

# _process_loop_node: lower a Loop node (while/foreach/postfix-while).
#
# Control flow:
#   preheader block (current): ... br label %loop.header
#   loop.header: phi for loop-carried values; test condition; br to body or exit
#   loop.body: execute body; update loop vars; br label %loop.header  (back-edge)
#   loop.exit: phi for exit values (loop_var state on exit)
#
# The Loop node carries:
#   inputs[0] = entry_ctrl (the control predecessor — already processed)
#   inputs[1] = backedge_ctrl (wired after the body — set by set_backedge_ctrl)
#   $loop->region = exit Region
#
# The loop is structured as a counted loop when the body is a simple range.
# This method handles the general case (condition test in the header).
sub _process_loop_node {
    my ($self, $loop_node) = @_;

    my $preheader_label = $self->_current_block_label;
    my $header_label    = $self->_fresh_label('loop.header.');
    my $body_label      = $self->_fresh_label('loop.body.');
    my $exit_label      = $self->_fresh_label('loop.exit.');

    # Jump from preheader to the loop header.
    $self->_set_terminator("  br label %$header_label  ; Loop: enter header");

    # ---- Lower init values in the preheader block ----
    # Each loop phi's inputs[0] is the initial value. Lower it NOW (while still
    # in the preheader block) so the SSA definition of the init value precedes
    # the phi instruction in the header block. If lowered after opening the
    # header, the init value's definition would appear after the phi that
    # references it — invalid LLVM IR (forward reference not allowed in phi).
    my @loop_phis = _collect_loop_phis($loop_node);

    my @phi_records;    # [ { node, phi_ref, init_ref } ]

    for my $phi_node (@loop_phis) {
        my $inputs = $phi_node->inputs;
        unless (defined $inputs && scalar @$inputs >= 1) {
            die "LLVM backend: Loop Phi (id=" . $phi_node->id . ") has no incoming values";
        }
        # Lower init value in the preheader block (current block before _new_block).
        my $init_ref = $self->lower_value($inputs->[0]);
        my $phi_ref  = $self->_fresh;
        push @phi_records, {
            node     => $phi_node,
            phi_ref  => $phi_ref,
            init_ref => $init_ref,
        };
    }

    # ---- Loop header ----
    # Open the header block. Phi instructions for loop-carried values are
    # prepended to this block after the body is lowered (two-pass approach:
    # we need the backedge SSA refs from the body to complete each phi).
    $self->_new_block($header_label);

    # Cache the phi refs so body lowering can reference them via lower_value.
    for my $rec (@phi_records) {
        $self->{cache}{ $rec->{node}->id } = $rec->{phi_ref};
        _update_var_table_for_phi($self, $rec->{node}, $rec->{phi_ref});
    }

    # Emit the loop condition. The condition is drawn from consumers of the
    # Loop header: a Proj 0 consumer carries the body Proj, Proj 1 carries
    # the exit Proj.
    my $cond_val_ref = $self->_lower_loop_condition($loop_node);

    # Conditional branch: condition true -> body; false -> exit.
    $self->_set_terminator("  br i1 $cond_val_ref, label %$body_label, label %$exit_label  ; Loop: header branch");

    # ---- Loop body ----
    $self->_new_block($body_label);

    # Save pre-body var_table for collecting backedge updates.
    my %pre_body_vars = %{ $self->{var_table} };

    # Process the body: VarDecl/Assign nodes reachable from the body Proj.
    $self->_process_loop_body($loop_node, $header_label);
    my $body_end_label = $self->_current_block_label;

    # Collect the backedge values for each phi.
    my %body_vars = %{ $self->{var_table} };

    # Back-edge branch back to header.
    $self->_set_terminator("  br label %$header_label  ; Loop: back-edge");

    # ---- NOW emit the phi instructions at the TOP of the header block ----
    # We insert them at index 0 of the header block's insts.
    my $header_block = $self->{blocks}[ $self->_find_block_idx($header_label) ];
    my @phi_lines;
    for my $rec (@phi_records) {
        my $phi_node = $rec->{node};
        my $phi_ref  = $rec->{phi_ref};
        my $init_ref = $rec->{init_ref};

        # Backedge value: the updated value of the variable after the body.
        # Look it up from body_vars via the VarDecl id that this phi tracks.
        my $backedge_ref = $self->_find_phi_backedge_value($phi_node, \%body_vars, $phi_ref);

        my $repr      = _require_repr($phi_node, 'Loop.Phi');
        my $llvm_type = _repr_to_llvm_type($repr);
        my $phi_line  = "  $phi_ref = phi $llvm_type [ $init_ref, %$preheader_label ], [ $backedge_ref, %$body_end_label ]  ; Loop phi";
        push @phi_lines, $phi_line;
    }
    # Prepend phi lines to the header block.
    unshift $header_block->{insts}->@*, @phi_lines;

    # ---- Exit block ----
    $self->_new_block($exit_label);

    # Wire exit Region phis.
    my $exit_region = $loop_node->region;
    if (defined $exit_region) {
        $self->_wire_region_phis($exit_region, $body_end_label, $preheader_label);
    }

    # Update var_table with the final values (from exit path = body_vars at
    # the point of the exit branch, which is the last state of the header
    # phi values since the condition was false, meaning the body did NOT run
    # one more time. For loop-exit values, we use the phi_ref from the header
    # (the value at the top of the header when the condition was checked).
    # This is correct: loop exits when condition is false, which is tested
    # BEFORE the body runs, so the exit value is the phi at the header.
    for my $rec (@phi_records) {
        my $phi_node = $rec->{node};
        my $phi_ref  = $rec->{phi_ref};
        _update_var_table_for_phi($self, $phi_node, $phi_ref);
    }
}

# _lower_loop_condition: find and lower the condition value for a loop header.
#
# Selection strategy (structural, not heuristic):
#
#   1. Find a comparison node whose control_in is the Loop node itself. This
#      is the canonical structural link authored by ir-block builders to mark
#      the condition as belonging to the header branch (not the body). Return
#      the first such node found (only one should be wired this way).
#
#   2. Fallback: walk consumers of each loop-header Phi and return the first
#      icmp-predicate node found. This covers older ir-block graphs that do
#      not wire control_in on the condition. Iterate in sorted-id order for
#      determinism (CLAUDE.md: sort all hash iteration).
#
# The structural strategy is preferred because the fallback is ambiguous when
# the loop body contains its own comparisons that also consume the induction
# phi — a first-icmp heuristic would pick the body comparison instead of the
# header condition (H3 bug).
sub _lower_loop_condition {
    my ($self, $loop_node) = @_;

    # Strategy 1: structural — look for a comparison whose control_in is
    # the loop node. This link is set by the ir-block author via
    # $cond->set_control_in($loop) to mark the header condition explicitly.
    my $loop_consumers = $loop_node->consumers // [];
    for my $c (@$loop_consumers) {
        next unless defined $c && $c->can('operation');
        next unless exists $ICMP_PREDICATE{ $c->operation };
        # This comparison has the loop as its control predecessor — it is the
        # header branch condition, not a body comparison.
        return $self->lower_value($c);
    }

    # Strategy 2: fallback — first icmp consumer of any loop phi.
    # Collect all phi-consumer icmps, sort by node id for determinism.
    my @candidates;
    for my $phi_node (_collect_loop_phis($loop_node)) {
        my $consumers = $phi_node->consumers // [];
        for my $consumer (@$consumers) {
            next unless defined $consumer && $consumer->can('operation');
            next unless exists $ICMP_PREDICATE{ $consumer->operation };
            push @candidates, $consumer;
        }
    }
    if (@candidates) {
        # Sort by id for deterministic selection (earliest-constructed condition
        # is the induction-variable test in well-structured loops).
        my ($first) = sort { $a->id cmp $b->id } @candidates;
        return $self->lower_value($first);
    }

    die "LLVM backend: could not find loop condition — the loop ir-block must "
      . "express the condition as a comparison (NumGt/NumLt/etc.) that "
      . "either has control_in wired to the Loop node (structural) or "
      . "consumes a loop-header Phi (the induction variable)";
}

# _process_loop_body: lower the body of a loop (the statements in the body Proj).
sub _process_loop_body {
    my ($self, $loop_node, $header_label) = @_;

    # Find body nodes: consumers of the body Proj (index 0).
    my $body_proj = _find_proj_consumer($loop_node, 0);
    return unless defined $body_proj;

    my @body_nodes = _collect_branch_body($body_proj);
    for my $body_node (@body_nodes) {
        my $op = $body_node->can('operation') ? $body_node->operation : '';
        if ($op eq 'If' || $op eq 'Loop') {
            # Dispatch control-flow nodes through process_control_node so that
            # nested If/Loop structures are handled by _process_if_node /
            # _process_loop_node, which emit basic blocks and phi instructions.
            # lower_value(If) only returns undef without processing branches.
            $self->process_control_node($body_node);
        }
        else {
            $self->lower_value($body_node);
        }
    }
}

# _collect_loop_phis: find all Phi nodes whose region is this Loop node.
sub _collect_loop_phis {
    my ($loop_node) = @_;
    my @phis;
    my $consumers = $loop_node->consumers // [];
    for my $c (@$consumers) {
        next unless defined $c && $c->can('operation');
        if ($c->operation eq 'Phi') {
            # Check that this Phi's region IS the loop node.
            my $r = $c->region;
            if (defined $r && $r->id eq $loop_node->id) {
                push @phis, $c;
            }
        }
    }
    return @phis;
}

# _find_phi_backedge_value: find the backedge value for a Loop phi node.
# The backedge value is the SSA ref of the updated variable at the end of
# the loop body — i.e. the value in var_table after the body ran.
#
# Primary strategy: read inputs[1] of the Phi, which is the explicitly wired
# backedge value (set via set_backedge after the body is constructed). Lower
# it to get the SSA ref produced by the body update.
#
# Fallback strategy: if inputs[1] is absent, look in body_vars for the VarDecl
# that this phi tracks (via _phi_to_vd). Iterate in sorted key order so the
# result is deterministic across Perl hash-iteration orders.
sub _find_phi_backedge_value {
    my ($self, $phi_node, $body_vars, $fallback_ref) = @_;

    # Primary: use inputs[1] of the phi (the explicitly wired backedge).
    my $inputs = $phi_node->inputs;
    if (defined $inputs && scalar @$inputs >= 2 && defined $inputs->[1]) {
        my $backedge_ref = $self->lower_value($inputs->[1]);
        return $backedge_ref if defined $backedge_ref;
    }

    # Fallback: look in body_vars for the VarDecl this phi tracks.
    # Sort keys for deterministic iteration (CLAUDE.md: sort all hash iteration).
    for my $vd_id (sort keys %$body_vars) {
        my $body_ref = $body_vars->{$vd_id};
        # Skip if the body value is unchanged from the phi_ref (no update).
        next if $body_ref eq $fallback_ref;
        # Check if this phi is known to track this vd_id (set by _update_var_table_for_phi).
        if (defined $self->{_phi_to_vd}{ $phi_node->id }
            && $self->{_phi_to_vd}{ $phi_node->id } eq $vd_id) {
            return $body_ref;
        }
    }

    return $fallback_ref;
}

# _update_var_table_for_phi: find the VarDecl that a Loop phi tracks and
# update var_table to point to the phi's SSA ref.
sub _update_var_table_for_phi {
    my ($self, $phi_node, $phi_ref) = @_;

    # The phi's inputs[0] is the initial value. If inputs[0] is a VarDecl,
    # or if inputs[0]'s producer is a VarDecl, we can find the vd_id.
    my $inputs = $phi_node->inputs;
    return unless defined $inputs && @$inputs;

    my $init_node = $inputs->[0];
    return unless defined $init_node;

    # Walk back: if init_node is a VarDecl, use its id.
    if ($init_node->operation eq 'VarDecl') {
        my $vd_id = $init_node->id;
        $self->{var_table}{$vd_id} = $phi_ref;
        $self->{_phi_to_vd}{ $phi_node->id } = $vd_id;
        return;
    }
    # If init_node is a PadAccess, its inputs[0] is the VarDecl.
    if ($init_node->operation eq 'PadAccess') {
        my $vd = $init_node->inputs->[0];
        if (defined $vd && $vd->operation eq 'VarDecl') {
            my $vd_id = $vd->id;
            $self->{var_table}{$vd_id} = $phi_ref;
            $self->{_phi_to_vd}{ $phi_node->id } = $vd_id;
            return;
        }
    }
}

# _find_proj_consumer($node, $idx) -> Proj node with index == $idx, or undef.
sub _find_proj_consumer {
    my ($node, $idx) = @_;
    my $consumers = $node->consumers // [];
    for my $c (@$consumers) {
        next unless defined $c && $c->can('operation');
        next unless $c->operation eq 'Proj';
        return $c if $c->index == $idx;
    }
    return undef;
}

# _collect_branch_body($proj_node) -> ordered list of body side-effect nodes.
# Walks consumers of the Proj node and collects VarDecl/Assign/CompoundAssign
# nodes in topological order (simplified: consumers of consumers).
sub _collect_branch_body {
    my ($proj_node) = @_;
    my @body;
    my %visited;
    _collect_body_recursive($proj_node, \%visited, \@body);
    return @body;
}

sub _collect_body_recursive {
    my ($node, $visited, $body) = @_;
    return unless defined $node;
    my $id = $node->id;
    return if $visited->{$id}++;

    my $op = $node->can('operation') ? $node->operation : '';

    # Side-effect and control-flow nodes go into the body.
    # If/Loop nodes in a branch are processed via process_control_node,
    # which dispatches to _process_if_node/_process_loop_node for nested
    # control flow.
    if ($op eq 'VarDecl' || $op eq 'Assign' || $op eq 'CompoundAssign'
        || $op eq 'If' || $op eq 'Loop') {
        push @$body, $node;
        # Do NOT recurse further for If/Loop — their branch bodies are
        # discovered from their own Proj consumers by _process_if_node.
        return if $op eq 'If' || $op eq 'Loop';
    }

    # Recurse into consumers that have this node as a control predecessor.
    my $consumers = $node->consumers // [];
    for my $c (@$consumers) {
        next unless defined $c;
        _collect_body_recursive($c, $visited, $body);
    }
}

# _find_block_idx($label) -> index in $self->{blocks} for the given label.
sub _find_block_idx {
    my ($self, $label) = @_;
    my $blocks = $self->{blocks};
    for my $i (0 .. $#$blocks) {
        return $i if $blocks->[$i]{label} eq $label;
    }
    die "LLVM backend: internal error — block '$label' not found";
}

# ===========================================================================
# G4 Array/Hash aggregate lowering
# ===========================================================================
#
# Array representation: %Array = { i64 len, i64 cap, %Slot* elems }
# Hash representation:  %Hash  = { i64 count, i64 cap, %HashEntry* entries }
# Slot type:            %Slot  = { i1 defined, i64 payload }
# HashEntry type:       %HashEntry = { i8* key_ptr, i64 key_len, i32 key_enc,
#                                      i1 val_defined, i64 val_payload }
# Ref types:  ArrayRef = bitcast %Array* to i8* (pointer, no additional tag needed)
#             HashRef  = bitcast %Hash* to i8*
#
# All allocation uses libc malloc — NOT libperl AV*/HV*. The slot model is
# the tagged-scalar {i1,i64} from L3 (SPIKE confirmed: OOB -> defined=false
# = undef by construction; plain-i64 rejected because INT_MIN is a valid
# payload with no safe sentinel, as L3's analysis showed).
#
# Hash lookup: linear scan with memcmp on Str keys. Sufficient for the small
# literal hashes in the R-corpus. Order-normalized for determinism (keys are
# stored in literal order; the R3/R5/R7 corpus cases only read, not iterate).
# ===========================================================================

# _lower_array_ref: canonical ref-producing array constructor.
# inputs = [elem0, elem1, ...]. Returns i8* (ArrayRef repr).
# The underlying %Array* is stored in _arr_table keyed by node id so that
# Length/Subscript consumers can get the struct pointer without a bitcast.
sub _lower_array_ref {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    my $inputs = $node->inputs;
    my $n      = scalar @$inputs;

    # Allocate slot buffer: n * sizeof(%Slot).
    my $slot_bytes = $n * 16;
    my $slot_buf = $self->_fresh;
    $self->_emit("  $slot_buf = call i8* \@malloc(i64 $slot_bytes)  ; ArrayRef: alloc $n slots");
    my $slots = $self->_fresh;
    $self->_emit("  $slots = bitcast i8* $slot_buf to %Slot*  ; ArrayRef: slot array ptr");

    # Store each element as a defined slot {i1=true, i64=value}.
    for my $i (0 .. $n - 1) {
        my $elem_ref = $self->lower_value($inputs->[$i]);
        my $slot_def = $self->_fresh;
        my $slot_pay = $self->_fresh;
        $self->_emit("  $slot_def = getelementptr inbounds %Slot, %Slot* $slots, i64 $i, i32 0  ; ArrayRef: slot[$i] defined ptr");
        $self->_emit("  $slot_pay = getelementptr inbounds %Slot, %Slot* $slots, i64 $i, i32 1  ; ArrayRef: slot[$i] payload ptr");
        $self->_emit("  store i1 true, i1* $slot_def  ; ArrayRef: slot[$i] defined=true");
        my $elem_i64;
        my $elem_repr = $inputs->[$i]->representation // '';
        if ($elem_repr eq 'ArrayRef' || $elem_repr eq 'HashRef') {
            $elem_i64 = $self->_fresh;
            $self->_emit("  $elem_i64 = ptrtoint i8* $elem_ref to i64  ; ArrayRef: ptr elem[$i] -> i64");
        }
        else {
            $elem_i64 = $elem_ref;
        }
        $self->_emit("  store i64 $elem_i64, i64* $slot_pay  ; ArrayRef: slot[$i] payload=$elem_i64");
    }

    # Allocate Array header: { i64 len, i64 cap, %Slot* elems } = 24 bytes.
    my $arr_buf = $self->_fresh;
    $self->_emit("  $arr_buf = call i8* \@malloc(i64 24)  ; ArrayRef: alloc Array header");
    my $arr = $self->_fresh;
    $self->_emit("  $arr = bitcast i8* $arr_buf to %Array*  ; ArrayRef: Array ptr");
    my $len_ptr = $self->_fresh;
    my $cap_ptr = $self->_fresh;
    my $elm_ptr = $self->_fresh;
    $self->_emit("  $len_ptr = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 0  ; ArrayRef: len ptr");
    $self->_emit("  $cap_ptr = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 1  ; ArrayRef: cap ptr");
    $self->_emit("  $elm_ptr = getelementptr inbounds %Array, %Array* $arr, i32 0, i32 2  ; ArrayRef: elems ptr");
    $self->_emit("  store i64 $n, i64* $len_ptr  ; ArrayRef: len=$n");
    $self->_emit("  store i64 $n, i64* $cap_ptr  ; ArrayRef: cap=$n");
    $self->_emit("  store %Slot* $slots, %Slot** $elm_ptr  ; ArrayRef: store slots ptr");

    # The canonical ref result is the i8* (Array* bitcast).
    my $ref = $self->_fresh;
    $self->_emit("  $ref = bitcast %Array* $arr to i8*  ; ArrayRef: Array* -> i8* ref");

    $self->{cache}{ $node->id } = $ref;
    # Track Array* in _arr_table for consumers (Length, Subscript) that need the struct.
    $self->{_arr_table}{ $node->id } = $arr;
    return $ref;
}

# _lower_hash_ref: canonical ref-producing hash constructor.
# inputs = [key0, val0, key1, val1, ...]. Returns i8* (HashRef repr).
# The underlying %Hash* is stored in _hash_table keyed by node id.
sub _lower_hash_ref {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;
    $self->{_need_memcmp}          = 1;

    my $inputs = $node->inputs;
    my $npairs = scalar(@$inputs) / 2;

    my $entry_bytes = $npairs * 48;
    my $ent_buf = $self->_fresh;
    $self->_emit("  $ent_buf = call i8* \@malloc(i64 $entry_bytes)  ; HashRef: alloc $npairs entries");
    my $ents = $self->_fresh;
    $self->_emit("  $ents = bitcast i8* $ent_buf to %HashEntry*  ; HashRef: entry array ptr");

    for my $i (0 .. $npairs - 1) {
        my $key_ref = $self->lower_value($inputs->[ $i * 2     ]);
        my $val_ref = $self->lower_value($inputs->[ $i * 2 + 1 ]);
        # The stored key length is later memcmp'd at read/update time; a 0-length
        # key would make every lookup match this entry. Die loudly on an untracked
        # length rather than default to 0 (matches the I-C loud-GAP contract).
        my $key_len = $self->_str_len_for($key_ref)
            // die "GAP: HashRef key (ref=$key_ref) has no tracked length — "
                 . "stored key length 0 would make any lookup match this entry.";

        my $e_kp = $self->_fresh;
        my $e_kl = $self->_fresh;
        my $e_ke = $self->_fresh;
        my $e_vd = $self->_fresh;
        my $e_vp = $self->_fresh;
        $self->_emit("  $e_kp = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 0  ; HashRef: entry[$i] key_ptr ptr");
        $self->_emit("  $e_kl = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 1  ; HashRef: entry[$i] key_len ptr");
        $self->_emit("  $e_ke = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 2  ; HashRef: entry[$i] key_enc ptr");
        $self->_emit("  $e_vd = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 3  ; HashRef: entry[$i] val_def ptr");
        $self->_emit("  $e_vp = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i, i32 4  ; HashRef: entry[$i] val_pay ptr");
        $self->_emit("  store i8* $key_ref, i8** $e_kp  ; HashRef: key ptr");
        $self->_emit("  store i64 $key_len, i64* $e_kl  ; HashRef: key len=$key_len");
        $self->_emit("  store i32 0, i32* $e_ke          ; HashRef: enc=0 (ASCII)");
        $self->_emit("  store i1 true, i1* $e_vd         ; HashRef: defined=true");
        # If the value is a pointer-repr (ArrayRef/HashRef), ptrtoint before
        # storing into the i64 payload slot — mirrors _lower_array_ref 3164-3172.
        my $val_node  = $inputs->[ $i * 2 + 1 ];
        my $val_repr  = $val_node->representation // '';
        my $val_i64;
        if ($val_repr eq 'ArrayRef' || $val_repr eq 'HashRef') {
            $val_i64 = $self->_fresh;
            $self->_emit("  $val_i64 = ptrtoint i8* $val_ref to i64  ; HashRef: ptr value[$i] -> i64");
        }
        else {
            $val_i64 = $val_ref;
        }
        $self->_emit("  store i64 $val_i64, i64* $e_vp   ; HashRef: value");
    }

    my $hash_buf = $self->_fresh;
    $self->_emit("  $hash_buf = call i8* \@malloc(i64 24)  ; HashRef: alloc Hash header");
    my $hash = $self->_fresh;
    $self->_emit("  $hash = bitcast i8* $hash_buf to %Hash*  ; HashRef: Hash ptr");
    my $cnt_ptr = $self->_fresh;
    my $cap_ptr = $self->_fresh;
    my $ent_ptr = $self->_fresh;
    $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 0  ; HashRef: count ptr");
    $self->_emit("  $cap_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 1  ; HashRef: cap ptr");
    $self->_emit("  $ent_ptr = getelementptr inbounds %Hash, %Hash* $hash, i32 0, i32 2  ; HashRef: entries ptr");
    $self->_emit("  store i64 $npairs, i64* $cnt_ptr  ; HashRef: count=$npairs");
    $self->_emit("  store i64 $npairs, i64* $cap_ptr  ; HashRef: cap=$npairs");
    $self->_emit("  store %HashEntry* $ents, %HashEntry** $ent_ptr  ; HashRef: store entries ptr");

    # The canonical ref result is the i8* (Hash* bitcast).
    my $ref = $self->_fresh;
    $self->_emit("  $ref = bitcast %Hash* $hash to i8*  ; HashRef: Hash* -> i8* ref");

    $self->{cache}{ $node->id } = $ref;
    # Track Hash* in _hash_table for consumers (Subscript, HashWrite) that need the struct.
    $self->{_hash_table}{ $node->id } = $hash;
    return $ref;
}

# _lower_length: repr-aware length of an Array or Str operand.
# Array repr: load the len field from the %Array struct (array element count).
# Str repr: load the len field from the %StrPair struct (byte length).
# Both return i64 (repr=Int).
sub _lower_length {
    my ($self, $node) = @_;

    my $operand = $node->inputs->[0];
    my $op_repr = _require_repr($operand, 'Length.operand');

    if ($op_repr eq 'Array' || $op_repr eq 'ArrayRef') {
        $self->{_need_aggregate_types} = 1;
        # Ensure the operand is lowered (populates _arr_table for ArrayRef nodes).
        $self->lower_value($operand);
        my $arr_ref = $self->{_arr_table}{ $operand->id };
        unless (defined $arr_ref) {
            # ArrayRef emitted as i8*: bitcast to Array* to read the struct.
            my $i8 = $self->{cache}{ $operand->id };
            $arr_ref = $self->_fresh;
            $self->_emit("  $arr_ref = bitcast i8* $i8 to %Array*  ; Length(ArrayRef): i8* -> Array*");
            $self->{_arr_table}{ $operand->id } = $arr_ref;
        }
        my $len_ptr = $self->_fresh;
        my $len     = $self->_fresh;
        $self->_emit("  $len_ptr = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 0  ; Length(Array): len ptr");
        $self->_emit("  $len = load i64, i64* $len_ptr  ; Length(Array): load len");
        $self->{cache}{ $node->id } = $len;
        return $len;
    }
    elsif ($op_repr eq 'Str') {
        # lower_value for Str returns i8* (ptr to NUL-terminated bytes).
        # The length is tracked separately in _str_len_table, keyed by the i8* SSA ref.
        # Emit a compile-time literal via add i64 0, <len>.
        # If the length is not tracked (e.g., a Coerce(Bool->Str) result), die loudly.
        my $str_ref = $self->lower_value($operand);
        my $byte_len = $self->_str_len_for($str_ref);
        unless (defined $byte_len) {
            die "GAP: Length(Str) — byte length not tracked for operand SSA ref $str_ref. "
              . "Only compile-time-known Str lengths are supported.";
        }
        my $len = $self->_fresh;
        $self->_emit("  $len = add i64 0, $byte_len  ; Length(Str): compile-time byte length");
        $self->{cache}{ $node->id } = $len;
        return $len;
    }
    else {
        die "GAP: Length operand has repr=$op_repr; only Array and Str are lowered runtime-free.";
    }
}

# _lower_subscript: repr-dispatch on inputs[0] container.
# Array container -> bounds-checked slot load (_lower_array_read body).
# Hash container  -> memcmp key scan (_lower_hash_read body).
# inputs[0] = container (Array or Hash), inputs[1] = index (Int) or key (Str).
sub _lower_subscript {
    my ($self, $node) = @_;
    my $container = $node->inputs->[0];
    my $container_repr = _require_repr($container, 'Subscript.container');

    if ($container_repr eq 'Array' || $container_repr eq 'ArrayRef') {
        # ArrayRef containers: populate _arr_table so _lower_array_read can resolve
        # %Array* from there rather than from the general value cache (which holds i8*).
        # Do NOT overwrite cache{container->id} — that would poison later lower_value
        # calls on the same node (e.g. a PostfixDeref consuming the same ArrayRef).
        if ($container_repr eq 'ArrayRef') {
            $self->lower_value($container);
            unless (exists $self->{_arr_table}{ $container->id }) {
                my $i8 = $self->{cache}{ $container->id };
                my $arr = $self->_fresh;
                $self->_emit("  $arr = bitcast i8* $i8 to %Array*  ; Subscript(ArrayRef): i8* -> Array*");
                $self->{_arr_table}{ $container->id } = $arr;
            }
        }
        return $self->_lower_array_read($node);
    }
    elsif ($container_repr eq 'Hash' || $container_repr eq 'HashRef') {
        # HashRef containers: same as ArrayRef pattern but for Hash*.
        # Do NOT overwrite cache{container->id} — same poison-prevention reason.
        if ($container_repr eq 'HashRef') {
            $self->lower_value($container);
            unless (exists $self->{_hash_table}{ $container->id }) {
                my $i8 = $self->{cache}{ $container->id };
                my $hash = $self->_fresh;
                $self->_emit("  $hash = bitcast i8* $i8 to %Hash*  ; Subscript(HashRef): i8* -> Hash*");
                $self->{_hash_table}{ $container->id } = $hash;
            }
        }
        return $self->_lower_hash_read($node);
    }
    else {
        die "GAP: Subscript container has repr=$container_repr; only Array/ArrayRef and Hash/HashRef are lowered runtime-free.";
    }
}

# _lower_array_read: bounds-checked element read.
# inputs = [Array, index :Int]. repr=Int: extract payload (in-bounds known).
# repr=Slot: return an alloca {i1,i64} — defined=true if in-bounds, false if OOB.
# The bounds-check is ALWAYS emitted (soundness). For repr=Int, the OOB path
# stores undefined into the payload (unreachable for valid in-bounds indices).
sub _lower_array_read {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;

    my $container = $node->inputs->[0];
    $self->lower_value($container);
    # Prefer the already-resolved %Array* from _arr_table; this avoids depending on
    # the general value cache (which holds i8* for ArrayRef nodes, not %Array*).
    # Defense-in-depth: a double-miss (neither table nor cache) would leave $arr_ref
    # undef and silently emit a malformed `getelementptr ... %Array* <undef>`.
    # lower_value($container) above always populates one of the two, so this is
    # unreachable today — but die loudly rather than emit garbage IR if it ever is.
    my $arr_ref = $self->{_arr_table}{ $container->id }
        // $self->{cache}{ $container->id }
        // die "GAP: ArrayRead container (id=" . $container->id . ") resolved to "
             . "neither _arr_table nor cache after lower_value — cannot emit slot load.";
    my $idx_ref = $self->lower_value($node->inputs->[1]);
    my $repr    = _require_repr($node, 'ArrayRead');

    # Load len and elems pointer from the Array struct.
    my $len_ptr  = $self->_fresh;
    my $elem_ptr = $self->_fresh;
    my $len      = $self->_fresh;
    my $elems    = $self->_fresh;
    $self->_emit("  $len_ptr  = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 0  ; ArrayRead: len ptr");
    $self->_emit("  $elem_ptr = getelementptr inbounds %Array, %Array* $arr_ref, i32 0, i32 2  ; ArrayRead: elems ptr");
    $self->_emit("  $len   = load i64, i64* $len_ptr   ; ArrayRead: load len");
    $self->_emit("  $elems = load %Slot*, %Slot** $elem_ptr  ; ArrayRead: load elems");

    # Emit bounds-check: in_bounds = (idx < len).
    my $ok    = $self->_fresh;
    my $lbl_inb = $self->_fresh_label('arr_inb');
    my $lbl_oob = $self->_fresh_label('arr_oob');
    my $lbl_end = $self->_fresh_label('arr_end');
    $self->_emit("  $ok = icmp ult i64 $idx_ref, $len  ; ArrayRead: bounds check (idx < len)");
    $self->_set_terminator("  br i1 $ok, label \%$lbl_inb, label \%$lbl_oob");
    $self->_new_block($lbl_inb);

    # In-bounds: load the slot at elems[idx].
    my $slot_p   = $self->_fresh;
    my $slot_def = $self->_fresh;
    my $slot_pay = $self->_fresh;
    my $def_val  = $self->_fresh;
    my $pay_val  = $self->_fresh;
    $self->_emit("  $slot_p   = getelementptr inbounds %Slot, %Slot* $elems, i64 $idx_ref  ; ArrayRead: slot ptr");
    $self->_emit("  $slot_def = getelementptr inbounds %Slot, %Slot* $slot_p, i32 0, i32 0  ; ArrayRead: slot defined ptr");
    $self->_emit("  $slot_pay = getelementptr inbounds %Slot, %Slot* $slot_p, i32 0, i32 1  ; ArrayRead: slot payload ptr");
    $self->_emit("  $def_val  = load i1,  i1*  $slot_def  ; ArrayRead: load defined bit");
    $self->_emit("  $pay_val  = load i64, i64* $slot_pay  ; ArrayRead: load payload");
    $self->_set_terminator("  br label \%$lbl_end");

    $self->_new_block($lbl_oob);
    # OOB: produce an undef-like slot (defined=false, payload=0).
    $self->_set_terminator("  br label \%$lbl_end");

    $self->_new_block($lbl_end);

    if ($repr eq 'Int') {
        # In-bounds known: phi-select the payload (OOB path unreachable for valid idx).
        my $result = $self->_fresh;
        $self->_emit("  $result = phi i64 [ $pay_val, \%$lbl_inb ], [ 0, \%$lbl_oob ]  ; ArrayRead :Int payload");
        $self->{cache}{ $node->id } = $result;
        return $result;
    }
    elsif ($repr eq 'ArrayRef' || $repr eq 'HashRef') {
        # Pointer element: phi-select payload then inttoptr.
        my $raw_pay = $self->_fresh;
        $self->_emit("  $raw_pay = phi i64 [ $pay_val, \%$lbl_inb ], [ 0, \%$lbl_oob ]  ; ArrayRead :$repr raw ptr payload");
        my $ptr = $self->_fresh;
        $self->_emit("  $ptr = inttoptr i64 $raw_pay to i8*  ; ArrayRead :$repr ptr");
        $self->{cache}{ $node->id } = $ptr;
        return $ptr;
    }
    else {
        # Slot repr: phi-select defined-bit and payload at the merge point.
        # The epilogue retrieves the payload from _slot_payload keyed by the def ref.
        my $def_phi = $self->_fresh;
        my $pay_phi = $self->_fresh;
        $self->_emit("  $def_phi = phi i1  [ $def_val, \%$lbl_inb ], [ false, \%$lbl_oob ]  ; ArrayRead :Slot defined phi");
        $self->_emit("  $pay_phi = phi i64 [ $pay_val, \%$lbl_inb ], [ 0,          \%$lbl_oob ]  ; ArrayRead :Slot payload phi");
        # Track payload for the Slot epilogue.
        $self->{_slot_payload}{$def_phi} = $pay_phi;
        $self->{cache}{ $node->id } = $def_phi;
        return $def_phi;
    }
}

# _lower_hash_read: linear-scan key lookup using phi-based loop counter.
# inputs = [Hash, key :Str]. repr=Int: extract payload (key found).
# repr=Slot: phi-select {defined=false, payload=0} for missing keys.
#
# Block structure:
#   pre_loop_block: load count+entries, br %hloop
#   hloop: %i = phi [0, pre_loop], [i_next, hnxt]; cond = i<count; br hchk/hmiss
#   hchk: load entry[i], len_eq check; br hcmp/hnxt
#   hcmp: memcmp; br hhit/hnxt
#   hhit: load val_def/val_pay; br hend
#   hnxt: i_next = i+1; br hloop  (back-edge)
#   hmiss: br hend
#   hend: phi result
sub _lower_hash_read {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_memcmp}          = 1;

    my $container = $node->inputs->[0];
    $self->lower_value($container);
    # Prefer the already-resolved %Hash* from _hash_table; avoids depending on
    # the general value cache (which holds i8* for HashRef nodes, not %Hash*).
    # Defense-in-depth: a double-miss would leave $hash_ref undef and silently emit
    # malformed IR. lower_value($container) above always populates one — die loudly
    # rather than emit garbage if it ever does not.
    my $hash_ref = $self->{_hash_table}{ $container->id }
        // $self->{cache}{ $container->id }
        // die "GAP: HashRead container (id=" . $container->id . ") resolved to "
             . "neither _hash_table nor cache after lower_value — cannot emit key scan.";
    my $lkey_ref = $self->lower_value($node->inputs->[1]);
    # The key length drives the memcmp scan; a silently-zeroed length makes a
    # zero-length memcmp match ANY entry (spurious key match). If the key length
    # is untracked it is a TypeInference/length-tracking gap — die loudly (matches
    # the I-C loud-GAP contract), do NOT default to 0.
    my $lkey_len = $self->_str_len_for($lkey_ref)
        // die "GAP: HashRead key (ref=$lkey_ref) has no tracked length — "
             . "would emit a 0-length memcmp matching any entry. Fix length tracking.";
    my $repr     = _require_repr($node, 'HashRead');

    # Load count and entries pointer from Hash struct (in current/pre_loop block).
    my $cnt_ptr  = $self->_fresh;
    my $ent_ptr  = $self->_fresh;
    my $count    = $self->_fresh;
    my $ents     = $self->_fresh;
    $self->_emit("  $cnt_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 0  ; HashRead: count ptr");
    $self->_emit("  $ent_ptr = getelementptr inbounds %Hash, %Hash* $hash_ref, i32 0, i32 2  ; HashRead: entries ptr");
    $self->_emit("  $count = load i64, i64* $cnt_ptr  ; HashRead: load count");
    $self->_emit("  $ents  = load %HashEntry*, %HashEntry** $ent_ptr  ; HashRead: load entries");

    # Allocate fresh block labels — all known before any block is emitted.
    my $lbl_loop = $self->_fresh_label('hloop');
    my $lbl_chk  = $self->_fresh_label('hchk');
    my $lbl_cmp  = $self->_fresh_label('hcmp');
    my $lbl_hit  = $self->_fresh_label('hhit');
    my $lbl_nxt  = $self->_fresh_label('hnxt');
    my $lbl_miss = $self->_fresh_label('hmiss');
    my $lbl_end  = $self->_fresh_label('hend');

    # Capture pre_loop label before terminating the current block.
    my $lbl_pre  = $self->_current_block_label;

    # Pre-loop -> loop header
    $self->_set_terminator("  br label \%$lbl_loop");
    $self->_new_block($lbl_loop);

    # Loop header: phi for i using pre_loop (=0) and hnxt (=i+1) predecessors.
    my $i_phi = $self->_fresh;
    my $i_next = $self->_fresh;  # defined later in hnxt; its name is known now
    $self->_emit("  $i_phi = phi i64 [ 0, \%$lbl_pre ], [ $i_next, \%$lbl_nxt ]  ; HashRead: loop counter");
    my $loop_cond = $self->_fresh;
    $self->_emit("  $loop_cond = icmp ult i64 $i_phi, $count  ; HashRead: i < count?");
    $self->_set_terminator("  br i1 $loop_cond, label \%$lbl_chk, label \%$lbl_miss");

    # hchk: load entry[i], compare key length.
    $self->_new_block($lbl_chk);
    my $ent_p   = $self->_fresh;
    my $ent_kpp = $self->_fresh;
    my $ent_klp = $self->_fresh;
    my $ent_vdp = $self->_fresh;
    my $ent_vpp = $self->_fresh;
    my $ent_kp  = $self->_fresh;
    my $ent_kl  = $self->_fresh;
    $self->_emit("  $ent_p   = getelementptr inbounds %HashEntry, %HashEntry* $ents, i64 $i_phi  ; HashRead: entry[$i_phi] ptr");
    $self->_emit("  $ent_kpp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 0  ; HashRead: key_ptr field ptr");
    $self->_emit("  $ent_klp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 1  ; HashRead: key_len field ptr");
    $self->_emit("  $ent_vdp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 3  ; HashRead: val_def field ptr");
    $self->_emit("  $ent_vpp = getelementptr inbounds %HashEntry, %HashEntry* $ent_p, i32 0, i32 4  ; HashRead: val_pay field ptr");
    $self->_emit("  $ent_kp  = load i8*,  i8**  $ent_kpp  ; HashRead: load entry key ptr");
    $self->_emit("  $ent_kl  = load i64,  i64*  $ent_klp  ; HashRead: load entry key len");
    my $len_eq = $self->_fresh;
    $self->_emit("  $len_eq = icmp eq i64 $ent_kl, $lkey_len  ; HashRead: key-len eq?");
    $self->_set_terminator("  br i1 $len_eq, label \%$lbl_cmp, label \%$lbl_nxt");

    # hcmp: memcmp key bytes.
    $self->_new_block($lbl_cmp);
    my $cmp_res  = $self->_fresh;
    my $is_match = $self->_fresh;
    $self->_emit("  $cmp_res  = call i32 \@memcmp(i8* nocapture readonly $ent_kp, i8* nocapture readonly $lkey_ref, i64 $lkey_len)  ; HashRead: key memcmp");
    $self->_emit("  $is_match = icmp eq i32 $cmp_res, 0  ; HashRead: key match?");
    $self->_set_terminator("  br i1 $is_match, label \%$lbl_hit, label \%$lbl_nxt");

    # hhit: load value slot.
    $self->_new_block($lbl_hit);
    my $vd_val = $self->_fresh;
    my $vp_val = $self->_fresh;
    $self->_emit("  $vd_val = load i1,  i1*  $ent_vdp  ; HashRead: val defined bit");
    $self->_emit("  $vp_val = load i64, i64* $ent_vpp  ; HashRead: val payload");
    $self->_set_terminator("  br label \%$lbl_end");

    # hnxt: i++ and back-edge to loop header.
    $self->_new_block($lbl_nxt);
    # $i_next was fresh()ed earlier so its name is deterministic.
    $self->_emit("  $i_next = add i64 $i_phi, 1  ; HashRead: i++");
    $self->_set_terminator("  br label \%$lbl_loop");

    # hmiss: key not found.
    $self->_new_block($lbl_miss);
    $self->_set_terminator("  br label \%$lbl_end");

    # hend: result phi.
    $self->_new_block($lbl_end);

    if ($repr eq 'Int') {
        my $result = $self->_fresh;
        $self->_emit("  $result = phi i64 [ $vp_val, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; HashRead :Int payload");
        $self->{cache}{ $node->id } = $result;
        return $result;
    }
    elsif ($repr eq 'ArrayRef' || $repr eq 'HashRef') {
        # Pointer element: phi-select payload then inttoptr (mirrors _lower_array_read).
        # The slot payload holds a ref (ArrayRef/HashRef) stored as i64; reading it
        # back as a usable pointer requires inttoptr i64 -> i8*.
        my $raw_pay = $self->_fresh;
        $self->_emit("  $raw_pay = phi i64 [ $vp_val, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; HashRead :$repr raw ptr payload");
        my $ptr = $self->_fresh;
        $self->_emit("  $ptr = inttoptr i64 $raw_pay to i8*  ; HashRead :$repr ptr");
        $self->{cache}{ $node->id } = $ptr;
        return $ptr;
    }
    else {
        # Slot repr: phi-select defined-bit and payload. Track payload for epilogue.
        my $def_phi = $self->_fresh;
        my $pay_phi = $self->_fresh;
        $self->_emit("  $def_phi = phi i1  [ $vd_val, \%$lbl_hit ], [ false, \%$lbl_miss ]  ; HashRead :Slot defined phi");
        $self->_emit("  $pay_phi = phi i64 [ $vp_val, \%$lbl_hit ], [ 0,     \%$lbl_miss ]  ; HashRead :Slot payload phi");
        $self->{_slot_payload}{$def_phi} = $pay_phi;
        $self->{cache}{ $node->id } = $def_phi;
        return $def_phi;
    }
}

# _lower_postfix_deref: repr-dispatch on sigil to dereference a ref value.
# sigil="@" → ArrayRef (i8*) → Array* bitcast (_lower_array_deref body).
# sigil="%" → HashRef  (i8*) → Hash*  bitcast (_lower_hash_deref body).
# sigil="$" → scalar deref (not yet in corpus; GAPs loudly).
# The input is the ref value (i8*); the output is the struct pointer.
sub _lower_postfix_deref {
    my ($self, $node) = @_;
    my $sigil = $node->sigil();

    if ($sigil eq '@') {
        return $self->_lower_array_deref($node);
    }
    elsif ($sigil eq '%') {
        return $self->_lower_hash_deref($node);
    }
    else {
        die "GAP: PostfixDeref sigil='$sigil' is not yet lowered runtime-free (only @ and % are supported).";
    }
}

# _lower_array_deref: cast i8* ref back to %Array*.
# The input is an ArrayRef (i8*); the output is an Array* for use by Length/Subscript.
# Populates _arr_table so Length/Subscript can resolve %Array* without a bitcast.
sub _lower_array_deref {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;

    my $ref_val = $self->lower_value($node->inputs->[0]);
    my $arr = $self->_fresh;
    $self->_emit("  $arr = bitcast i8* $ref_val to %Array*  ; ArrayDeref: i8* ref -> Array*");
    $self->{cache}{ $node->id } = $arr;
    # Track in _arr_table so Length(PostfixDeref(@)) finds %Array* directly.
    $self->{_arr_table}{ $node->id } = $arr;
    return $arr;
}

# _lower_hash_deref: cast i8* ref back to %Hash*.
# Populates _hash_table so consumers can resolve %Hash* without a bitcast.
sub _lower_hash_deref {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;

    my $ref_val = $self->lower_value($node->inputs->[0]);
    my $hash = $self->_fresh;
    $self->_emit("  $hash = bitcast i8* $ref_val to %Hash*  ; HashDeref: i8* ref -> Hash*");
    $self->{cache}{ $node->id } = $hash;
    # Track in _hash_table so consumers can resolve %Hash* without a bitcast.
    $self->{_hash_table}{ $node->id } = $hash;
    return $hash;
}

# ---------------------------------------------------------------------------
# MOP / class object lowering (G5: feature-class static vtables + object structs)
# ---------------------------------------------------------------------------

# _lower_new($node) -> $llvm_ref
#
# Lowers a New node: malloc the object struct, store the vtable pointer, and
# bind each :param field from the node's inputs[1..N].
#
# Object layout: %Cls.obj = { %Cls.vt*, %Slot, %Slot, ... }
# Vtable ptr is stored at GEP index 0. Field i is at GEP index i+1 (one %Slot
# = two sub-elements: i1 at index 0, i64 at index 1; we use the Slot type).
#
# Returns: an i8* (raw opaque pointer to the object). The Object repr signals
# to MethodCall/FieldWrite that this is an object pointer.
sub _lower_new {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    my $cls_node    = $node->class_decl_node;
    my $class_name  = _class_name_from_class_node($cls_node);
    my $param_names = $node->param_names // [];
    my $param_vals  = $node->param_values // [];

    # Verify the class is registered
    my $reg = $self->{class_registry}{$class_name}
        or die "LLVM MOP: New references undeclared class '$class_name'";

    # malloc the object
    my $raw     = $self->_fresh;
    my $obj_ref = $self->_fresh;
    $self->_emit("  $raw     = call i8* \@malloc(i64 ptrtoint (%${class_name}.obj* getelementptr (%${class_name}.obj, %${class_name}.obj* null, i64 1) to i64))  ; New $class_name: sizeof");
    $self->_emit("  $obj_ref = bitcast i8* $raw to %${class_name}.obj*  ; New $class_name: typed ptr");

    # Store vtable pointer
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 0  ; vtable ptr slot");
    $self->_emit("  store %${class_name}.vt* \@${class_name}__vtable, %${class_name}.vt** $vt_gep  ; store vtable");

    # Bind :param fields
    my $fields = $reg->{fields} // [];
    for my $i (0 .. $#$param_names) {
        my $pname   = $param_names->[$i];
        my $pval    = $param_vals->[$i];
        # Find the field with this param name
        my ($finfo) = grep { ($_->{name} // '') eq $pname } @$fields;
        unless (defined $finfo) {
            die "LLVM MOP: New $class_name: no :param field named '$pname' in class registry";
        }
        my $fidx = $finfo->{field_index};
        my $slot_idx = $fidx + 1;  # +1 for vtable pointer at index 0
        # Outer 'Int' default: pval absent = no param value node wired (legitimate).
        # _require_repr guards a present pval with undef repr (TypeInference gap).
        my $repr = defined $pval ? _require_repr($pval, 'New.:param.field') : 'Int';

        my $val_ref = $self->lower_value($pval);

        # Store the defined=1 bit
        my $def_gep = $self->_fresh;
        $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 0  ; field[$fidx] defined bit");
        $self->_emit("  store i1 true, i1* $def_gep  ; field '$pname' defined=true");

        # Store the payload
        my $pay_gep = $self->_fresh;
        $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 1  ; field[$fidx] payload");
        if ($repr eq 'Str') {
            # Str payload: store ptr as i64. The length is tracked separately in _str_len_table.
            # Allocate a heap StrPair to store {ptr, len} and store its address as i64.
            my $len_ref = $self->{_str_len_table}{$val_ref};
            my $pair_raw = $self->_fresh;
            my $pair_ptr = $self->_fresh;
            $self->_emit("  $pair_raw = call i8* \@malloc(i64 16)  ; alloc StrPair for field '$pname'");
            $self->_emit("  $pair_ptr = bitcast i8* $pair_raw to %StrPair*  ; typed StrPair ptr");
            my $pp_gep = $self->_fresh;
            $self->_emit("  $pp_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 0  ; StrPair.ptr");
            $self->_emit("  store i8* $val_ref, i8** $pp_gep  ; store str ptr");
            my $pl_gep = $self->_fresh;
            $self->_emit("  $pl_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 1  ; StrPair.len");
            my $len_val = defined $len_ref ? $len_ref : 'zeroinitializer';
            if ($len_val eq 'zeroinitializer') {
                # Compute length via strlen at runtime
                $len_val = $self->_fresh;
                $self->_emit("  $len_val = call i64 \@strlen(i8* $val_ref)  ; strlen for Str field '$pname'");
            }
            $self->_emit("  store i64 $len_val, i64* $pl_gep  ; store str len");
            my $pair_as_i64 = $self->_fresh;
            $self->_emit("  $pair_as_i64 = ptrtoint %StrPair* $pair_ptr to i64  ; StrPair* -> i64 payload");
            $self->_emit("  store i64 $pair_as_i64, i64* $pay_gep  ; field '$pname' Str payload = StrPair*");
            # For Str-typed field, the StrPair pointer (as i64) is the payload.
            $self->{_need_strpair} = 1;
        }
        else {
            # Int/Bool: store directly as i64
            my $pay_i64 = $self->_fresh;
            if ($repr eq 'Bool') {
                $self->_emit("  $pay_i64 = zext i1 $val_ref to i64  ; Bool->i64 for field '$pname'");
            }
            else {
                $self->_emit("  $pay_i64 = add i64 0, $val_ref  ; identity: $repr->i64 for field '$pname'");
            }
            $self->_emit("  store i64 $pay_i64, i64* $pay_gep  ; field '$pname' payload");
        }
    }

    # Store default fields (has_default=true, not provided as :param at this New call)
    for my $finfo (@$fields) {
        my $pname = $finfo->{name} // '';
        next if grep { $_ eq $pname } @$param_names;  # already bound above
        my $fidx     = $finfo->{field_index};
        my $slot_idx = $fidx + 1;

        if ($finfo->{has_default}) {
            # Has a default value node — bind it
            my $def_node = $finfo->{default_node};
            # Outer 'Int' default: def_node absent = no default value wired (legitimate).
            # _require_repr guards a present def_node with undef repr (TypeInference gap).
            my $def_repr = defined $def_node ? _require_repr($def_node, 'New.default.field') : 'Int';
            my $def_ref  = defined $def_node ? $self->lower_value($def_node) : '0';

            my $def_gep = $self->_fresh;
            $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 0  ; default field[$fidx] defined");
            $self->_emit("  store i1 true, i1* $def_gep  ; field '$pname' default defined=true");
            my $pay_gep = $self->_fresh;
            $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 1  ; default field[$fidx] payload");
            my $pay_i64 = $self->_fresh;
            $self->_emit("  $pay_i64 = add i64 0, $def_ref  ; default value for field '$pname'");
            $self->_emit("  store i64 $pay_i64, i64* $pay_gep");
        }
        else {
            # No default: defined=false, payload=0
            my $def_gep = $self->_fresh;
            $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 0  ; uninit field[$fidx] defined");
            $self->_emit("  store i1 false, i1* $def_gep  ; field '$pname' not initialized");
            my $pay_gep = $self->_fresh;
            $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 1  ; uninit field[$fidx] payload");
            $self->_emit("  store i64 0, i64* $pay_gep  ; field '$pname' payload=0");
        }
    }

    # ADJUST blocks: lower each ADJUST body in base-first order.
    # ADJUST bodies run with implicit $self = the newly constructed object (raw i8* pointer).
    # Set _in_method_body + method context so FieldAccess/FieldWrite use the raw pointer.
    my $adjusts = $reg->{adjusts} // [];
    for my $adj (@$adjusts) {
        # adj = { body_nodes => [...] } where body_nodes are FieldWrite nodes
        for my $fw_node (@{ $adj->{body_nodes} // [] }) {
            # Temporarily set method body context for FieldAccess/FieldWrite.
            # Use $raw (i8*) not $obj_ref (%Cls.obj*) so field-body bitcasts are correct.
            local $self->{_in_method_body}    = 1;
            local $self->{_method_self_name}  = $raw;
            local $self->{_method_class_name} = $class_name;
            $self->lower_value($fw_node);
        }
    }

    # Return the raw i8* pointer (Object repr)
    my $result = $self->_fresh;
    $self->_emit("  $result = bitcast %${class_name}.obj* $obj_ref to i8*  ; New $class_name: -> Object (i8*)");
    $self->{cache}{ $node->id } = $result;
    return $result;
}

# _lower_call_new($node) -> $llvm_ref
#
# Lowers a Call(dispatch_kind='method', name='new') node.
# This is the canonical form of the New node: malloc + vtable bind + :param binding.
# inputs[0] = ClassInfo, inputs[1..N] = :param values, param_names = [names].
sub _lower_call_new {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    my $cls_node    = $node->inputs->[0];
    my $class_name  = _class_name_from_class_node($cls_node);
    my $param_names = $node->can('param_names') ? ($node->param_names // []) : [];
    # inputs[1..N] are the :param values
    my $all_inputs  = $node->inputs // [];
    my $param_vals  = scalar(@$all_inputs) > 1 ? [ @{$all_inputs}[1 .. $#$all_inputs] ] : [];

    # Verify the class is registered
    my $reg = $self->{class_registry}{$class_name}
        or die "LLVM MOP: Call(new) references undeclared class '$class_name'";

    # malloc the object
    my $raw     = $self->_fresh;
    my $obj_ref = $self->_fresh;
    $self->_emit("  $raw     = call i8* \@malloc(i64 ptrtoint (%${class_name}.obj* getelementptr (%${class_name}.obj, %${class_name}.obj* null, i64 1) to i64))  ; Call(new) $class_name: sizeof");
    $self->_emit("  $obj_ref = bitcast i8* $raw to %${class_name}.obj*  ; Call(new) $class_name: typed ptr");

    # Store vtable pointer
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 0  ; vtable ptr slot");
    $self->_emit("  store %${class_name}.vt* \@${class_name}__vtable, %${class_name}.vt** $vt_gep  ; store vtable");

    # Bind :param fields
    my $fields = $reg->{fields} // [];
    for my $i (0 .. $#$param_names) {
        my $pname   = $param_names->[$i];
        my $pval    = $param_vals->[$i];
        my ($finfo) = grep { ($_->{name} // '') eq $pname } @$fields;
        unless (defined $finfo) {
            die "LLVM MOP: Call(new) $class_name: no :param field named '$pname' in class registry";
        }
        my $fidx = $finfo->{field_index};
        my $slot_idx = $fidx + 1;
        my $repr = defined $pval ? _require_repr($pval, 'Call(new).:param.field') : 'Int';
        my $val_ref = $self->lower_value($pval);

        my $def_gep = $self->_fresh;
        $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 0  ; field[$fidx] defined bit");
        $self->_emit("  store i1 true, i1* $def_gep  ; field '$pname' defined=true");
        my $pay_gep = $self->_fresh;
        $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 1  ; field[$fidx] payload");

        if ($repr eq 'Str') {
            my $len_ref  = $self->{_str_len_table}{$val_ref};
            my $pair_raw = $self->_fresh;
            my $pair_ptr = $self->_fresh;
            $self->_emit("  $pair_raw = call i8* \@malloc(i64 16)  ; alloc StrPair for field '$pname'");
            $self->_emit("  $pair_ptr = bitcast i8* $pair_raw to %StrPair*  ; typed StrPair ptr");
            my $pp_gep = $self->_fresh;
            $self->_emit("  $pp_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 0  ; StrPair.ptr");
            $self->_emit("  store i8* $val_ref, i8** $pp_gep  ; store str ptr");
            my $pl_gep = $self->_fresh;
            $self->_emit("  $pl_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 1  ; StrPair.len");
            my $len_val = defined $len_ref ? $len_ref : 'zeroinitializer';
            if ($len_val eq 'zeroinitializer') {
                $len_val = $self->_fresh;
                $self->_emit("  $len_val = call i64 \@strlen(i8* $val_ref)  ; strlen for Str field '$pname'");
            }
            $self->_emit("  store i64 $len_val, i64* $pl_gep  ; store str len");
            my $pair_as_i64 = $self->_fresh;
            $self->_emit("  $pair_as_i64 = ptrtoint %StrPair* $pair_ptr to i64  ; StrPair* -> i64 payload");
            $self->_emit("  store i64 $pair_as_i64, i64* $pay_gep  ; field '$pname' Str payload = StrPair*");
            $self->{_need_strpair} = 1;
        } else {
            my $pay_i64 = $self->_fresh;
            if ($repr eq 'Bool') {
                $self->_emit("  $pay_i64 = zext i1 $val_ref to i64  ; Bool->i64 for field '$pname'");
            } else {
                $self->_emit("  $pay_i64 = add i64 0, $val_ref  ; identity: $repr->i64 for field '$pname'");
            }
            $self->_emit("  store i64 $pay_i64, i64* $pay_gep  ; field '$pname' payload");
        }
    }

    # Store default/uninit fields not provided as :param
    for my $finfo (@$fields) {
        my $pname = $finfo->{name} // '';
        next if grep { $_ eq $pname } @$param_names;
        my $fidx     = $finfo->{field_index};
        my $slot_idx = $fidx + 1;
        if ($finfo->{has_default}) {
            my $def_node = $finfo->{default_node};
            my $def_repr = defined $def_node ? _require_repr($def_node, 'Call(new).default.field') : 'Int';
            my $def_ref  = defined $def_node ? $self->lower_value($def_node) : '0';
            my $def_gep = $self->_fresh;
            $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 0  ; default field[$fidx] defined");
            $self->_emit("  store i1 true, i1* $def_gep  ; field '$pname' default defined=true");
            my $pay_gep = $self->_fresh;
            $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 1  ; default field[$fidx] payload");
            my $pay_i64 = $self->_fresh;
            $self->_emit("  $pay_i64 = add i64 0, $def_ref  ; default value for field '$pname'");
            $self->_emit("  store i64 $pay_i64, i64* $pay_gep");
        } else {
            my $def_gep = $self->_fresh;
            $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 0  ; uninit field[$fidx] defined");
            $self->_emit("  store i1 false, i1* $def_gep  ; field '$pname' not initialized");
            my $pay_gep = $self->_fresh;
            $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_ref, i64 0, i32 $slot_idx, i32 1  ; uninit field[$fidx] payload");
            $self->_emit("  store i64 0, i64* $pay_gep  ; field '$pname' payload=0");
        }
    }

    # ADJUST blocks
    my $adjusts = $reg->{adjusts} // [];
    for my $adj (@$adjusts) {
        for my $fw_node (@{ $adj->{body_nodes} // [] }) {
            local $self->{_in_method_body}    = 1;
            local $self->{_method_self_name}  = $raw;
            local $self->{_method_class_name} = $class_name;
            $self->lower_value($fw_node);
        }
    }

    # Return the raw i8* pointer (Object repr)
    my $result = $self->_fresh;
    $self->_emit("  $result = bitcast %${class_name}.obj* $obj_ref to i8*  ; Call(new) $class_name: -> Object (i8*)");
    $self->{cache}{ $node->id } = $result;
    return $result;
}

# _lower_call_method($node) -> $llvm_ref
#
# Lowers a Call(dispatch_kind='method') node.
# When name='new': routes to the constructor lowering (_lower_call_new).
# Otherwise: vtable-dispatch (same logic as the former _lower_method_call).
# inputs[0] = ClassInfo (class reference) for name='new'.
# inputs[0] = invocant (obj), inputs[1] = ClassInfo for regular method calls.
sub _lower_call_method {
    my ($self, $node) = @_;

    my $method_name = $node->name;

    # Route constructor calls to the construction lowering.
    if ($method_name eq 'new') {
        return $self->_lower_call_new($node);
    }
    my $obj_node    = $node->inputs->[0];
    my $cls_node    = $node->inputs->[1];
    my $class_name  = _class_name_from_class_node($cls_node);
    my $result_repr = _require_repr($node, 'Call(method)');

    # Verify class and method are in the registry
    my $reg = $self->{class_registry}{$class_name}
        or die "LLVM MOP: Call(method) '$method_name' on undeclared class '$class_name' — "
             . "no ClassInfo registered for this class. Cannot emit vtable slot.";

    my $methods = $reg->{methods} // [];
    my ($minfo) = grep { ($_->{name} // '') eq $method_name } @$methods;
    unless (defined $minfo) {
        die "LLVM MOP: Call(method) '$method_name' is absent from class '$class_name' vtable — "
          . "available methods: [" . join(', ', map { $_->{name} // '?' } @$methods) . "]. "
          . "Cannot emit vtable dispatch to a non-existent slot.";
    }

    my $slot_idx = $minfo->{vtable_slot};

    # Lower the object to get the raw pointer
    my $obj_raw = $self->lower_value($obj_node);

    # Load vtable pointer
    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; Call(method) $method_name: typed obj");
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 0  ; vtable ptr slot");
    my $vt_ptr = $self->_fresh;
    $self->_emit("  $vt_ptr = load %${class_name}.vt*, %${class_name}.vt** $vt_gep  ; load vtable ptr");

    # Load opaque fn ptr from vtable slot
    my $fn_slot_llvm = 1 + $slot_idx;
    my $fn_gep = $self->_fresh;
    $self->_emit("  $fn_gep = getelementptr inbounds %${class_name}.vt, %${class_name}.vt* $vt_ptr, i64 0, i32 $fn_slot_llvm  ; method '$method_name' fn ptr slot");
    my $opaque_fn = $self->_fresh;
    $self->_emit("  $opaque_fn = load i8*, i8** $fn_gep  ; load opaque fn ptr for '$method_name'");

    # Cast to actual fn-ptr type and call
    my $fn_type  = _method_fn_type($result_repr);
    my $typed_fn = $self->_fresh;
    $self->_emit("  $typed_fn = bitcast i8* $opaque_fn to $fn_type*  ; cast to typed fn ptr");

    my $result = $self->_fresh;
    if ($result_repr eq 'Str') {
        $self->{_need_strpair} = 1;
        $self->_emit("  $result = call %StrPair $typed_fn(i8* $obj_raw)  ; Call(method) $method_name -> StrPair");
        my $str_ptr = $self->_fresh;
        my $str_len = $self->_fresh;
        $self->_emit("  $str_ptr = extractvalue %StrPair $result, 0  ; Call(method) $method_name result ptr");
        $self->_emit("  $str_len = extractvalue %StrPair $result, 1  ; Call(method) $method_name result len");
        $self->{_str_len_table}{$str_ptr} = $str_len;
        $self->{cache}{ $node->id } = $str_ptr;
        return $str_ptr;
    }
    else {
        $self->_emit("  $result = call i64 $typed_fn(i8* $obj_raw)  ; Call(method) $method_name -> i64");
        $self->{cache}{ $node->id } = $result;
        return $result;
    }
}

# _lower_method_call($node) -> $llvm_ref
#
# Lowers a MethodCall node: load vtable from obj, GEP to the method slot,
# load the opaque fn ptr, cast to the actual fn-ptr type, and call.
#
# Adversarial contract: if the method name is not in the class's vtable,
# die loudly at lowering time — NEVER emit a null/garbage fn-ptr.
sub _lower_method_call {
    my ($self, $node) = @_;

    my $method_name = $node->method_name;
    my $obj_node    = $node->obj_node;
    my $cls_node    = $node->class_decl_node;
    my $class_name  = _class_name_from_class_node($cls_node);
    my $result_repr = _require_repr($node, 'MethodCall');

    # Verify class and method are in the registry
    my $reg = $self->{class_registry}{$class_name}
        or die "LLVM MOP: MethodCall '$method_name' on undeclared class '$class_name' — "
             . "no ClassDecl registered for this class. Cannot emit vtable slot.";

    my $methods = $reg->{methods} // [];
    my ($minfo) = grep { ($_->{name} // '') eq $method_name } @$methods;
    unless (defined $minfo) {
        die "LLVM MOP: MethodCall '$method_name' is absent from class '$class_name' vtable — "
          . "available methods: [" . join(', ', map { $_->{name} // '?' } @$methods) . "]. "
          . "Cannot emit vtable dispatch to a non-existent slot.";
    }

    my $slot_idx  = $minfo->{vtable_slot};  # index in vtable (after class-name ptr)

    # Lower the object to get the raw pointer
    my $obj_raw = $self->lower_value($obj_node);

    # Load vtable pointer: GEP %Cls.obj[0].field[0] = vtable ptr slot
    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; MethodCall $method_name: typed obj");
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 0  ; vtable ptr slot");
    my $vt_ptr = $self->_fresh;
    $self->_emit("  $vt_ptr = load %${class_name}.vt*, %${class_name}.vt** $vt_gep  ; load vtable ptr");

    # Load opaque fn ptr from vtable slot (slot index = 1 + vtable_slot for methods,
    # since slot 0 is the class-name pointer)
    my $fn_slot_llvm = 1 + $slot_idx;
    my $fn_gep = $self->_fresh;
    $self->_emit("  $fn_gep = getelementptr inbounds %${class_name}.vt, %${class_name}.vt* $vt_ptr, i64 0, i32 $fn_slot_llvm  ; method '$method_name' fn ptr slot");
    my $opaque_fn = $self->_fresh;
    $self->_emit("  $opaque_fn = load i8*, i8** $fn_gep  ; load opaque fn ptr for '$method_name'");

    # Cast to actual fn-ptr type and call
    my $fn_type  = _method_fn_type($result_repr);
    my $typed_fn = $self->_fresh;
    $self->_emit("  $typed_fn = bitcast i8* $opaque_fn to $fn_type*  ; cast to typed fn ptr");

    # Call the method: always passes self as first arg
    my $result = $self->_fresh;
    if ($result_repr eq 'Str') {
        # Str returns: method returns %StrPair (as struct value)
        $self->{_need_strpair} = 1;
        $self->_emit("  $result = call %StrPair $typed_fn(i8* $obj_raw)  ; call $method_name -> StrPair");
        # Extract ptr and len
        my $str_ptr = $self->_fresh;
        my $str_len = $self->_fresh;
        $self->_emit("  $str_ptr = extractvalue %StrPair $result, 0  ; MethodCall $method_name result ptr");
        $self->_emit("  $str_len = extractvalue %StrPair $result, 1  ; MethodCall $method_name result len");
        $self->{_str_len_table}{$str_ptr} = $str_len;
        $self->{cache}{ $node->id } = $str_ptr;
        return $str_ptr;
    }
    else {
        # Int return: i64
        $self->_emit("  $result = call i64 $typed_fn(i8* $obj_raw)  ; call $method_name -> i64");
        $self->{cache}{ $node->id } = $result;
        return $result;
    }
}

# _lower_field_write($node) -> $llvm_ref
#
# Lowers a FieldWrite node: GEP to the field's %Slot within the object struct,
# store {defined=1, payload} into the Slot.
#
# Two calling conventions:
#   Non-method-body context: inputs[0]=obj_node, inputs[1]=new_val_node
#   Method-body context:     inputs[0]=new_val_node (obj is implicit $self)
sub _lower_field_write {
    my ($self, $node) = @_;

    if ($self->{_in_method_body}) {
        # Method body context: object is implicit $self
        my $obj_raw    = $self->{_method_self_name} // '%self';
        my $class_name = $self->{_method_class_name}
            or die "LLVM MOP: FieldWrite in method body but _method_class_name not set";
        return $self->_lower_field_write_method_body($node, $obj_raw, $class_name);
    }

    # Non-method-body context: inputs[0]=obj_node, inputs[1]=new_val_node
    my $obj_node   = $node->obj_node;
    my $class_name = _infer_class_name_from_obj($obj_node);
    my $obj_raw    = $self->lower_value($obj_node);
    return $self->_lower_field_write_with_obj($node, $obj_raw, $class_name);
}

# _lower_field_write_method_body($node, $obj_raw, $class_name) -> $llvm_ref
# Method-body FieldWrite: inputs[0] = new value node (no explicit obj).
sub _lower_field_write_method_body {
    my ($self, $node, $obj_raw, $class_name) = @_;

    my $val_node    = $node->inputs->[0]  # inputs[0] is the new value in method context
        or die "LLVM MOP: FieldWrite in method body has no value node (inputs[0] undef)";
    my $field_index = $node->field_index;
    my $val_repr    = _require_repr($val_node, 'FieldWrite(method).val');
    my $slot_idx    = $field_index + 1;

    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; FieldWrite(method): typed self");

    my $val_ref = $self->lower_value($val_node);

    my $def_gep = $self->_fresh;
    $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 0  ; FieldWrite(method)[$field_index] defined");
    $self->_emit("  store i1 true, i1* $def_gep");
    my $pay_gep = $self->_fresh;
    $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 1  ; FieldWrite(method)[$field_index] payload");
    my $pay_i64 = $self->_fresh;
    if ($val_repr eq 'Bool') {
        $self->_emit("  $pay_i64 = zext i1 $val_ref to i64");
    }
    else {
        $self->_emit("  $pay_i64 = add i64 0, $val_ref  ; identity: $val_repr->i64");
    }
    $self->_emit("  store i64 $pay_i64, i64* $pay_gep");

    $self->{cache}{ $node->id } = $pay_i64;
    return $pay_i64;
}

# _lower_field_write_with_obj($node, $obj_raw, $class_name) -> $llvm_ref
#
# Implementation of FieldWrite given an already-lowered object raw pointer.
sub _lower_field_write_with_obj {
    my ($self, $node, $obj_raw, $class_name) = @_;

    my $val_node    = $node->new_val_node;
    my $field_index = $node->field_index;
    # Outer 'Int' default: val_node absent = no value wired (legitimate skip).
    # _require_repr guards a present val_node with undef repr (TypeInference gap).
    my $val_repr    = defined $val_node ? _require_repr($val_node, 'FieldWrite.val') : 'Int';

    my $slot_idx = $field_index + 1;

    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; FieldWrite: typed obj");

    my $val_ref = $self->lower_value($val_node);

    # Store defined=true
    my $def_gep = $self->_fresh;
    $self->_emit("  $def_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 0  ; FieldWrite[$field_index] defined");
    $self->_emit("  store i1 true, i1* $def_gep  ; FieldWrite[$field_index] defined=true");

    # Store payload as i64
    my $pay_gep = $self->_fresh;
    $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 1  ; FieldWrite[$field_index] payload");
    my $pay_i64 = $self->_fresh;
    if ($val_repr eq 'Bool') {
        $self->_emit("  $pay_i64 = zext i1 $val_ref to i64  ; Bool->i64 FieldWrite");
    }
    else {
        $self->_emit("  $pay_i64 = add i64 0, $val_ref  ; identity: $val_repr->i64 FieldWrite");
    }
    $self->_emit("  store i64 $pay_i64, i64* $pay_gep  ; FieldWrite[$field_index] payload");

    $self->{cache}{ $node->id } = $pay_i64;
    return $pay_i64;
}

# _lower_ref_of_object($node) -> $llvm_ref (Str: ptr to class-name string)
#
# Lowers ref($obj) where obj has repr=Object. Returns the class-name string
# pointer (i8*) and tracks the compile-time-known length in _str_len_table.
sub _lower_ref_of_object {
    my ($self, $node) = @_;

    my $obj_node = $node->inputs->[0];

    # Walk obj_node back to the New node to find the ClassDecl
    my $class_name = _infer_class_name_from_obj($obj_node);
    my $name_len   = length($class_name);  # compile-time known ASCII length

    # Load vtable from obj, load class-name ptr from vtable slot 0.
    # This is the runtime-verifiable path (load from actual vtable).
    my $obj_raw = $self->lower_value($obj_node);
    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; ref(obj): typed obj");
    my $vt_gep = $self->_fresh;
    $self->_emit("  $vt_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 0  ; vtable ptr slot");
    my $vt_ptr = $self->_fresh;
    $self->_emit("  $vt_ptr = load %${class_name}.vt*, %${class_name}.vt** $vt_gep  ; load vtable");
    my $cn_gep = $self->_fresh;
    $self->_emit("  $cn_gep = getelementptr inbounds %${class_name}.vt, %${class_name}.vt* $vt_ptr, i64 0, i32 0  ; class-name ptr slot");
    my $cn_ptr = $self->_fresh;
    $self->_emit("  $cn_ptr = load i8*, i8** $cn_gep  ; load class-name ptr");

    # Track the compile-time-known length for the Str output epilogue
    $self->{_str_len_table}{$cn_ptr} = $name_len;
    $self->{cache}{ $node->id } = $cn_ptr;
    return $cn_ptr;
}

# _lower_field_access_in_method($node) -> $llvm_ref
#
# Lowers a FieldAccess node when inside a method body context.
# Reads from %self at the field's struct offset.
# For Str fields: payload is a StrPair* (as i64); returns the string ptr.
sub _lower_field_access_in_method {
    my ($self, $node) = @_;

    my $field_index = $node->field_index;
    my $class_name  = $self->{_method_class_name}
        or die "LLVM MOP: FieldAccess in method body but _method_class_name not set";
    my $repr        = _require_repr($node, 'FieldAccess(method)');

    my $slot_idx  = $field_index + 1;
    my $obj_raw   = $self->{_method_self_name} // '%self';
    my $obj_typed = $self->_fresh;
    $self->_emit("  $obj_typed = bitcast i8* $obj_raw to %${class_name}.obj*  ; FieldAccess: typed self");
    my $pay_gep   = $self->_fresh;
    $self->_emit("  $pay_gep = getelementptr inbounds %${class_name}.obj, %${class_name}.obj* $obj_typed, i64 0, i32 $slot_idx, i32 1  ; field[$field_index] payload");
    my $pay       = $self->_fresh;
    $self->_emit("  $pay = load i64, i64* $pay_gep  ; load field[$field_index] payload");

    if ($repr eq 'Str') {
        # Payload is a StrPair* (as i64) — cast and extract {ptr, len}
        $self->{_need_strpair} = 1;
        my $pair_ptr = $self->_fresh;
        $self->_emit("  $pair_ptr = inttoptr i64 $pay to %StrPair*  ; payload -> StrPair*");
        my $pp_gep = $self->_fresh;
        $self->_emit("  $pp_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 0  ; StrPair.ptr");
        my $sp = $self->_fresh;
        $self->_emit("  $sp = load i8*, i8** $pp_gep  ; load str ptr");
        my $lp_gep = $self->_fresh;
        $self->_emit("  $lp_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 1  ; StrPair.len");
        my $sl = $self->_fresh;
        $self->_emit("  $sl = load i64, i64* $lp_gep  ; load str len");
        $self->{_str_len_table}{$sp} = $sl;
        $self->{cache}{ $node->id } = $sp;
        return $sp;
    }
    else {
        # Int: payload is i64 directly
        $self->{cache}{ $node->id } = $pay;
        return $pay;
    }
}

# _infer_class_name_from_obj($obj_node) -> $class_name
#
# Walks the obj_node back to find the ClassDecl. Currently supports:
# - New node (inputs[0] = ClassDecl)
# - Other cases: die loudly (cannot infer class name)
sub _infer_class_name_from_obj {
    my ($obj_node) = @_;
    return undef unless defined $obj_node;
    my $op = $obj_node->can('operation') ? $obj_node->operation : '';
    if ($op eq 'New') {
        my $cls_node = $obj_node->class_decl_node;
        return defined $cls_node ? _class_name_from_class_node($cls_node) : undef;
    }
    # Call(dispatch_kind='method', name='new') is the canonical form of New.
    if ($op eq 'Call' && $obj_node->can('dispatch_kind')
        && ($obj_node->dispatch_kind // '') eq 'method'
        && ($obj_node->name // '') eq 'new')
    {
        my $cls_node = $obj_node->inputs->[0];
        return defined $cls_node ? _class_name_from_class_node($cls_node) : undef;
    }
    # PadAccess to a variable holding a New — walk inputs
    if ($op eq 'PadAccess') {
        # Not yet supported in MOP: die to trigger diagnostic
        die "LLVM MOP: cannot infer class name from PadAccess — "
          . "method body self-reference via var not yet supported";
    }
    die "LLVM MOP: cannot infer class name from op=$op — expected New, Call(new), or PadAccess";
}

1;

# ---------------------------------------------------------------------------
# ElaboratedContext: a Context subclass that uses the Elaborate pass output
# for phi placement at Region merges. Placement is driven by the dominator tree
# and scoped value map computed by Chalk::IR::Schedule::Elaborate.
# ---------------------------------------------------------------------------
package Chalk::Target::LLVM::ElaboratedContext;
use 5.42.0;
use utf8;

use parent -norequire, 'Chalk::Target::LLVM::Context';

sub new {
    my ($class, %args) = @_;
    my $elab           = delete $args{elab};
    my $class_registry = delete $args{class_registry};
    my $self  = $class->SUPER::new(%args);
    $self->{elab} = $elab;
    # Class registry: maps class_name -> { methods => [...], fields => [...], parent => str }
    # Built by _scan_class_registry() in lower_with_elaboration.
    $self->{class_registry} = $class_registry // {};
    # Index emitted_phis by Region id -> list of phi records.
    # The Elaborate pass emits phis with block_id = the merge block id.
    # We need to look them up by the Region node's block id at emit time.
    $self->{elab_phi_by_block} = {};
    if (defined $elab) {
        for my $phi_rec ($elab->emitted_phis->@*) {
            push $self->{elab_phi_by_block}{ $phi_rec->{block_id} }->@*, $phi_rec;
        }
    }
    return $self;
}

# _process_if_node: elaboration-driven version.
# Reads phi records from the Elaborate pass for this Region's merge block.
sub _process_if_node {
    my ($self, $if_node) = @_;

    my $cond_input = $if_node->inputs->[1];
    die "LLVM backend (elaboration): If node has no condition (inputs[1] is undef)"
        unless defined $cond_input;

    my $cond_ref = $self->lower_value($cond_input);

    my $cond_repr = $cond_input->representation // 'Bool';
    if ($cond_repr eq 'Int') {
        my $bool_ref = $self->_fresh;
        $self->_emit("  $bool_ref = icmp ne i64 $cond_ref, 0  ; If (elab): coerce Int to i1");
        $cond_ref = $bool_ref;
    }

    my $then_label  = $self->_fresh_label('if.then.');
    my $else_label  = $self->_fresh_label('if.else.');
    my $merge_label = $self->_fresh_label('if.merge.');

    $self->_set_terminator("  br i1 $cond_ref, label %$then_label, label %$else_label  ; If (elab): branch");

    my $region = $if_node->region;

    # Snapshot var_table before any branch so each branch starts from the same
    # pre-branch state. This is required for correctness with nested control:
    # the then-branch may contain a nested If that updates var_table with an
    # inner-merge phi ref; the else-branch must see the pre-branch state, not the
    # post-then state. After both branches run, phi arms are taken from branch
    # snapshots (not from raw assignment nodes in the elab record), so a nested
    # If's merge phi ref is correctly propagated as the outer phi arm value.
    my %pre_var = %{ $self->{var_table} };

    # Process then-branch. var_table is mutated in place; snapshot after.
    $self->_new_block($then_label);
    $self->_process_branch_from_if($if_node, 0, $merge_label);
    my $then_end_label = $self->_current_block_label;
    my %then_var = %{ $self->{var_table} };

    # Restore to pre-branch state before processing else-branch.
    %{ $self->{var_table} } = %pre_var;

    # Process else-branch. var_table starts from pre-branch state.
    $self->_new_block($else_label);
    $self->_process_branch_from_if($if_node, 1, $merge_label);
    my $else_end_label = $self->_current_block_label;
    my %else_var = %{ $self->{var_table} };

    # Restore to pre-branch state before emitting merge phis. The merge block
    # will update var_table with phi results.
    %{ $self->{var_table} } = %pre_var;

    # Merge block.
    $self->_new_block($merge_label);

    # Emit phis from the elaboration plan for this merge block.
    # The Elaborate pass determines which variables diverge between branches and
    # records the merge block id (keyed as 'if.merge.<region_id>'). We look up
    # the exact key by region id (M1 fix: exact match, not substring regex, to
    # prevent Region#5 matching Region#59).
    if (defined $region) {
        my $phi_key = 'if.merge.' . $region->id;
        my $phi_recs = $self->{elab_phi_by_block}{$phi_key} // [];

        for my $phi_rec (@$phi_recs) {
            my $vd_id = $phi_rec->{vd_id};

            # Use var_table snapshots from each branch — NOT lower_value(arm->{value}).
            # lower_value on a raw assignment node emits a fresh instruction that does
            # not reflect nested merge phis. The snapshot holds the SSA ref LIVE AT
            # THE END of each branch: for a nested-if branch, that is the inner merge
            # phi ref; for a simple-assign branch, it is the assign's SSA ref.
            my $then_ref = $then_var{$vd_id};
            my $else_ref = $else_var{$vd_id};

            # Fall back to '0' only for truly uninit variables.
            $then_ref //= '0';
            $else_ref //= '0';

            # Look up the VarDecl repr for this phi.
            my $var_repr  = $self->{_vd_repr}{$vd_id} // 'Int';
            my $llvm_type = Chalk::Target::LLVM::Context::_repr_to_llvm_type($var_repr);

            my $phi_ref  = $self->_fresh;
            my $phi_line = "  $phi_ref = phi $llvm_type "
                         . "[ $then_ref, %$then_end_label ], "
                         . "[ $else_ref, %$else_end_label ]"
                         . "  ; elab phi (vd=$vd_id)";
            $self->_emit($phi_line);
            $self->{var_table}{$vd_id} = $phi_ref;
        }

        # Wire explicit Phi nodes on the Region.
        # Explicit Phi nodes (consumers of the Region) have their incoming values
        # lowered in the PREDECESSOR blocks, not in the merge block, so that
        # instructions appear before the phi in the correct block. We temporarily
        # re-enter the then/else tail blocks to emit the incoming-value instructions
        # (if not already cached), then return to the merge block.
        $self->_wire_region_phis_with_preblock(
            $region, $then_end_label, $else_end_label);
    }
}

# _wire_region_phis_with_preblock: emit explicit Phi nodes on a Region,
# ensuring each incoming value is lowered in its PREDECESSOR block (not the
# current/merge block). For each Phi consumer of the Region, we temporarily
# switch to the then/else tail block to emit the incoming-value instructions
# (if they are not already in cache), then switch back to the merge block to
# emit the phi instruction itself.
#
# This is required when a Phi's incoming value has not been pre-lowered during
# branch processing (e.g. a pure data node like Add that has no control_in
# and is not in the body chain). Emitting it from the merge block would place
# the instruction after the phi that references it — invalid in LLVM IR.
sub _wire_region_phis_with_preblock {
    my ($self, $region, $then_label, $else_label) = @_;

    my $consumers = $region->consumers // [];
    for my $phi_node (@$consumers) {
        next unless defined $phi_node && ref($phi_node);
        next unless $phi_node->can('operation') && $phi_node->operation eq 'Phi';
        next if exists $self->{cache}{ $phi_node->id };

        my $inputs = $phi_node->inputs;
        unless (defined $inputs && scalar @$inputs >= 2) {
            die "LLVM backend: Phi node (id=" . $phi_node->id . ") attached to Region "
              . "has fewer than 2 incoming values — missing predecessor edge";
        }

        # Lower incoming[0] in the then-tail block so the instruction precedes
        # the phi in the correct predecessor.
        my $merge_idx = $self->_find_block_idx($self->_current_block_label);
        my $then_idx  = $self->_find_block_idx($then_label);
        $self->{current_idx} = $then_idx;
        my $then_val = $self->lower_value($inputs->[0]);

        # Lower incoming[1] in the else-tail block.
        my $else_idx = $self->_find_block_idx($else_label);
        $self->{current_idx} = $else_idx;
        my $else_val = $self->lower_value($inputs->[1]);

        # Return to merge block to emit the phi instruction.
        $self->{current_idx} = $merge_idx;

        my $repr      = Chalk::Target::LLVM::Context::_require_repr($phi_node, 'ElaboratedContext.Region.Phi');
        my $llvm_type = Chalk::Target::LLVM::Context::_repr_to_llvm_type($repr);
        my $result    = $self->_fresh;
        $self->_emit("  $result = phi $llvm_type [ $then_val, %$then_label ], [ $else_val, %$else_label ]  ; Region phi");
        $self->{cache}{ $phi_node->id } = $result;
    }
}

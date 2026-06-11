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
    my ($class, $return_node, %opts) = @_;

    my $dom  = Chalk::IR::Schedule::Dominators->from_return_node($return_node);
    my $elab = Chalk::IR::Schedule::Elaborate->from_return_node($return_node, $dom);
    return $class->lower_with_elaboration($return_node, $elab, %opts);
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
# Class registry: built from the sealed MOP (019eb42a MOP-direct).
# ---------------------------------------------------------------------------

# _flatten_inheritance(\%registry) -> void
#
# Resolve :isa inheritance: for each class with a parent, copy inherited
# method slots from the parent into the child's vtable (compile-time MRO
# flatten). Run AFTER the registry is fully populated so all parent classes
# are present.
sub _flatten_inheritance {
    my ($registry) = @_;
    for my $cname (sort keys %$registry) {
        my $parent = $registry->{$cname}{parent};
        next unless defined $parent;
        my $parent_reg = $registry->{$parent};
        unless (defined $parent_reg) {
            die "LLVM MOP: class '$cname' has :isa($parent) but '$parent' is not declared in this graph";
        }
        # Copy parent methods into child that don't already exist in child
        for my $pmeth (@{ $parent_reg->{methods} }) {
            unless (grep { ($_->{name} // '') eq $pmeth->{name} } @{ $registry->{$cname}{methods} }) {
                push @{ $registry->{$cname}{methods} }, {
                    %$pmeth,
                    vtable_slot => scalar(@{ $registry->{$cname}{methods} }),
                    inherited_from => $parent,
                };
            }
        }
    }
    return;
}

# _build_registry_from_mop($mop) -> \%registry
#
# MOP-direct registry construction (019eb42a,
# docs/plans/2026-06-11-llvm-reads-mop-directly.md): read class structure
# from a SEALED Chalk::MOP — MOP::Class / MOP::Method / MOP::Field /
# MOP::Phaser::Adjust — instead of scanning the graph for ClassInfo
# metadata objects. Class structure is compile-time context resolved by
# name (Call.class_name), not dataflow. The implicit 'main' class (the
# program container seeded by Chalk::MOP's ADJUST) is skipped: it is never
# instantiated via Call(new).
sub _build_registry_from_mop {
    my ($mop) = @_;

    die "LLVM MOP: lower(mop => ...) requires a SEALED MOP — the registry "
      . "is a post-parse read surface and must not be built while "
      . "declare_* can still fire. Call \$mop->seal first."
        unless $mop->can('is_sealed') && $mop->is_sealed;

    my %registry;
    for my $cls (sort { $a->name cmp $b->name } $mop->classes) {
        next if $cls->name eq 'main';
        _populate_registry_from_mop_class(\%registry, $cls);
    }
    _flatten_inheritance(\%registry);
    return \%registry;
}

# _method_body_root($mop_method) -> $value_node
#
# The lowering root of a method body is its graph's Return value. The
# graph (+ its control chain) is the durable body shape — the MethodInfo
# body_node field and the MOP body arrayrefs are both transitional.
# Return inputs are [$value] (typed-factory shape) or [$ctrl, $value]
# (legacy Actions shape); the value is the LAST input either way.
sub _method_body_root {
    my ($mop_method) = @_;
    my $cname = $mop_method->class ? $mop_method->class->name : '?';
    my $returns = $mop_method->graph ? $mop_method->graph->returns : [];
    die "GAP: method '" . $mop_method->name . "' in class '$cname' has no "
      . "Return in its graph — cannot determine the lowering root. "
      . "Merge a Return(value) into the method's graph."
        unless $returns && @$returns;
    my $value = $returns->[0]->inputs->[-1];
    die "GAP: method '" . $mop_method->name . "' in class '$cname' has a "
      . "Return with no value input." unless defined $value;
    return $value;
}

# _phaser_body_in_control_order($phaser) -> \@statement_nodes
#
# ADJUST body statements from the phaser's graph, in control-chain order.
# Statements are the graph's statement-position members (the shared
# %STATEMENT_EFFECT_OPS table, plus VarDecl); order is recovered by
# following control_in links from the chain head. A single statement needs
# no threading; multiple statements REQUIRE it (an unordered body would
# lower nondeterministically — die instead).
sub _phaser_body_in_control_order {
    my ($phaser) = @_;
    my @stmts = grep {
        blessed($_) && $_->can('operation')
            && (exists $Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS{ $_->operation }
                || $_->operation eq 'VarDecl')
    } $phaser->graph->nodes->@*;
    return [] unless @stmts;
    return [@stmts] if @stmts == 1;

    my %is_member = map { $_->id => $_ } @stmts;
    my @heads = grep {
        my $c = $_->can('control_in') ? $_->control_in : undef;
        !(defined $c && blessed($c) && exists $is_member{ $c->id });
    } @stmts;
    die "GAP: ADJUST block has " . scalar(@stmts) . " statements but its "
      . "control chain does not order them (found " . scalar(@heads) . " "
      . "chain heads) — thread control_in in statement order."
        unless @heads == 1;

    my @ordered = ($heads[0]);
    my %placed  = ($heads[0]->id => 1);
    while (@ordered < @stmts) {
        my $tail = $ordered[-1];
        my ($next) = grep {
            !$placed{ $_->id }
                && defined $_->control_in
                && blessed($_->control_in)
                && $_->control_in->id eq $tail->id;
        } @stmts;
        die "GAP: ADJUST control chain is broken after statement "
          . $tail->id . " — thread control_in in statement order."
            unless defined $next;
        push @ordered, $next;
        $placed{ $next->id } = 1;
    }
    return \@ordered;
}

# _populate_registry_from_mop_class(\%registry, $mop_class) -> void
#
# The MOP-direct sibling of _populate_registry_from_classinfo: produces the
# same registry record shape from a sealed MOP::Class so downstream emission
# (_emit_class_registry_ir) is unchanged.
sub _populate_registry_from_mop_class {
    my ($registry, $cls) = @_;
    my $cname = $cls->name;
    $registry->{$cname} //= { methods => [], fields => [], adjusts => [], parent => undef };
    $registry->{$cname}{parent} //= $cls->parent_name;

    my $mslot = scalar @{ $registry->{$cname}{methods} };

    for my $m ($cls->methods) {
        my $mname     = $m->name;
        my $body_node = _method_body_root($m);
        my $ret_repr  = $m->return_type
            // _require_repr($body_node, "MOP::Method '$mname' body root");
        unless (grep { ($_->{name} // '') eq $mname } @{ $registry->{$cname}{methods} }) {
            push @{ $registry->{$cname}{methods} }, {
                name        => $mname,
                body_node   => $body_node,
                return_repr => $ret_repr,
                vtable_slot => $mslot++,
            };
        }
    }

    for my $mf ($cls->fields) {
        my $fname       = $mf->name;
        my $fidx        = $mf->fieldix;
        my $f_repr      = $mf->type
            // die "GAP: field '$fname' in class '$cname' has no declared repr "
                 . "(type) — refusing to silently default to Int.";
        unless (grep { ($_->{field_index} // -1) == $fidx } @{ $registry->{$cname}{fields} }) {
            push @{ $registry->{$cname}{fields} }, {
                name         => $fname,
                field_index  => $fidx,
                is_param     => $mf->is_param    // false,
                has_reader   => $mf->has_reader  // false,
                has_default  => $mf->has_default // false,
                default_node => $mf->default_value,
                field_repr   => $f_repr,
            };
        }
        if ($mf->has_reader) {
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

    for my $phaser ($cls->adjust_blocks) {
        push @{ $registry->{$cname}{adjusts} }, {
            body_nodes => _phaser_body_in_control_order($phaser),
        };
    }
    return;
}

# _render_context_blocks($ctx, $skip_first_label) -> @llvm_lines
#
# Render a lowering context's basic blocks, with the block that was CURRENT
# at end of lowering rendered LAST: epilogue lines (printf/ret) attach
# textually to the final rendered block and must close the block holding
# the result value. Multi-block phi arms append continuation blocks after
# the merge block, so creation order does not guarantee the current block
# is last. Block order is otherwise semantically irrelevant in LLVM IR,
# except that the entry block must stay first — the current block at end
# of lowering is never the entry block when later blocks exist (fallback
# preserves creation order if it ever were). $skip_first_label suppresses
# block 0's label for callers that emit their own 'entry:' line.
sub _render_context_blocks {
    my ($ctx, $skip_first_label) = @_;
    my @lines;
    my $blocks = $ctx->blocks;
    my $final_idx = $ctx->{current_idx} // $#$blocks;
    $final_idx = $#$blocks if $final_idx == 0 && $#$blocks > 0;
    for my $i ((grep { $_ != $final_idx } 0 .. $#$blocks), $final_idx) {
        my $block = $blocks->[$i];
        unless ($skip_first_label && $i == 0) {
            push @lines, $block->{label} . ':';
        }
        push @lines, $block->{insts}->@*;
        if (defined $block->{terminator}) {
            push @lines, $block->{terminator};
        }
    }
    return @lines;
}

# _propagate_need_flags($dst_ctx, $src_ctx)
#
# Copy ALL _need_* helper/declaration flags from a body-lowering context up
# to the main context. The prologue is assembled before bodies are lowered
# and reads these flags from the main ctx; a flag set only on a body ctx
# would be invisible to it, producing .ll that references undeclared
# globals/helpers (the F6 bug class).
my @NEED_FLAGS = qw(
    _need_malloc_memcpy
    _need_strpair
    _need_bool_str_globals
    _need_str_to_num_helper
    _need_memcmp
    _need_aggregate_types
    _need_getenv
);

sub _propagate_need_flags {
    my ($dst_ctx, $src_ctx) = @_;
    for my $flag (@NEED_FLAGS) {
        $dst_ctx->{$flag} = 1 if $src_ctx->{$flag};
    }
}

# _render_str_globals($body_ctx) -> @llvm_lines
#
# Emit string-constant globals accumulated by a body-lowering context.
# They cannot go in the main prologue (already emitted); the caller places
# them in the class section near the function that references them.
sub _render_str_globals {
    my ($body_ctx) = @_;
    my @lines;
    if (defined $body_ctx->{_str_globals} && @{ $body_ctx->{_str_globals} }) {
        for my $g (@{ $body_ctx->{_str_globals} }) {
            my ($gname, $content, $blen) = @$g;
            my $total = $blen + 1;
            my $enc = _encode_c_string($content);
            push @lines, "$gname = private unnamed_addr constant [$total x i8] c\"$enc\\00\", align 1";
        }
    }
    return @lines;
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

            # Emit all instructions from the body context (current block
            # renders last; the ret lines below attach textually to it).
            push @lines, _render_context_blocks($body_ctx, 1);

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

            # Propagate _need_* flags to the main ctx (F6 bug class) and
            # emit the body's string-constant globals into the class section.
            _propagate_need_flags($ctx, $body_ctx);
            push @lines, _render_str_globals($body_ctx);
        }

        # 4b. ADJUST function: one @Cls__ADJUST(i8* %self) per class with
        # ADJUST blocks, lowered ONCE in a fresh context exactly like a
        # method body. Call(new) calls it after :param/default binding.
        # Lowering ADJUST bodies inline on the main context (the old shape)
        # shared the main value cache across constructions: the second new
        # of the same class cache-hit the body's statement nodes and
        # silently skipped the second object's stores (review I6).
        my $adjusts = $reg->{adjusts} // [];
        my @adjust_stmts = map { @{ $_->{body_nodes} // [] } } @$adjusts;
        if (@adjust_stmts) {
            my $adj_ctx = Chalk::Target::LLVM::Context->new;
            $adj_ctx->{_in_method_body}     = 1;
            $adj_ctx->{_method_self_name}   = '%self';
            $adj_ctx->{_method_class_name}  = $cname;
            $adj_ctx->{_method_name}        = '__ADJUST';
            $adj_ctx->{class_registry}      = $registry;
            $adj_ctx->{_need_strpair}       = $ctx->{_need_strpair} // 0;

            $adj_ctx->lower_value($_) for @adjust_stmts;

            push @lines, "define internal void \@${cname}__ADJUST(i8* %self) {  ; ADJUST blocks for $cname";
            push @lines, 'entry:';
            push @lines, _render_context_blocks($adj_ctx, 1);
            push @lines, '  ret void';
            push @lines, '}';
            push @lines, '';

            # Same flag/global propagation as the method-body loop above.
            _propagate_need_flags($ctx, $adj_ctx);
            push @lines, _render_str_globals($adj_ctx);
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
    my ($class, $return_node, $elab, %opts) = @_;

    # Build the class registry that drives class-type declarations, vtable
    # globals, and method body emission — all of which must appear BEFORE
    # @main in the LLVM module.
    #
    # MOP-direct (019eb42a): class structure reaches the backend ONLY as a
    # sealed Chalk::MOP via mop => $mop; Call nodes name their class via the
    # class_name attribute. Without a mop the registry is empty — a
    # class_name Call then fails the registry lookup loudly. (The retired
    # ClassInfo bridge used to scan the graph for metadata objects riding
    # as node inputs.)
    my $class_registry = defined $opts{mop}
        ? _build_registry_from_mop($opts{mop})
        : {};

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

    # Declare getenv (+ strlen for the runtime value length) when EnvRead was
    # emitted. Plain C host-interface functions — NOT libperl.
    if ($ctx->{_need_getenv}) {
        push @lines, 'declare i8* @getenv(i8* nocapture readonly)';
        push @lines, 'declare i64 @strlen(i8* nocapture readonly)';
        $ctx->{_strlen_declared} = 1;
        $ctx->{_getenv_emitted}  = 1;
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
        unless ($ctx->{_strlen_declared}) {
            push @lines, 'declare i64 @strlen(i8* nocapture readonly)';
            $ctx->{_strlen_declared} = 1;
        }
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

    # Post-class re-emit for _need_getenv (same F6 pattern as memcmp): a
    # method-body EnvRead sets the flag after the prologue ran.
    if ($ctx->{_need_getenv} && !$ctx->{_getenv_emitted}) {
        push @lines, 'declare i8* @getenv(i8* nocapture readonly)';
        push @lines, 'declare i64 @strlen(i8* nocapture readonly)'
            unless $ctx->{_strlen_declared};
        $ctx->{_strlen_declared} = 1;
        $ctx->{_getenv_emitted}  = 1;
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

    # Current block renders last: the epilogue lines below (printf + ret)
    # attach textually to the final rendered block.
    push @lines, _render_context_blocks($ctx, 0);

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

# Ops that LOAD from a mutable memory location when lowered: a pad slot
# (PadAccess reads var_table), an aggregate element (Subscript), or an object
# field (FieldAccess). Their lowered value is program-point-dependent — a
# later store changes what an identical load returns — so they must re-lower
# at every consumption point, never serve from the value cache.
my %MUTABLE_READ_OPS = map { $_ => 1 } qw(PadAccess Subscript FieldAccess);

# Pure value ops the staleness predicate descends THROUGH: a pure node over a
# mutable-location read is itself program-point-dependent (Add(PadAccess, 10)
# after a reassign must re-read). The walk stops at everything else — side
# effects (Assign/Call/RegexMatch/...) execute once at their control position
# and their result SSA ref is fixed; Phi/Constant/VarDecl/ArrayRef/HashRef
# likewise produce a fixed SSA value at a single program point.
my %PURE_DESCEND_OPS = map { $_ => 1 } qw(
    Add Subtract Multiply Divide Modulo Power Concat
    NumEq NumNe NumLt NumGt NumLe NumGe NumCmp
    StrEq StrNe StrLt StrGt StrLe StrGe StrCmp
    And Or DefinedOr Xor Not Negate Complement Defined UnaryPlus
    BitAnd BitOr BitXor LeftShift RightShift
    Coerce Stringify Interpolate Length PostfixDeref Ref TernaryExpr
    Repeat Range IsaOp Slice
);

# _reads_mutable_location($node) -> bool
# True when lowering $node (or any pure node it transitively feeds on)
# performs a mutable-location load — i.e. when a cached SSA ref for it can
# go stale across a store (whole-branch review C1/C2). Structural property
# of the graph, so memoized per node id for the lifetime of this lowering.
sub _reads_mutable_location {
    my ($self, $node) = @_;
    my $id = $node->id();
    return $self->{_mut_read_memo}{$id}
        if exists $self->{_mut_read_memo}{$id};

    my $op = $node->operation();
    my $result = 0;
    if (exists $MUTABLE_READ_OPS{$op}) {
        $result = 1;
    }
    elsif (exists $PURE_DESCEND_OPS{$op}) {
        # Seed the memo before descending so an unexpected cycle terminates
        # (pure-op cycles do not occur; Phi backedges stop above).
        $self->{_mut_read_memo}{$id} = 0;
        INPUT: for my $input ($node->inputs()->@*) {
            my @flat = (ref($input) eq 'ARRAY') ? $input->@* : ($input);
            for my $el (@flat) {
                next unless defined $el && blessed($el);
                if ($self->_reads_mutable_location($el)) {
                    $result = 1;
                    last INPUT;
                }
            }
        }
    }
    return $self->{_mut_read_memo}{$id} = $result;
}

# lower_value($node) -> $llvm_ref (a string like "%tmp_1" or "1" for constants)
# Recursively lowers the data sub-graph rooted at $node, accumulating
# LLVM IR instructions into the current basic block. Returns the LLVM value
# reference (SSA name or immediate) for the node's result.
sub lower_value {
    my ($self, $node) = @_;

    # Cache: if we already lowered this node (hash-cons sharing), reuse the
    # previously computed SSA ref — except for nodes that read mutable
    # locations (directly or through pure ops).
    #
    # Such nodes are EXCLUDED from the cache-hit path: they must read the
    # current state at the moment they are lowered. var_table is updated by
    # Assign (and by phi emission at merge points), and aggregate elements /
    # object fields are updated by element/field stores, so a load for a
    # mutated location must see the post-store value, not a cached pre-store
    # SSA ref. Bypassing the cache ensures every such node re-lowers and is
    # always program-point-correct. See t/bootstrap/ir/llvm-reassign-soundness.t
    # for the adversarial proof of the PadAccess/var_table model across
    # straight-line, branch, and loop shapes, and
    # t/bootstrap/ir/llvm-stale-value-cache.t for the pure-over-read and
    # element/field store cases. Side-effecting ops STAY cached: they execute
    # once at their control position; re-lowering would double the effect.
    my $id = $node->id();
    my $op = $node->operation();
    if (exists $self->{cache}{$id} && !$self->_reads_mutable_location($node)) {
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
    # inputs[0] = invocant (obj node); the class rides as the class_name attr.
    # name = method name. return repr from node->representation.
    elsif ($op eq 'Call' && $node->can('dispatch_kind') && ($node->dispatch_kind // '') eq 'method') {
        return $self->_lower_call_method($node);
    }
    # RegexMatch: lower a literal pattern to a runtime-free matcher (G6).
    # inputs[0] = subject (Str, i8* + tracked len); pattern is a compile-time
    # literal attr. Produces an i1 matched? (Bool repr).
    elsif ($op eq 'RegexMatch') {
        return $self->_lower_regex_match($node);
    }
    # RegexSubst: s/// = match + splice (prefix + replacement(+$N) + suffix).
    # Produces the result string (i8*, runtime length in _str_len_table).
    elsif ($op eq 'RegexSubst') {
        return $self->_lower_regex_subst($node);
    }
    # Match (=~ with a compiled-regex VALUE, i.e. qr//): the rhs is a
    # Constant(const_type='regex') whose pattern is compile-time known; the
    # lowering resolves it statically and inlines the same matcher.
    elsif ($op eq 'Match') {
        return $self->_lower_match_apply($node);
    }
    # RegexCapture ($N magic var): a slot of the match node's result — a
    # zero-copy {ptr,len} view into the subject at the captured offsets.
    elsif ($op eq 'RegexCapture') {
        return $self->_lower_regex_capture($node);
    }
    # EnvRead (%ENV{key}): host process state via the C getenv — not libperl.
    elsif ($op eq 'EnvRead') {
        return $self->_lower_env_read($node);
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
        # Sanitize the comment text: a control byte (e.g. a newline in the
        # string value) would split the IR line and break the module.
        (my $val_cmt = $val) =~ s/[^\x20-\x7e]/./g;
        $self->_emit("  $ref = getelementptr inbounds [$total x i8], [$total x i8]* $gname, i64 0, i64 0  ; Constant(\"$val_cmt\", Str) -> i8* ptr");

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

    # Copy b's bytes (exactly len_b), then store the NUL explicitly. Copying
    # len_b+1 "to include the source NUL" is wrong for VIEW-typed inputs (a
    # RegexCapture points into the middle of its subject — the byte past the
    # view is the next subject byte, not NUL).
    $self->_emit("  call i8* \@memcpy(i8* $buf_b, i8* $rhs_ref, i64 $len_b)  ; Concat: copy rhs");
    my $nul_ptr = $self->_fresh;
    $self->_emit("  $nul_ptr = getelementptr inbounds i8, i8* $buf, i64 $len_sum  ; Concat: NUL slot");
    $self->_emit("  store i8 0, i8* $nul_ptr  ; Concat: NUL-terminate");

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
        if ($val_repr eq 'Str') {
            # Str field payload is a %StrPair* (as i64), mirroring _lower_call_new's
            # :param Str binding and the field READ path (which reads it back via
            # inttoptr i64 -> %StrPair*). A bare `add i64 0, <i8*>` would be invalid
            # IR and read back as a corrupt StrPair.
            my $len_ref  = $self->{_str_len_table}{$rhs_ref};
            my $pair_raw = $self->_fresh;
            my $pair_ptr = $self->_fresh;
            $self->_emit("  $pair_raw = call i8* \@malloc(i64 16)  ; alloc StrPair for FieldAccess-lvalue[$field_index]");
            $self->_emit("  $pair_ptr = bitcast i8* $pair_raw to %StrPair*  ; typed StrPair ptr");
            my $pp_gep = $self->_fresh;
            $self->_emit("  $pp_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 0  ; StrPair.ptr");
            $self->_emit("  store i8* $rhs_ref, i8** $pp_gep  ; store str ptr");
            my $pl_gep = $self->_fresh;
            $self->_emit("  $pl_gep = getelementptr inbounds %StrPair, %StrPair* $pair_ptr, i64 0, i32 1  ; StrPair.len");
            my $len_val = defined $len_ref ? $len_ref : 'zeroinitializer';
            if ($len_val eq 'zeroinitializer') {
                $len_val = $self->_fresh;
                $self->_emit("  $len_val = call i64 \@strlen(i8* $rhs_ref)  ; strlen for Str FieldAccess-lvalue[$field_index]");
            }
            $self->_emit("  store i64 $len_val, i64* $pl_gep  ; store str len");
            my $pair_as_i64 = $self->_fresh;
            $self->_emit("  $pair_as_i64 = ptrtoint %StrPair* $pair_ptr to i64  ; StrPair* -> i64 payload");
            $self->_emit("  store i64 $pair_as_i64, i64* $pay_gep  ; FieldAccess-lvalue[$field_index] Str payload = StrPair*");
            $self->{_need_strpair} = 1;
            $self->{cache}{ $node->id } = $rhs_ref;
            return $rhs_ref;
        }
        my $pay_i64 = $self->_fresh;
        if ($val_repr eq 'Bool') {
            $self->_emit("  $pay_i64 = zext i1 $rhs_ref to i64  ; Bool->i64 FieldAccess-lvalue");
        } elsif ($val_repr eq 'ArrayRef' || $val_repr eq 'HashRef') {
            # Pointer-repr value: ptrtoint before storing into the i64 payload slot,
            # mirroring the array/hash element-store branches.
            $self->_emit("  $pay_i64 = ptrtoint i8* $rhs_ref to i64  ; $val_repr ptr -> i64 FieldAccess-lvalue");
        } elsif ($val_repr eq 'Int') {
            $self->_emit("  $pay_i64 = add i64 0, $rhs_ref  ; identity: Int->i64 FieldAccess-lvalue");
        } else {
            die "GAP: Assign(FieldAccess-lvalue) rhs repr=$val_repr cannot be "
              . "stored in an i64 Slot payload (only Int/Bool/Str/ArrayRef/HashRef "
              . "are lowered) — refusing to emit invalid IR.";
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
            elsif ($rhs_repr eq 'Int') {
                $rhs_i64 = $rhs_ref;
            }
            else {
                die "GAP: Assign(Array-lvalue) rhs repr=$rhs_repr cannot be stored "
                  . "in an i64 Slot payload (only Int/ArrayRef/HashRef are lowered) "
                  . "— refusing to emit invalid IR.";
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
            elsif ($wrhs_repr eq 'Int') {
                $wrhs_i64 = $rhs_ref;
            }
            else {
                die "GAP: Assign(Hash-lvalue) rhs repr=$wrhs_repr cannot be stored "
                  . "in an i64 Slot payload (only Int/ArrayRef/HashRef are lowered) "
                  . "— refusing to emit invalid IR.";
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

    my $header_label    = $self->_fresh_label('loop.header.');
    my $body_label      = $self->_fresh_label('loop.body.');
    my $exit_label      = $self->_fresh_label('loop.exit.');

    # ---- Lower init values in the preheader block ----
    # Each loop phi's inputs[0] is the initial value. Lower it NOW (while still
    # in the preheader block) so the SSA definition of the init value precedes
    # the phi instruction in the header block. If lowered after opening the
    # header, the init value's definition would appear after the phi that
    # references it — invalid LLVM IR (forward reference not allowed in phi).
    #
    # This happens BEFORE the preheader's terminator is set and BEFORE its
    # label is captured: a multi-block init value (bounds-checked Subscript,
    # And/Or, ternary) consumes the current block's terminator and opens
    # continuation blocks, so the block that actually falls through to the
    # header is whatever is current AFTER lowering.
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

    # Re-capture the preheader label (multi-block inits may have moved us),
    # then jump from the preheader tail to the loop header.
    my $preheader_label = $self->_current_block_label;
    $self->_set_terminator("  br label %$header_label  ; Loop: enter header");

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

    # Collect the backedge values for each phi.
    my %body_vars = %{ $self->{var_table} };

    # ---- Lower backedge values at the body tail ----
    # The backedge value (phi inputs[1], wired via set_backedge) may not be
    # pre-lowered by the body chain — and a multi-block backedge value
    # (bounds-checked Subscript etc.) consumes the current block's terminator
    # and opens continuation blocks. Lower BEFORE capturing the body-end
    # label and setting the back-edge branch, so the phi's incoming label
    # names the block that actually branches to the header.
    for my $rec (@phi_records) {
        $rec->{backedge_ref} =
            $self->_find_phi_backedge_value($rec->{node}, \%body_vars, $rec->{phi_ref});
    }

    my $body_end_label = $self->_current_block_label;

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
        my $backedge_ref = $rec->{backedge_ref};

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
        elsif ($elem_repr eq 'Int') {
            $elem_i64 = $elem_ref;
        }
        else {
            die "GAP: ArrayRef element[$i] repr=$elem_repr cannot be stored in an "
              . "i64 Slot payload (only Int/ArrayRef/HashRef are lowered) — "
              . "refusing to emit invalid IR.";
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
        elsif ($val_repr eq 'Int') {
            $val_i64 = $val_ref;
        }
        else {
            die "GAP: HashRef value[$i] repr=$val_repr cannot be stored in an "
              . "i64 Slot payload (only Int/ArrayRef/HashRef are lowered) — "
              . "refusing to emit invalid IR.";
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

# _lower_call_new($node) -> $llvm_ref
#
# Lowers a Call(dispatch_kind='method', name='new') node.
# This is the canonical form of the New node: malloc + vtable bind + :param binding.
# Inputs are the :param values; the class rides as the class_name attribute.
sub _lower_call_new {
    my ($self, $node) = @_;

    $self->{_need_aggregate_types} = 1;
    $self->{_need_malloc_memcpy}   = 1;

    # MOP-direct shape: inputs are ONLY the :param values — class structure
    # is registry context named by the class_name attribute, never an input.
    my $param_names = $node->can('param_names') ? ($node->param_names // []) : [];
    my $class_name  = $node->class_name
        // die "LLVM MOP: Call(new) has no class_name — the constructor must "
             . "name its statically-known class (019eb42a MOP-direct contract).";
    my $param_vals  = [ ($node->inputs // [])->@* ];

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
            # Only Int defaults are lowered (the :param binding path boxes Str
            # into a StrPair and ptrtoints refs — the default path does not yet;
            # a Str default stored as add i64 0,<i8*> was invalid IR. Tracked
            # follow-up: share the slot-payload store helper across :param/
            # default/FieldAccess-lvalue sites).
            die "GAP: field '$pname' default value repr=$def_repr is not lowered "
              . "(only Int defaults; Str/ref defaults are a tracked follow-up) — "
              . "refusing to emit invalid IR." if $def_repr ne 'Int';
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

    # ADJUST blocks: call the per-class @Cls__ADJUST function (emitted once
    # by _emit_class_registry_ir in its own fresh context). Lowering the
    # bodies inline here shared this context's value cache across
    # constructions — the second new of the same class cache-hit the body's
    # statement nodes and skipped its stores (review I6).
    my $adjusts = $reg->{adjusts} // [];
    if (grep { @{ $_->{body_nodes} // [] } } @$adjusts) {
        $self->_emit("  call void \@${class_name}__ADJUST(i8* $raw)  ; run ADJUST blocks");
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
# Inputs: the :param values for name='new'; inputs[0] = invocant for regular
# method calls. The class rides as the class_name attribute (MOP-direct).
sub _lower_call_method {
    my ($self, $node) = @_;

    my $method_name = $node->name;

    # Route constructor calls to the construction lowering.
    if ($method_name eq 'new') {
        return $self->_lower_call_new($node);
    }
    my $obj_node    = $node->inputs->[0];
    # MOP-direct shape: the class rides as the class_name attribute.
    my $class_name  = $node->class_name
        // die "LLVM MOP: Call(method) '$method_name' has no class_name — "
             . "method dispatch must name its statically-known class "
             . "(019eb42a MOP-direct contract).";
    my $result_repr = _require_repr($node, 'Call(method)');

    # Verify class and method are in the registry
    my $reg = $self->{class_registry}{$class_name}
        or die "LLVM MOP: Call(method) '$method_name' on undeclared class '$class_name' — "
             . "the class is not in the sealed MOP handed to lower(). Cannot emit vtable slot.";

    my $methods = $reg->{methods} // [];
    my ($minfo) = grep { ($_->{name} // '') eq $method_name } @$methods;
    unless (defined $minfo) {
        die "LLVM MOP: Call(method) '$method_name' is absent from class '$class_name' vtable — "
          . "available methods: [" . join(', ', map { $_->{name} // '?' } @$methods) . "]. "
          . "Cannot emit vtable dispatch to a non-existent slot.";
    }

    # ABI cross-check: the call site is cast per the NODE's repr while the
    # vtable function was DEFINED per the registry's return_repr. The i8*
    # fn-ptr bitcast means lli ACCEPTS a mismatch — the silent-garbage
    # channel (branch-review I4). Die loudly instead.
    my $abi_repr = $minfo->{return_repr} // 'Int';
    if ($result_repr ne $abi_repr) {
        die "GAP: Call(method) '$method_name' node repr=$result_repr disagrees "
          . "with class '$class_name' vtable ABI return_repr=$abi_repr — "
          . "a mismatched indirect call would be silently wrong.";
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

# _lower_ref_of_object($node) -> $llvm_ref (Str: ptr to class-name string)
#
# Lowers ref($obj) where obj has repr=Object. Returns the class-name string
# pointer (i8*) and tracks the compile-time-known length in _str_len_table.
sub _lower_ref_of_object {
    my ($self, $node) = @_;

    my $obj_node = $node->inputs->[0];

    # Walk obj_node back to the constructing Call(new) for its class_name.
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

# ---------------------------------------------------------------------------
# Regex sub-compiler (G6): lower a literal pattern to a runtime-free matcher.
#
# The pattern is a compile-time-known literal string (RegexMatch->pattern), so
# the matcher is emitted as straight-line LLVM with NO libperl / perl regex
# engine. The subject rides on the G3 Str representation (i8* ptr + a length
# tracked in _str_len_table).
#
# Emission style (per the G6 spike): a shared outer "try each start offset"
# slide loop wrapping a straight-line per-pattern inner recognizer. For T0 the
# recognizer is an unrolled literal byte comparison; later tranches grow the
# recognizer (anchors collapse the slide loop, classes/quantifiers/captures
# extend the inner body) without changing this scaffold.
# ---------------------------------------------------------------------------

# _compile_regex_pattern($pattern, $flags) -> \%compiled
#
# Parse a literal regex pattern into the compiled form the emitter consumes:
# a sequence of one-byte ATOMS plus anchor flags. Atom kinds:
#   { kind => 'lit',   byte => $ord }                  — exact byte
#   { kind => 'class', neg => 0|1, ranges => [[lo,hi],...] }
#                                                      — byte in (or not in)
#                                                        any of the ranges
#                                                        (singles are [b,b])
#   { kind => 'any' }                                  — . (any byte but \n)
# Shorthands \d \w \s (and \D \W \S) desugar to classes; a backslash escape
# of a metachar (\. \[ \$ ...) is a literal byte. T3 adds per-atom quantifiers.
# Byte escapes the G6 sub-compiler resolves (regex-language escapes).
my %REGEX_ESCAPE_BYTE = (
    t => 0x09, n => 0x0A, r => 0x0D, f => 0x0C, a => 0x07, e => 0x1B, '0' => 0x00,
);

# _regex_escape_byte(\@chars, $idx, $pattern) -> ($byte, $consumed)
#
# Resolve a backslash escape; $idx is the char AFTER the backslash. Returns
# the byte value and how many pattern chars were consumed (1, or 3 for \xHH).
# Escaped punctuation is the literal byte; \t \n \r \f \a \e \0 map to their
# control bytes; \xHH parses two hex digits. Assertion and unknown
# ALPHANUMERIC escapes (\b \B \A \z \Z \G \p \N \c ...) DIE LOUDLY — perl
# reserves them, so matching the literal letter would be a silent miscompile.
sub _regex_escape_byte {
    my ($chars, $idx, $pattern) = @_;
    my $e = $chars->[$idx];
    if ($e !~ /[A-Za-z0-9]/) {
        return (ord($e), 1);                # \. \[ \$ \\ \/ ...
    }
    if (exists $REGEX_ESCAPE_BYTE{$e}) {
        return ($REGEX_ESCAPE_BYTE{$e}, 1); # \t \n \r \f \a \e \0
    }
    if ($e eq 'x') {
        my $hex = join '', grep { defined } @{$chars}[ $idx + 1, $idx + 2 ];
        die "GAP: malformed \\x escape in regex pattern '$pattern' "
          . "(need two hex digits)" unless $hex =~ /^[0-9A-Fa-f]{2}$/;
        return (hex($hex), 3);
    }
    die "GAP: regex escape \\$e in pattern '$pattern' not supported by the G6 "
      . "sub-compiler (assertions \\b \\B \\A \\z \\Z \\G and classes \\p \\N "
      . "are pending tranches — refusing to silently match a literal '$e')";
}

sub _compile_regex_pattern {
    my ($pattern, $flags) = @_;

    # No flag is implemented yet; silently ignoring one (e.g. /i compiling a
    # case-sensitive matcher, /x treating whitespace as literal atoms) would
    # be a silent miscompile. One gate here covers m//, qr//, and s///.
    die "GAP: regex flags '$flags' not yet supported by the G6 sub-compiler"
        if length($flags // '');

    # T1 anchors: a leading ^ anchors the match at offset 0; a trailing $
    # anchors the match end at the subject length (or before a final newline,
    # perl semantics). They are not literal bytes. A trailing escaped \$ is a
    # literal dollar — the $ is an anchor only when preceded by an EVEN run of
    # backslashes (\\$ = escaped backslash THEN anchor; \$ = literal dollar).
    my $anchored_start = 0;
    my $anchored_end   = 0;
    if ($pattern =~ /^\^/) {
        $anchored_start = 1;
        $pattern =~ s/^\^//;
    }
    if ($pattern =~ /(\\*)\$$/ && length($1) % 2 == 0) {
        $anchored_end = 1;
        $pattern =~ s/\$$//;
    }

    # Shorthand class definitions (byte ranges).
    my %SHORTHAND = (
        d => [ [ord('0'), ord('9')] ],
        w => [ [ord('0'), ord('9')], [ord('A'), ord('Z')], [ord('a'), ord('z')],
               [ord('_'), ord('_')] ],
        s => [ [0x09, 0x0D], [ord(' '), ord(' ')] ],   # \t \n \v \f \r space
    );

    my @atoms;
    my @paren_stack;   # open-group cap indices (undef = non-capturing)
    my $ngroups = 0;   # capture group counter
    my @chars = split //, $pattern;
    my $i = 0;
    while ($i <= $#chars) {
        my $c = $chars[$i];

        if ($c eq '\\') {
            # Escape: shorthand class, byte escape, or literal punctuation.
            my $e = $chars[ $i + 1 ]
                // die "GAP: regex pattern '$pattern' ends with a bare backslash";
            if ($e =~ /^[dwsDWS]$/) {
                push @atoms, {
                    kind   => 'class',
                    neg    => ($e =~ /[DWS]/) ? 1 : 0,
                    ranges => $SHORTHAND{ lc $e },
                };
                $i += 2;
                next;
            }
            my ($byte, $used) = _regex_escape_byte(\@chars, $i + 1, $pattern);
            push @atoms, { kind => 'lit', byte => $byte };
            $i += 1 + $used;
            next;
        }

        if ($c eq '[') {
            # Character class: [^? ... ] with ranges and escapes.
            my $j   = $i + 1;
            my $neg = 0;
            if (($chars[$j] // '') eq '^') { $neg = 1; $j++ }
            my @ranges;
            my $first = 1;   # a ] as the FIRST member is a literal ]
            while ($j <= $#chars) {
                my $cc = $chars[$j];
                last if $cc eq ']' && !$first;
                $first = 0;
                # Shorthand expansion inside the class: [\d_] etc.
                if ($cc eq '\\') {
                    my $e = $chars[ $j + 1 ]
                        // die "GAP: regex class in '$pattern' ends with a bare backslash";
                    if ($e =~ /^[dwsDWS]$/) {
                        die "GAP: regex class shorthand \\$e inside [...] not yet supported "
                          . "in pattern '$pattern'" if $e =~ /[DWS]/;
                        push @ranges, $SHORTHAND{ lc $e }->@*;
                        $j += 2;
                        next;
                    }
                }
                # One endpoint: a plain char or a resolved escape byte.
                my ($lo, $lo_used);
                if ($cc eq '\\') {
                    ($lo, $lo_used) = _regex_escape_byte(\@chars, $j + 1, $pattern);
                    $lo_used += 1;   # the backslash itself
                }
                else {
                    ($lo, $lo_used) = (ord($cc), 1);
                }
                my $k = $j + $lo_used;
                # Range lo-hi (a dash that is not the last member)?
                if (($chars[$k] // '') eq '-' && ($chars[ $k + 1 ] // ']') ne ']') {
                    my ($hi, $hi_used);
                    if ($chars[ $k + 1 ] eq '\\') {
                        ($hi, $hi_used) = _regex_escape_byte(\@chars, $k + 2, $pattern);
                        $hi_used += 1;
                    }
                    else {
                        ($hi, $hi_used) = (ord($chars[ $k + 1 ]), 1);
                    }
                    # Perl rejects a descending range at compile time; matching
                    # nothing silently would be a miscompile.
                    die "GAP: invalid [] range (lo > hi) in regex pattern '$pattern'"
                        if $lo > $hi;
                    push @ranges, [ $lo, $hi ];
                    $j = $k + 1 + $hi_used;
                    next;
                }
                push @ranges, [ $lo, $lo ];
                $j = $k;
            }
            die "GAP: unterminated character class in regex pattern '$pattern'"
                unless ($chars[$j] // '') eq ']';
            push @atoms, { kind => 'class', neg => $neg, ranges => \@ranges };
            $i = $j + 1;
            next;
        }

        if ($c eq '.') {
            push @atoms, { kind => 'any' };
            $i++;
            next;
        }

        # Capture groups (T4): zero-width gopen/gclose markers around the
        # enclosed atoms. (?:...) is non-capturing (markers with cap undef —
        # transparent without alternation, but tracked so ')' pairs up).
        # Quantified groups ((ab)+) are a pending tranche.
        if ($c eq '(') {
            my $cap;
            if (($chars[$i+1] // '') eq '?' && ($chars[$i+2] // '') eq ':') {
                $cap = undef;     # non-capturing
                $i += 3;
            }
            elsif (($chars[$i+1] // '') eq '?') {
                die "GAP: regex (?...) construct (lookaround/modifier/code) in "
                  . "pattern '$pattern' not supported";
            }
            else {
                $cap = ++$ngroups;
                $i++;
            }
            push @atoms, { kind => 'gopen', cap => $cap };
            push @paren_stack, $cap;
            next;
        }
        if ($c eq ')') {
            die "GAP: unbalanced ')' in regex pattern '$pattern'"
                unless @paren_stack;
            my $cap = pop @paren_stack;
            push @atoms, { kind => 'gclose', cap => $cap };
            $i++;
            next;
        }

        # Quantifiers (T3): attach {min,max} to the PRECEDING atom. max undef
        # = unbounded. A quantifier with no preceding atom is malformed.
        if ($c =~ /[*+?{]/) {
            die "GAP: regex quantifier '$c' with no preceding atom in pattern '$pattern'"
                unless @atoms;
            my $atom = $atoms[-1];
            die "GAP: quantified group (...)$c in pattern '$pattern' not yet "
              . "supported by the G6 sub-compiler (tranche pending)"
                if $atom->{kind} eq 'gclose';
            die "GAP: regex quantifier '$c' directly after '(' in pattern '$pattern'"
                if $atom->{kind} eq 'gopen';
            die "GAP: double quantifier on one atom in pattern '$pattern' "
              . "(non-greedy *? +? ?? not yet supported)"
                if exists $atom->{min};
            if ($c eq '*') { $atom->{min} = 0; $atom->{max} = undef; $i++; next }
            if ($c eq '+') { $atom->{min} = 1; $atom->{max} = undef; $i++; next }
            if ($c eq '?') { $atom->{min} = 0; $atom->{max} = 1;     $i++; next }
            # {n} {n,} {n,m}
            my $rest = join '', @chars[ $i .. $#chars ];
            if ($rest =~ /^\{(\d+)(,(\d*))?\}/) {
                my ($n, $has_comma, $m) = ($1, defined $2, $3);
                $atom->{min} = 0 + $n;
                $atom->{max} = $has_comma ? (length($m // '') ? 0 + $m : undef) : 0 + $n;
                die "GAP: regex {n,m} with m < n in pattern '$pattern'"
                    if defined $atom->{max} && $atom->{max} < $atom->{min};
                $i += length($&);
                next;
            }
            die "GAP: malformed regex counted quantifier near '"
              . substr($rest, 0, 8) . "' in pattern '$pattern'";
        }

        # Unsupported metachars die loudly rather than silently matching as
        # literals (alternation arrives in T5). Mid-pattern ^/$ are perl
        # ASSERTIONS (usually unmatchable without /m) — matching them as
        # literal bytes would silently diverge.
        if ($c =~ /[}|^\$]/) {
            die "GAP: regex metachar '$c' in pattern '$pattern' not yet supported "
              . "by the G6 sub-compiler (tranche pending; mid-pattern ^/\$ are "
              . "assertions, not literals)";
        }

        push @atoms, { kind => 'lit', byte => ord($c) };
        $i++;
    }

    die "GAP: unbalanced '(' in regex pattern '$pattern'" if @paren_stack;

    return {
        atoms          => \@atoms,
        anchored_start => $anchored_start,
        anchored_end   => $anchored_end,
        ngroups        => $ngroups,
    };
}

# _emit_atom_predicate($self, $atom, $byte_ref, $label) -> $i1_ref
#
# Emit the LLVM predicate for one atom against an already-loaded subject byte.
# Returns the i1 SSA ref that is true iff the byte satisfies the atom.
sub _emit_atom_predicate {
    my ($self, $atom, $byte_ref, $label) = @_;

    if ($atom->{kind} eq 'lit') {
        my $eq = $self->_fresh;
        my $ch = $atom->{byte} >= 0x20 && $atom->{byte} <= 0x7e ? chr($atom->{byte}) : sprintf('\\x%02x', $atom->{byte});
        $self->_emit("  $eq = icmp eq i8 $byte_ref, $atom->{byte}  ; $label: byte == '$ch'?");
        return $eq;
    }

    if ($atom->{kind} eq 'any') {
        # Perl . matches any byte except newline (no /s in the supported slice).
        my $ne = $self->_fresh;
        $self->_emit("  $ne = icmp ne i8 $byte_ref, 10  ; $label: . (any byte but \\n)");
        return $ne;
    }

    if ($atom->{kind} eq 'class') {
        # OR over ranges: (b >= lo && b <= hi) || ...
        my $acc;
        for my $r ($atom->{ranges}->@*) {
            my ($lo, $hi) = @$r;
            my $in;
            if ($lo == $hi) {
                $in = $self->_fresh;
                $self->_emit("  $in = icmp eq i8 $byte_ref, $lo  ; $label: class member $lo");
            }
            else {
                my $ge = $self->_fresh;
                my $le = $self->_fresh;
                $in = $self->_fresh;
                $self->_emit("  $ge = icmp uge i8 $byte_ref, $lo  ; $label: class range lo");
                $self->_emit("  $le = icmp ule i8 $byte_ref, $hi  ; $label: class range hi");
                $self->_emit("  $in = and i1 $ge, $le  ; $label: in [$lo-$hi]?");
            }
            if (!defined $acc) {
                $acc = $in;
            }
            else {
                my $or = $self->_fresh;
                $self->_emit("  $or = or i1 $acc, $in  ; $label: class union");
                $acc = $or;
            }
        }
        # Empty class [] matches nothing.
        if (!defined $acc) {
            $acc = $self->_fresh;
            $self->_emit("  $acc = add i1 false, false  ; $label: empty class never matches");
        }
        if ($atom->{neg}) {
            my $not = $self->_fresh;
            $self->_emit("  $not = xor i1 $acc, true  ; $label: negated class");
            return $not;
        }
        return $acc;
    }

    die "G6 internal: unknown regex atom kind '$atom->{kind}'";
}

# _emit_regex_seq($self, \@atoms, $idx, $pos_ref, \%ctx)
#
# Position-threaded recursive emission of atoms[$idx..]. $pos_ref is the SSA
# value of the current subject position. %ctx carries subj_ptr/subj_len/
# hit_lbl/fail_lbl/anch_e; fail_lbl is the CURRENT backtrack target (the
# innermost enclosing backoff decrementer, or the slide-advance block at the
# top level). Each atom is emitted exactly once; a quantified atom wraps the
# continuation (the recursive call) in a backoff loop, giving correct greedy
# backtracking via runtime loop structure rather than code duplication.
#
# Emission contract: called with a current open block; every path it emits
# ends in a terminator (br to hit/fail or into its own loop structure).
sub _emit_regex_seq {
    my ($self, $atoms, $idx, $pos_ref, $ctx) = @_;

    # Base: end of pattern. Record the whole-match end position (group 0),
    # check the end anchor, then hit. Perl's $ matches at the end of the
    # subject OR immediately before a FINAL newline ("foo\n" =~ /foo$/ is
    # true), so the anchor check is pos==len, or pos==len-1 with subj[pos]
    # being a newline (the load is branch-guarded: pos==len-1 implies
    # in-bounds).
    if ($idx > $#$atoms) {
        $ctx->{caps}{m0e} = $pos_ref;
        if ($ctx->{anch_e}) {
            my $lbl_chknl = $self->_fresh_label('rxenl');
            my $lbl_ldnl  = $self->_fresh_label('rxeld');
            my $at_end = $self->_fresh;
            $self->_emit("  $at_end = icmp eq i64 $pos_ref, $ctx->{subj_len}  ; RegexMatch \$: match ends at len?");
            $self->_set_terminator("  br i1 $at_end, label \%$ctx->{hit_lbl}, label \%$lbl_chknl");

            $self->_new_block($lbl_chknl);
            my $lenm1 = $self->_fresh;
            $self->_emit("  $lenm1 = sub i64 $ctx->{subj_len}, 1  ; RegexMatch \$: len-1");
            my $is_pre = $self->_fresh;
            $self->_emit("  $is_pre = icmp eq i64 $pos_ref, $lenm1  ; RegexMatch \$: just before the last byte?");
            $self->_set_terminator("  br i1 $is_pre, label \%$lbl_ldnl, label \%$ctx->{fail_lbl}");

            $self->_new_block($lbl_ldnl);
            my $gep = $self->_fresh;
            $self->_emit("  $gep = getelementptr inbounds i8, i8* $ctx->{subj_ptr}, i64 $pos_ref  ; RegexMatch \$: last byte ptr");
            my $byte = $self->_fresh;
            $self->_emit("  $byte = load i8, i8* $gep  ; RegexMatch \$: last byte");
            my $is_nl = $self->_fresh;
            $self->_emit("  $is_nl = icmp eq i8 $byte, 10  ; RegexMatch \$: final newline?");
            $self->_set_terminator("  br i1 $is_nl, label \%$ctx->{hit_lbl}, label \%$ctx->{fail_lbl}");
        }
        else {
            $self->_set_terminator("  br label \%$ctx->{hit_lbl}");
        }
        return;
    }

    my $atom  = $atoms->[$idx];

    # Capture-group boundary markers (T4): zero-width — record the current
    # position SSA as the group's start/end and continue. The records go into
    # the SHARED $ctx->{caps} hashref (ctx is shallow-copied at backoff
    # boundaries; the caps ref is shared by all copies). The recorded refs
    # dominate the recursion base (the linear chain), so they are valid at the
    # hit edge; on a backtracked retry the same SSA names hold the values of
    # the CURRENT (ultimately successful) attempt.
    if ($atom->{kind} eq 'gopen' || $atom->{kind} eq 'gclose') {
        if (defined $atom->{cap}) {
            my $slot = $atom->{kind} eq 'gopen' ? 's' : 'e';
            $ctx->{caps}{$slot}[ $atom->{cap} ] = $pos_ref;
        }
        $self->_emit_regex_seq($atoms, $idx + 1, $pos_ref, $ctx);
        return;
    }

    my $quant = exists $atom->{min};

    if (!$quant) {
        # Plain atom: bounds-check, load, predicate, advance position by one.
        my $lbl_ld = $self->_fresh_label('rxa');
        my $lbl_nx = $self->_fresh_label('rxn');
        my $inb = $self->_fresh;
        $self->_emit("  $inb = icmp ult i64 $pos_ref, $ctx->{subj_len}  ; RegexMatch atom[$idx]: in bounds?");
        $self->_set_terminator("  br i1 $inb, label \%$lbl_ld, label \%$ctx->{fail_lbl}");

        $self->_new_block($lbl_ld);
        my $gep = $self->_fresh;
        $self->_emit("  $gep = getelementptr inbounds i8, i8* $ctx->{subj_ptr}, i64 $pos_ref  ; RegexMatch atom[$idx]: byte ptr");
        my $byte = $self->_fresh;
        $self->_emit("  $byte = load i8, i8* $gep  ; RegexMatch atom[$idx]: subject byte");
        my $ok = $self->_emit_atom_predicate($atom, $byte, "RegexMatch atom[$idx]");
        my $pos_next = $self->_fresh;
        $self->_emit("  $pos_next = add i64 $pos_ref, 1  ; RegexMatch atom[$idx]: advance");
        $self->_set_terminator("  br i1 $ok, label \%$lbl_nx, label \%$ctx->{fail_lbl}");

        $self->_new_block($lbl_nx);
        $self->_emit_regex_seq($atoms, $idx + 1, $pos_next, $ctx);
        return;
    }

    # Quantified atom {min,max} (max undef = unbounded): greedy-consume loop
    # counts how many bytes the atom can take from $pos_ref, then a backoff
    # loop tries the continuation at count c = greedy, greedy-1, ..., min.
    my ($min, $max) = ($atom->{min}, $atom->{max});

    my $lbl_cur   = $self->_current_block_label;
    my $lbl_ghead = $self->_fresh_label('rxgh');   # greedy header (cnt phi)
    my $lbl_gtest = $self->_fresh_label('rxgt');   # greedy predicate test
    my $lbl_gbody = $self->_fresh_label('rxgb');   # greedy increment
    my $lbl_gdone = $self->_fresh_label('rxgd');   # greedy done
    my $lbl_bhead = $self->_fresh_label('rxbh');   # backoff header (c phi)
    my $lbl_bbody = $self->_fresh_label('rxbb');   # backoff continuation
    my $lbl_bdec  = $self->_fresh_label('rxbd');   # backoff decrement
    my $cnt_next  = $self->_fresh;                 # forward ref for ghead phi
    my $c_dec     = $self->_fresh;                 # forward ref for bhead phi

    $self->_set_terminator("  br label \%$lbl_ghead");

    # Greedy header: how many consumed so far; can we take one more?
    $self->_new_block($lbl_ghead);
    my $cnt = $self->_fresh;
    $self->_emit("  $cnt = phi i64 [ 0, \%$lbl_cur ], [ $cnt_next, \%$lbl_gbody ]  ; RegexMatch q[$idx]: greedy count");
    my $posg = $self->_fresh;
    $self->_emit("  $posg = add i64 $pos_ref, $cnt  ; RegexMatch q[$idx]: greedy pos");
    my $inb = $self->_fresh;
    $self->_emit("  $inb = icmp ult i64 $posg, $ctx->{subj_len}  ; RegexMatch q[$idx]: in bounds?");
    my $more = $inb;
    if (defined $max) {
        my $ltmax = $self->_fresh;
        $self->_emit("  $ltmax = icmp ult i64 $cnt, $max  ; RegexMatch q[$idx]: below max $max?");
        my $and = $self->_fresh;
        $self->_emit("  $and = and i1 $inb, $ltmax  ; RegexMatch q[$idx]: may consume more?");
        $more = $and;
    }
    $self->_set_terminator("  br i1 $more, label \%$lbl_gtest, label \%$lbl_gdone");

    # Greedy test: does the atom match at posg?
    $self->_new_block($lbl_gtest);
    my $gep = $self->_fresh;
    $self->_emit("  $gep = getelementptr inbounds i8, i8* $ctx->{subj_ptr}, i64 $posg  ; RegexMatch q[$idx]: byte ptr");
    my $byte = $self->_fresh;
    $self->_emit("  $byte = load i8, i8* $gep  ; RegexMatch q[$idx]: subject byte");
    my $ok = $self->_emit_atom_predicate($atom, $byte, "RegexMatch q[$idx]");
    $self->_set_terminator("  br i1 $ok, label \%$lbl_gbody, label \%$lbl_gdone");

    # Greedy body: consume one and loop.
    $self->_new_block($lbl_gbody);
    $self->_emit("  $cnt_next = add i64 $cnt, 1  ; RegexMatch q[$idx]: consume");
    $self->_set_terminator("  br label \%$lbl_ghead");

    # Greedy done: enter the backoff loop with c = greedy count.
    $self->_new_block($lbl_gdone);
    $self->_set_terminator("  br label \%$lbl_bhead");

    # Backoff header: try the continuation at count c; give up below min.
    $self->_new_block($lbl_bhead);
    my $c = $self->_fresh;
    $self->_emit("  $c = phi i64 [ $cnt, \%$lbl_gdone ], [ $c_dec, \%$lbl_bdec ]  ; RegexMatch q[$idx]: backoff count");
    my $ge_min = $self->_fresh;
    $self->_emit("  $ge_min = icmp sge i64 $c, $min  ; RegexMatch q[$idx]: count >= min $min?");
    $self->_set_terminator("  br i1 $ge_min, label \%$lbl_bbody, label \%$ctx->{fail_lbl}");

    # Backoff body: the continuation at pos + c; its fail target is the
    # decrementer (back off one and retry), NOT the outer fail.
    $self->_new_block($lbl_bbody);
    my $posb = $self->_fresh;
    $self->_emit("  $posb = add i64 $pos_ref, $c  ; RegexMatch q[$idx]: continuation pos");
    my %inner_ctx = ( $ctx->%*, fail_lbl => $lbl_bdec );
    $self->_emit_regex_seq($atoms, $idx + 1, $posb, \%inner_ctx);

    # Backoff decrement: one fewer repetition, retry.
    $self->_new_block($lbl_bdec);
    $self->_emit("  $c_dec = sub i64 $c, 1  ; RegexMatch q[$idx]: back off");
    $self->_set_terminator("  br label \%$lbl_bhead");
    return;
}

# _emit_regex_matcher($self, $subj_ptr, $subj_len, $compiled, $tag) -> \%match
#
# Emit the full matcher (slide loop + position-threaded recognizer + end
# merge) for an already-compiled pattern. Returns the END-block SSA values:
#   matched — i1 (did the pattern match anywhere?)
#   m0s/m0e — i64 whole-match start/end offsets (0 on miss)
#   cap_s/cap_e — arrayrefs (1-based) of i64 capture-group offsets (0 on miss)
# Captures are plain SSA offset pairs into the subject buffer — no struct is
# materialized (a %MatchResult ABI is only needed at a function boundary,
# i.e. a future qr//-as-function; per the G6 scope decision it is not built).
sub _emit_regex_matcher {
    my ($self, $subj_ptr, $subj_len, $compiled, $tag) = @_;
    $tag //= 'RegexMatch';

    my @atoms    = $compiled->{atoms}->@*;
    my $anch_s   = $compiled->{anchored_start};
    my $anch_e   = $compiled->{anchored_end};
    my $ngroups  = $compiled->{ngroups} // 0;

    # Minimum bytes the pattern can match (sum of per-atom min counts;
    # zero-width group markers contribute nothing). Drives the slide-loop
    # room check; quantified atoms may consume more.
    my $min_len = 0;
    for my $a (@atoms) {
        next if $a->{kind} eq 'gopen' || $a->{kind} eq 'gclose';
        $min_len += ($a->{min} // 1);
    }

    # Empty pattern (possibly with anchors). The $ anchor's position honors
    # perl's final-newline rule: the effective end position is len-1 when the
    # last byte is a newline, else len (so s/$/X/ inserts BEFORE a trailing
    # newline, and /^$/ matches "\n").
    if (scalar @atoms == 0) {
        if ($anch_e) {
            # endpos = (len > 0 && subj[len-1] == '\n') ? len-1 : len
            my $lbl_pre   = $self->_current_block_label;
            my $lbl_ld    = $self->_fresh_label('rxeep');
            my $lbl_merge = $self->_fresh_label('rxeem');
            my $nonempty  = $self->_fresh;
            $self->_emit("  $nonempty = icmp ugt i64 $subj_len, 0  ; $tag: non-empty subject?");
            $self->_set_terminator("  br i1 $nonempty, label \%$lbl_ld, label \%$lbl_merge");

            $self->_new_block($lbl_ld);
            my $lenm1 = $self->_fresh;
            $self->_emit("  $lenm1 = sub i64 $subj_len, 1  ; $tag: len-1");
            my $gep = $self->_fresh;
            $self->_emit("  $gep = getelementptr inbounds i8, i8* $subj_ptr, i64 $lenm1  ; $tag: last byte ptr");
            my $byte = $self->_fresh;
            $self->_emit("  $byte = load i8, i8* $gep  ; $tag: last byte");
            my $is_nl = $self->_fresh;
            $self->_emit("  $is_nl = icmp eq i8 $byte, 10  ; $tag: trailing newline?");
            my $end_ld = $self->_fresh;
            $self->_emit("  $end_ld = select i1 $is_nl, i64 $lenm1, i64 $subj_len  ; $tag: \$ position");
            $self->_set_terminator("  br label \%$lbl_merge");

            $self->_new_block($lbl_merge);
            my $endpos = $self->_fresh;
            $self->_emit("  $endpos = phi i64 [ $end_ld, \%$lbl_ld ], [ 0, \%$lbl_pre ]  ; $tag: effective end (len==0 -> 0)");

            my $r = $self->_fresh;
            if ($anch_s) {
                # /^$/ matches iff the effective end is offset 0.
                $self->_emit("  $r = icmp eq i64 $endpos, 0  ; $tag /^\$/: empty (or lone-newline) subject?");
            }
            else {
                # /$/ always matches, at the effective end position.
                $self->_emit("  $r = add i1 true, false  ; $tag /\$/: always matches at the end");
            }
            my $m0 = $anch_s ? '0' : $endpos;
            return { matched => $r, m0s => $m0, m0e => $m0, cap_s => [], cap_e => [] };
        }

        # //, /^/ — match unconditionally at offset 0.
        my $r = $self->_fresh;
        $self->_emit("  $r = add i1 true, false  ; $tag: empty pattern always matches");
        return { matched => $r, m0s => '0', m0e => '0', cap_s => [], cap_e => [] };
    }

    # Slide loop: for start in 0 .. (len - min_len), try the pattern at start.
    my $lbl_pre   = $self->_current_block_label;
    my $lbl_head  = $self->_fresh_label('rxhead');
    my $lbl_try   = $self->_fresh_label('rxtry');
    my $lbl_cont  = $self->_fresh_label('rxcont');
    my $lbl_hit   = $self->_fresh_label('rxhit');
    my $lbl_miss  = $self->_fresh_label('rxmiss');
    my $lbl_end   = $self->_fresh_label('rxend');
    my $start_next = $self->_fresh;

    $self->_set_terminator("  br label \%$lbl_head");

    # Header: start phi + room check (start + min_len <= len).
    # With a start anchor (^), there is no back-edge from the continue block
    # (a failed try goes straight to miss), so the phi has only the entry edge.
    $self->_new_block($lbl_head);
    my $start = $self->_fresh;
    if ($anch_s) {
        $self->_emit("  $start = phi i64 [ 0, \%$lbl_pre ]  ; $tag ^: anchored at offset 0");
    }
    else {
        $self->_emit("  $start = phi i64 [ 0, \%$lbl_pre ], [ $start_next, \%$lbl_cont ]  ; $tag: slide start");
    }
    my $min_end = $self->_fresh;
    $self->_emit("  $min_end = add i64 $start, $min_len  ; $tag: start + min pattern length");
    my $room = $self->_fresh;
    $self->_emit("  $room = icmp sle i64 $min_end, $subj_len  ; $tag: room for pattern?");
    $self->_set_terminator("  br i1 $room, label \%$lbl_try, label \%$lbl_miss");

    # Try: position-threaded recursive emission of the atom sequence. Each
    # atom's code is emitted once; quantified atoms emit a greedy-consume loop
    # plus a backoff loop whose body holds the continuation, so backtracking
    # happens via loop structure at runtime (fail targets thread to the
    # innermost enclosing backoff; the outermost fail target is the slide
    # advance). The end-anchor check lives in the recursion base (pos == len).
    # The caps hashref is SHARED across the recursion's ctx copies; the seq
    # records group-boundary position SSA refs + the whole-match end into it.
    my %caps = ( s => [], e => [], m0e => undef );
    $self->_new_block($lbl_try);
    $self->_emit_regex_seq(\@atoms, 0, $start, {
        subj_ptr => $subj_ptr,
        subj_len => $subj_len,
        hit_lbl  => $lbl_hit,
        fail_lbl => $lbl_cont,
        anch_e   => $anch_e,
        caps     => \%caps,
    });

    # Continue: advance the start offset (or stop, if start-anchored).
    $self->_new_block($lbl_cont);
    $self->_emit("  $start_next = add i64 $start, 1  ; $tag: next start");
    if ($anch_s) {
        # Start anchor (^): only offset 0 is tried — a failed try means no match.
        $self->_set_terminator("  br label \%$lbl_miss");
    }
    else {
        $self->_set_terminator("  br label \%$lbl_head");
    }

    # Hit / miss feed the end-block phis.
    $self->_new_block($lbl_hit);
    $self->_set_terminator("  br label \%$lbl_end");
    $self->_new_block($lbl_miss);
    $self->_set_terminator("  br label \%$lbl_end");

    # End merge: matched + the whole-match and capture-group offsets. All the
    # recorded refs dominate the hit edge; miss feeds 0 sentinels (consumers
    # must guard on matched — perl leaves $N undef on a failed match).
    $self->_new_block($lbl_end);
    my $matched = $self->_fresh;
    $self->_emit("  $matched = phi i1 [ true, \%$lbl_hit ], [ false, \%$lbl_miss ]  ; $tag: matched?");
    my $m0s = $self->_fresh;
    $self->_emit("  $m0s = phi i64 [ $start, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: match start");
    my $m0e = $self->_fresh;
    $self->_emit("  $m0e = phi i64 [ $caps{m0e}, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: match end");
    my (@cap_s, @cap_e);
    for my $g (1 .. $ngroups) {
        my ($s_ref, $e_ref) = ($caps{s}[$g], $caps{e}[$g]);
        die "G6 internal: capture group $g has no recorded boundaries"
            unless defined $s_ref && defined $e_ref;
        my $sp = $self->_fresh;
        $self->_emit("  $sp = phi i64 [ $s_ref, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: \$$g start");
        my $ep = $self->_fresh;
        $self->_emit("  $ep = phi i64 [ $e_ref, \%$lbl_hit ], [ 0, \%$lbl_miss ]  ; $tag: \$$g end");
        $cap_s[$g] = $sp;
        $cap_e[$g] = $ep;
    }

    return { matched => $matched, m0s => $m0s, m0e => $m0e,
             cap_s => \@cap_s, cap_e => \@cap_e };
}

# _lower_regex_match($node) -> $llvm_ref (i1 matched?)
sub _lower_regex_match {
    my ($self, $node) = @_;

    my $subj_node = $node->inputs->[0];
    my $repr      = _require_repr($node, 'RegexMatch');

    # Lower the subject to its i8* pointer and obtain its byte length.
    my $subj_ptr  = $self->lower_value($subj_node);
    my $subj_len  = $self->_str_len_for($subj_ptr)
        // die "GAP: RegexMatch subject (ref=$subj_ptr) has no tracked length — "
             . "the matcher needs the subject's byte length.";

    my $compiled = _compile_regex_pattern($node->pattern, $node->flags);
    my $match    = $self->_emit_regex_matcher($subj_ptr, $subj_len, $compiled, 'RegexMatch');

    # Record the capture offsets for downstream consumers (G7's $N magic vars
    # read these as graph-edge side data; s/// consumes them directly).
    # subj_ptr rides along so a RegexCapture can materialize the $N view.
    $match->{subj_ptr} = $subj_ptr;
    $self->{_regex_captures}{ $node->id } = $match;

    $self->{cache}{ $node->id } = $match->{matched};
    return $match->{matched};
}

# _lower_match_apply($node) -> $llvm_ref (i1 matched?)
#
# Lowers Match (=~ applying a compiled-regex VALUE): inputs[0] = subject Str,
# inputs[1] = the qr// value. A qr// literal is a Constant(const_type='regex')
# with :Regex repr — its pattern is compile-time known, so the application
# inlines the same matcher RegexMatch uses. A qr value that cannot be resolved
# statically (e.g. flowing through vars/containers the resolver cannot walk)
# is a loud GAP — a matcher-function ABI is only built if that need is real.
sub _lower_match_apply {
    my ($self, $node) = @_;

    my $subj_node = $node->inputs->[0];
    my $qr_node   = $node->inputs->[1];
    my $repr      = _require_repr($node, 'Match');

    my $qr_op = $qr_node->can('operation') ? $qr_node->operation : '';
    unless ($qr_op eq 'Constant'
        && $qr_node->can('const_type')
        && ($qr_node->const_type // '') eq 'regex')
    {
        my $why = ($qr_op eq 'Constant')
            ? "a string-valued =~ rhs (perl treats it as a pattern) is not yet "
            . "wired — it IS statically resolvable, just an unimplemented form"
            : "a runtime-computed pattern would need a matcher-fn ABI";
        die "GAP: Match rhs (op=$qr_op) is not a qr// literal "
          . "(Constant const_type='regex') — $why.";
    }
    my $pattern = $qr_node->value;

    my $subj_ptr = $self->lower_value($subj_node);
    my $subj_len = $self->_str_len_for($subj_ptr)
        // die "GAP: Match subject (ref=$subj_ptr) has no tracked length — "
             . "the matcher needs the subject's byte length.";

    my $compiled = _compile_regex_pattern($pattern, '');
    my $match    = $self->_emit_regex_matcher($subj_ptr, $subj_len, $compiled, 'Match(qr)');

    $match->{subj_ptr} = $subj_ptr;
    $self->{_regex_captures}{ $node->id } = $match;
    $self->{cache}{ $node->id } = $match->{matched};
    return $match->{matched};
}

# _lower_regex_capture($node) -> $llvm_ref (i8* NUL-terminated copy)
#
# Lowers RegexCapture ($N): inputs[0] is the RegexMatch/Match node whose
# lowering recorded its capture offsets in _regex_captures. The captured
# bytes are COPIED into a fresh NUL-terminated buffer (malloc len+1 +
# memcpy + NUL), upholding the backend-wide invariant that EVERY Str SSA
# value is NUL-terminated: length tracking is lost at phi merges, and the
# fallbacks (epilogue printf %s, strlen) assume NUL — a zero-copy view into
# the subject violated that and printed the subject tail when a capture
# crossed an if/else merge (branch-review C4). Zero-copy views can return
# when the Str representation carries explicit lengths end-to-end.
#
# On a failed match the offsets are the 0 sentinels, so the copy is the
# empty string; perl yields undef there — the realistic lib/ idiom guards
# $N behind the match (matched ? $1 : ...), and the undef face is a tracked
# follow-up alongside the L3 Undef-rep composition.
sub _lower_regex_capture {
    my ($self, $node) = @_;

    my $repr       = _require_repr($node, 'RegexCapture');
    die "GAP: RegexCapture has repr=$repr; \$N capture values are Str"
        unless $repr eq 'Str';
    my $match_node = $node->inputs->[0];
    my $n          = $node->n;

    # Lower the match first (idempotent via the value cache); its lowering
    # records the capture offsets keyed by the match node's id.
    $self->lower_value($match_node);
    my $rec = $self->{_regex_captures}{ $match_node->id };
    unless (defined $rec) {
        my $mop = $match_node->can('operation') ? $match_node->operation : '?';
        die "GAP: RegexCapture input (op=$mop) is not a regex match node — "
          . "\$$n is a slot of a match result; only RegexMatch/Match produce one.";
    }
    my ($s_ref, $e_ref) = ($rec->{cap_s}[$n], $rec->{cap_e}[$n]);
    unless (defined $s_ref && defined $e_ref) {
        my $have = $#{ $rec->{cap_s} };
        $have = 0 if $have < 0;
        die "GAP: RegexCapture \$$n out of range — the pattern has $have capture "
          . "group(s) (\$& / group 0 is a tracked follow-up).";
    }

    $self->{_need_malloc_memcpy} = 1;

    my $src = $self->_fresh;
    $self->_emit("  $src = getelementptr inbounds i8, i8* $rec->{subj_ptr}, i64 $s_ref  ; RegexCapture: \$$n source");
    my $len = $self->_fresh;
    $self->_emit("  $len = sub i64 $e_ref, $s_ref  ; RegexCapture: \$$n length");
    my $alloc = $self->_fresh;
    $self->_emit("  $alloc = add i64 $len, 1  ; RegexCapture: +1 for NUL");
    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 $alloc)  ; RegexCapture: \$$n buffer");
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $src, i64 $len)  ; RegexCapture: copy \$$n");
    my $nul = $self->_fresh;
    $self->_emit("  $nul = getelementptr inbounds i8, i8* $buf, i64 $len  ; RegexCapture: NUL slot");
    $self->_emit("  store i8 0, i8* $nul  ; RegexCapture: NUL-terminate");

    $self->{_str_len_table}{$buf} = $len;
    $self->{cache}{ $node->id } = $buf;
    return $buf;
}

# _lower_env_read($node) -> $llvm_ref (i8* value string)
#
# Lowers EnvRead: a getenv(key) call against host process state. A missing
# key reads as the EMPTY string (perl yields undef there — the undef face is
# a tracked follow-up that composes with the L3 Undef representation; the
# NULL-guarded select keeps the read crash-free meanwhile). The value length
# is a runtime strlen, tracked in _str_len_table.
sub _lower_env_read {
    my ($self, $node) = @_;

    my $repr = _require_repr($node, 'EnvRead');
    die "GAP: EnvRead has repr=$repr; %ENV values are Str" unless $repr eq 'Str';
    my $key  = $node->key;
    $self->{_need_getenv} = 1;

    # Key + empty-string fallback as module globals. Same symbol-prefix rule
    # as @str_const_N/@rxs_lit_N: method bodies lower in fresh Contexts whose
    # counters restart at 0, but the globals land at module scope — prefix by
    # class/method so two bodies do not both emit @env_key_0.
    my $gpfx = '';
    if ($self->{_in_method_body}
        && defined $self->{_method_class_name}
        && defined $self->{_method_name}) {
        $gpfx = "$self->{_method_class_name}__$self->{_method_name}__";
    }
    my $gidx  = scalar @{ $self->{_str_globals} };
    my $kname = "\@${gpfx}env_key_$gidx";
    push $self->{_str_globals}->@*, [ $kname, $key, length($key) ];
    my $ktotal = length($key) + 1;
    my $kptr = $self->_fresh;
    $self->_emit("  $kptr = getelementptr inbounds [$ktotal x i8], [$ktotal x i8]* $kname, i64 0, i64 0  ; EnvRead: key \"$key\"");

    my $eidx  = scalar @{ $self->{_str_globals} };
    my $ename = "\@${gpfx}env_empty_$eidx";
    push $self->{_str_globals}->@*, [ $ename, '', 0 ];
    my $eptr = $self->_fresh;
    $self->_emit("  $eptr = getelementptr inbounds [1 x i8], [1 x i8]* $ename, i64 0, i64 0  ; EnvRead: empty fallback");

    my $raw = $self->_fresh;
    $self->_emit("  $raw = call i8* \@getenv(i8* $kptr)  ; EnvRead: getenv(\"$key\")");
    my $isnull = $self->_fresh;
    $self->_emit("  $isnull = icmp eq i8* $raw, null  ; EnvRead: key unset?");
    my $val = $self->_fresh;
    $self->_emit("  $val = select i1 $isnull, i8* $eptr, i8* $raw  ; EnvRead: value (empty if unset)");
    my $len = $self->_fresh;
    $self->_emit("  $len = call i64 \@strlen(i8* $val)  ; EnvRead: value length");

    $self->{_str_len_table}{$val} = $len;
    $self->{cache}{ $node->id } = $val;
    return $val;
}

# _parse_subst_replacement($replacement, $ngroups) -> \@segments
#
# Split an s/// replacement into literal runs and $N capture references.
# Each segment is { kind => 'lit', text => ... } or { kind => 'cap', n => N }.
# A backslash escapes the next char to a literal; $& $` $' and $N beyond the
# pattern's group count die loudly as GAPs.
sub _parse_subst_replacement {
    my ($repl, $ngroups) = @_;
    my @segs;
    my $lit = '';
    my @chars = split //, $repl;
    my $i = 0;
    my $flush = sub {
        push @segs, { kind => 'lit', text => $lit } if length $lit;
        $lit = '';
    };
    while ($i <= $#chars) {
        my $c = $chars[$i];
        if ($c eq '\\' && $i < $#chars) {
            my $e = $chars[ $i + 1 ];
            # The replacement contract is COOKED BYTES: the parser resolves
            # double-quotish escapes (\t, \n, \x..) before constructing the
            # node; only \$ and \\ are substitution-level escapes here. An
            # alphanumeric escape reaching this point would silently become
            # the literal letter — die loudly instead.
            die "GAP: s/// replacement escape \\$e not supported (the parser "
              . "resolves double-quotish escapes; only \\\$ and punctuation "
              . "escapes are handled here)" if $e =~ /[A-Za-z0-9]/;
            $lit .= $e;
            $i += 2;
            next;
        }
        if ($c eq '$' && $i < $#chars) {
            my $n = $chars[ $i + 1 ];
            if ($n =~ /^[1-9]$/) {
                # Perl reads the LONGEST digit run ($12 = group 12, not $1."2");
                # multi-digit groups are beyond the supported slice — die rather
                # than silently splitting into $1 . "2".
                die "GAP: s/// replacement multi-digit capture ref \$$n$chars[$i+2] "
                  . "not supported (perl reads it as one group number)"
                    if ($chars[ $i + 2 ] // '') =~ /^\d$/;
                die "GAP: s/// replacement references \$$n but the pattern has "
                  . "only $ngroups capture group(s)" if $n > $ngroups;
                $flush->();
                push @segs, { kind => 'cap', n => 0 + $n };
                $i += 2;
                next;
            }
            die "GAP: s/// replacement \$$n not supported (only \$1..\$9 capture refs)";
        }
        $lit .= $c;
        $i++;
    }
    $flush->();
    return \@segs;
}

# _lower_regex_subst($node) -> $llvm_ref (i8* result string)
#
# Lowers s///: run the matcher, then splice — result = prefix [0,m0s) +
# replacement (literal segments + $N captured slices) + suffix [m0e,len).
# A failed match returns the subject unchanged. First match only (/g is a
# tracked follow-up). The result length is a runtime value tracked in
# _str_len_table (the Str epilogue prints via "%.*s").
sub _lower_regex_subst {
    my ($self, $node) = @_;

    my $subj_node = $node->inputs->[0];
    my $repr      = _require_repr($node, 'RegexSubst');

    my $flags = $node->flags // '';
    die "GAP: s///$flags flags not yet supported by the G6 sub-compiler "
      . "(/g is a tracked follow-up)" if length $flags;

    my $subj_ptr  = $self->lower_value($subj_node);
    my $subj_len  = $self->_str_len_for($subj_ptr)
        // die "GAP: RegexSubst subject (ref=$subj_ptr) has no tracked length — "
             . "the matcher needs the subject's byte length.";

    my $compiled = _compile_regex_pattern($node->pattern, $node->flags);
    my $segs     = _parse_subst_replacement($node->replacement // '',
                                            $compiled->{ngroups} // 0);

    my $match = $self->_emit_regex_matcher($subj_ptr, $subj_len, $compiled, 'RegexSubst');

    $self->{_need_malloc_memcpy} = 1;

    my $lbl_pre  = $self->_current_block_label;
    my $lbl_do   = $self->_fresh_label('rxsdo');
    my $lbl_done = $self->_fresh_label('rxsdn');
    $self->_set_terminator("  br i1 $match->{matched}, label \%$lbl_do, label \%$lbl_done");

    # Matched: build the spliced string.
    $self->_new_block($lbl_do);
    my $m0len = $self->_fresh;
    $self->_emit("  $m0len = sub i64 $match->{m0e}, $match->{m0s}  ; RegexSubst: matched length");

    # Replacement length: compile-time literal bytes + runtime capture lengths.
    my $lit_total = 0;
    $lit_total += length($_->{text}) for grep { $_->{kind} eq 'lit' } @$segs;
    my $repl_len = $lit_total;   # SSA ref or constant
    for my $seg (grep { $_->{kind} eq 'cap' } @$segs) {
        my $n = $seg->{n};
        my $clen = $self->_fresh;
        $self->_emit("  $clen = sub i64 $match->{cap_e}[$n], $match->{cap_s}[$n]  ; RegexSubst: \$$n length");
        $seg->{len_ref} = $clen;
        my $acc = $self->_fresh;
        $self->_emit("  $acc = add i64 $repl_len, $clen  ; RegexSubst: replacement length so far");
        $repl_len = $acc;
    }

    my $keep = $self->_fresh;
    $self->_emit("  $keep = sub i64 $subj_len, $m0len  ; RegexSubst: bytes kept from subject");
    my $new_len = $self->_fresh;
    $self->_emit("  $new_len = add i64 $keep, $repl_len  ; RegexSubst: result length");
    my $alloc = $self->_fresh;
    $self->_emit("  $alloc = add i64 $new_len, 1  ; RegexSubst: +1 for NUL");
    my $buf = $self->_fresh;
    $self->_emit("  $buf = call i8* \@malloc(i64 $alloc)  ; RegexSubst: result buffer");

    # Prefix [0, m0s).
    $self->_emit("  call i8* \@memcpy(i8* $buf, i8* $subj_ptr, i64 $match->{m0s})  ; RegexSubst: prefix");
    my $cursor = $match->{m0s};   # dest offset after the prefix

    # Replacement segments.
    for my $seg (@$segs) {
        my $dest = $self->_fresh;
        $self->_emit("  $dest = getelementptr inbounds i8, i8* $buf, i64 $cursor  ; RegexSubst: dest cursor");
        if ($seg->{kind} eq 'lit') {
            my $text = $seg->{text};
            my $blen = length $text;
            # Same symbol-prefix rule as @str_const_N (see _lower_constant, I1):
            # method bodies lower in fresh Contexts whose counters restart at 0,
            # but the globals land at module scope — prefix by class/method so
            # two bodies do not both emit @rxs_lit_0 (duplicate symbol).
            my $gidx = scalar @{ $self->{_str_globals} };
            my $gname;
            if ($self->{_in_method_body}
                && defined $self->{_method_class_name}
                && defined $self->{_method_name}) {
                $gname = "\@$self->{_method_class_name}__$self->{_method_name}__rxs_lit_${gidx}";
            } else {
                $gname = "\@rxs_lit_$gidx";
            }
            push $self->{_str_globals}->@*, [ $gname, $text, $blen ];
            my $total = $blen + 1;
            my $src = $self->_fresh;
            $self->_emit("  $src = getelementptr inbounds [$total x i8], [$total x i8]* $gname, i64 0, i64 0  ; RegexSubst: literal segment");
            $self->_emit("  call i8* \@memcpy(i8* $dest, i8* $src, i64 $blen)  ; RegexSubst: copy literal");
            my $next = $self->_fresh;
            $self->_emit("  $next = add i64 $cursor, $blen  ; RegexSubst: advance cursor");
            $cursor = $next;
        }
        else {
            my $n = $seg->{n};
            my $src = $self->_fresh;
            $self->_emit("  $src = getelementptr inbounds i8, i8* $subj_ptr, i64 $match->{cap_s}[$n]  ; RegexSubst: \$$n source");
            $self->_emit("  call i8* \@memcpy(i8* $dest, i8* $src, i64 $seg->{len_ref})  ; RegexSubst: copy \$$n");
            my $next = $self->_fresh;
            $self->_emit("  $next = add i64 $cursor, $seg->{len_ref}  ; RegexSubst: advance cursor");
            $cursor = $next;
        }
    }

    # Suffix [m0e, len) + NUL terminator.
    my $sfx_dest = $self->_fresh;
    $self->_emit("  $sfx_dest = getelementptr inbounds i8, i8* $buf, i64 $cursor  ; RegexSubst: suffix dest");
    my $sfx_src = $self->_fresh;
    $self->_emit("  $sfx_src = getelementptr inbounds i8, i8* $subj_ptr, i64 $match->{m0e}  ; RegexSubst: suffix source");
    my $sfx_len = $self->_fresh;
    $self->_emit("  $sfx_len = sub i64 $subj_len, $match->{m0e}  ; RegexSubst: suffix length");
    $self->_emit("  call i8* \@memcpy(i8* $sfx_dest, i8* $sfx_src, i64 $sfx_len)  ; RegexSubst: suffix");
    my $nul_ptr = $self->_fresh;
    $self->_emit("  $nul_ptr = getelementptr inbounds i8, i8* $buf, i64 $new_len  ; RegexSubst: NUL slot");
    $self->_emit("  store i8 0, i8* $nul_ptr  ; RegexSubst: NUL-terminate");
    $self->_set_terminator("  br label \%$lbl_done");

    # Merge: spliced buffer on match, the original subject otherwise.
    $self->_new_block($lbl_done);
    my $res = $self->_fresh;
    $self->_emit("  $res = phi i8* [ $buf, \%$lbl_do ], [ $subj_ptr, \%$lbl_pre ]  ; RegexSubst: result");
    my $res_len = $self->_fresh;
    $self->_emit("  $res_len = phi i64 [ $new_len, \%$lbl_do ], [ $subj_len, \%$lbl_pre ]  ; RegexSubst: result length");

    $self->{_str_len_table}{$res} = $res_len;
    $self->{cache}{ $node->id } = $res;
    return $res;
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
# Walks the obj_node back to find the statically-known class name. Supports:
# - Call(dispatch_kind='method', name='new') via its class_name attribute
# - Other cases: die loudly (cannot infer class name)
sub _infer_class_name_from_obj {
    my ($obj_node) = @_;
    return undef unless defined $obj_node;
    my $op = $obj_node->can('operation') ? $obj_node->operation : '';
    # Call(dispatch_kind='method', name='new') is the canonical construction form.
    if ($op eq 'Call' && $obj_node->can('dispatch_kind')
        && ($obj_node->dispatch_kind // '') eq 'method'
        && ($obj_node->name // '') eq 'new')
    {
        return $obj_node->class_name
            // die "LLVM MOP: Call(new) has no class_name — cannot infer the "
                 . "constructed class (019eb42a MOP-direct contract).";
    }
    # PadAccess to a variable holding a constructed object — walk inputs
    if ($op eq 'PadAccess') {
        # Not yet supported in MOP: die to trigger diagnostic
        die "LLVM MOP: cannot infer class name from PadAccess — "
          . "method body self-reference via var not yet supported";
    }
    die "LLVM MOP: cannot infer class name from op=$op — expected Call(new) or PadAccess";
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
        # Wire explicit Phi nodes on the Region FIRST: lowering their arm
        # values may extend the then/else tails with continuation blocks
        # (multi-block values), which changes the labels that actually
        # branch into the merge. The elab phis below must name those
        # updated labels, so take them from the wiring's return value.
        # Arm values are lowered with each branch's var_table snapshot so
        # variable reads are branch-correct.
        ($then_end_label, $else_end_label) = $self->_wire_region_phis_with_preblock(
            $region, $then_end_label, $else_end_label, \%then_var, \%else_var);

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
#
# A multi-block arm value (bounds-checked Subscript, And/Or, ternary)
# consumes the tail block's branch-to-merge and opens continuation blocks;
# _lower_arm_in_tail re-attaches the branch to the new tail and returns the
# label that actually enters the merge. Arms are lowered with that branch's
# var_table snapshot so variable reads see branch-final state, not merge
# state. Returns the updated (then_label, else_label) — the caller must use
# these for any further phi lines it emits into the same merge block.
sub _wire_region_phis_with_preblock {
    my ($self, $region, $then_label, $else_label, $then_vars, $else_vars) = @_;

    my $consumers = $region->consumers // [];
    my @phis = grep {
        defined $_ && ref($_)
            && $_->can('operation') && $_->operation eq 'Phi'
            && !exists $self->{cache}{ $_->id }
    } @$consumers;
    return ($then_label, $else_label) unless @phis;

    my $merge_idx = $self->_find_block_idx($self->_current_block_label);

    # Pass 1: lower ALL arms for ALL phis. Emitting phi lines one at a time
    # is wrong: a later phi's multi-block arm extends the same tail and
    # re-points the branch-to-merge, leaving any already-emitted phi naming
    # a block that no longer branches to the merge ("PHI node entries do
    # not match predecessors"). Every phi line must name the FINAL tail
    # labels, known only after all arms have lowered. (An earlier-lowered
    # arm value defined in the pre-extension tail still dominates the final
    # tail's branch, so the value/label pairing stays valid.)
    my @wired;
    for my $phi_node (@phis) {
        my $inputs = $phi_node->inputs;
        unless (defined $inputs && scalar @$inputs >= 2) {
            die "LLVM backend: Phi node (id=" . $phi_node->id . ") attached to Region "
              . "has fewer than 2 incoming values — missing predecessor edge";
        }
        for my $slot (0, 1) {
            next if defined $inputs->[$slot];
            # Bindings builds Phi([val, undef]) when a variable is bound in
            # one branch only. Die with a diagnostic (mirrors _lower_phi's
            # undef-arm guard) instead of crashing inside lower_value.
            die "GAP: Region Phi (id=" . $phi_node->id . ") incoming slot $slot "
              . "is undef (variable bound in one branch only) — cannot lower "
              . "a one-sided merge value runtime-free.";
        }
        my ($then_val, $else_val);
        ($then_val, $then_label) =
            $self->_lower_arm_in_tail($inputs->[0], $then_label, $then_vars);
        ($else_val, $else_label) =
            $self->_lower_arm_in_tail($inputs->[1], $else_label, $else_vars);
        push @wired, [$phi_node, $then_val, $else_val];
    }

    # Pass 2: emit all phi lines into the merge block with the final labels.
    $self->{current_idx} = $merge_idx;
    for my $w (@wired) {
        my ($phi_node, $then_val, $else_val) = @$w;
        my $repr      = Chalk::Target::LLVM::Context::_require_repr($phi_node, 'ElaboratedContext.Region.Phi');
        my $llvm_type = Chalk::Target::LLVM::Context::_repr_to_llvm_type($repr);
        my $result    = $self->_fresh;
        $self->_emit("  $result = phi $llvm_type [ $then_val, %$then_label ], [ $else_val, %$else_label ]  ; Region phi");
        $self->{cache}{ $phi_node->id } = $result;
    }
    return ($then_label, $else_label);
}

# _lower_arm_in_tail($arm_node, $tail_label, $var_snapshot) -> ($val, $end_label)
# Lower a phi arm value inside the named predecessor tail block, with the
# branch's var_table snapshot swapped in (when provided) so variable reads
# are branch-correct. If the arm expands into continuation blocks, its
# control flow consumed the tail's terminator: re-attach the saved
# branch-to-merge to the new tail and report the new tail's label as the
# phi's incoming label.
sub _lower_arm_in_tail {
    my ($self, $arm_node, $tail_label, $var_snapshot) = @_;

    my $idx = $self->_find_block_idx($tail_label);
    $self->{current_idx} = $idx;
    my $saved_term = $self->{blocks}[$idx]{terminator};

    my %merge_vars;
    if (defined $var_snapshot) {
        %merge_vars = %{ $self->{var_table} };
        %{ $self->{var_table} } = %$var_snapshot;
    }
    my $val = $self->lower_value($arm_node);
    if (defined $var_snapshot) {
        %{ $self->{var_table} } = %merge_vars;
    }

    my $end_label = $self->_current_block_label;
    if ($end_label ne $tail_label) {
        $self->_set_terminator($saved_term);
    }
    return ($val, $end_label);
}

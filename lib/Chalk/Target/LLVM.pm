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
use Chalk::IR::NodeFactory;   # %STATEMENT_EFFECT_OPS (the shared statement-effect table)
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
    # Undef return: a method whose body value is statically undef (e.g. an
    # if/else field-mutation whose discarded residual is the assignment value).
    # Undef lowers to the i1 defined-bit (always false), same shape as Bool.
    return 'i1 (i8*)'   if $result_repr eq 'Undef';
    die "LLVM MOP: unsupported method return repr '$result_repr'";
}

# _method_fn_llvm_ret_type($repr) -> LLVM return type for method function header
sub _method_fn_llvm_ret_type {
    my ($repr) = @_;
    return 'i64'      if !defined $repr || $repr eq 'Int';
    return '%StrPair' if $repr eq 'Str';
    return 'i1'       if $repr eq 'Bool';
    return 'double'   if $repr eq 'Num';
    return 'i1'       if $repr eq 'Undef';   # defined-bit, always false
    die "LLVM MOP: unsupported method return repr '$repr' for fn return type";
}

# ---------------------------------------------------------------------------
# Class registry: built from the sealed MOP (019eb42a MOP-direct).
# ---------------------------------------------------------------------------

# _flatten_inheritance(\%registry) -> void
#
# Resolve :isa inheritance: for each class with a parent, flatten inherited
# methods, FIELDS, and ADJUST blocks into the child (compile-time MRO
# flatten). Run AFTER the registry is fully populated so all parent classes
# are present. Parents flatten BEFORE their children (memoized recursion,
# cycle-guarded) — a single pass in name order would copy a parent's entry
# as it currently stands, losing GRANDparent members whenever the child
# sorts before its parent.
#
# Object-struct layout is base-first: a `feature class` subclass's struct
# is [parent fields..., own fields...], and a field read names its
# FLATTENED slot. The child's own fields, declared with per-class indices,
# are renumbered to follow the inherited ones. ADJUST blocks run base-first
# (the MRO order perl runs them in), so inherited adjusts are PREPENDED.
# :param fields likewise come from the flattened set, so a child constructor
# binds inherited :param fields.
sub _flatten_inheritance {
    my ($registry) = @_;
    my %done;
    my %in_progress;
    my $flatten;
    $flatten = sub {
        my ($cname) = @_;
        return if $done{$cname};
        die "LLVM MOP: inheritance cycle through class '$cname'"
            if $in_progress{$cname}++;
        my $parent = $registry->{$cname}{parent};
        if (defined $parent) {
            my $parent_reg = $registry->{$parent};
            unless (defined $parent_reg) {
                die "LLVM MOP: class '$cname' has :isa($parent) but '$parent' is not declared in this graph";
            }
            $flatten->($parent);
            my $child = $registry->{$cname};

            # Fields: parent fields occupy the low struct slots; the child's
            # own fields are renumbered to follow them. Inherited reader
            # methods (below) and FieldAccess nodes both name flattened slots.
            my @inherited = map { { %$_, inherited_from => $parent } }
                @{ $parent_reg->{fields} };
            my $base = scalar @inherited;
            my @own;
            my %remap;   # old per-class field_index -> flattened slot
            for my $fi (0 .. $#{ $child->{fields} }) {
                my $old = $child->{fields}[$fi]{field_index};
                $remap{$old} = $base + $fi;
                push @own, { $child->{fields}[$fi]->%*, field_index => $base + $fi };
            }
            $child->{fields} = [ @inherited, @own ];

            # Own :reader methods were synthesized with the pre-renumber
            # field index — fix them to the flattened slot.
            for my $m (@{ $child->{methods} }) {
                next unless $m->{is_reader_synth};
                next if exists $m->{inherited_from};
                $m->{reader_field_index} = $remap{ $m->{reader_field_index} }
                    if exists $remap{ $m->{reader_field_index} };
            }

            # Methods: copy parent slots the child does not override. Reader
            # methods carry reader_field_index — these are inherited fields,
            # already at their parent slot, so the index is correct as-is.
            for my $pmeth (@{ $parent_reg->{methods} }) {
                unless (grep { ($_->{name} // '') eq $pmeth->{name} } @{ $child->{methods} }) {
                    push @{ $child->{methods} }, {
                        %$pmeth,
                        vtable_slot => scalar(@{ $child->{methods} }),
                        inherited_from => $parent,
                    };
                }
            }

            # ADJUST: base-first. The parent's (already-flattened) adjusts
            # run before the child's own.
            $child->{adjusts} = [ @{ $parent_reg->{adjusts} }, @{ $child->{adjusts} } ];
        }
        delete $in_progress{$cname};
        $done{$cname} = 1;
        return;
    };
    $flatten->($_) for sort keys %$registry;
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
        # `main` is never INSTANTIATED -- no Call(new), so no vtable and no
        # object layout -- and it is skipped outright for that reason.
        #
        # It DOES own callables: every file-level `sub` is a sub of class main
        # under everything-is-a-class. They are deliberately not registered
        # here, because registering them would only feed an emission path that
        # is itself gated off (see CHALK_EMIT_SUB_DEFINES in the emission loop):
        # the INLINER still substitutes every direct-call body at its call site,
        # so a define duplicates rather than enables. Measured -- corpus
        # F9/F10/F11/F13 each printed their callee's output twice, gate
        # 214 -> 207.
        #
        # Step 5 (retire the inliner) is what makes main's subs worth
        # registering, and it is the same step that gives their defines a
        # caller. Skipping main entirely until then keeps ONE reason in ONE
        # place rather than a flag that no longer has a writer.
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
    # Graph::returns() collects Return AND Unwind nodes in hash order —
    # the contract is EXACTLY one Return (an early-return body would
    # otherwise lower a nondeterministically chosen arm), and an Unwind
    # (die/exception value) is never the body root.
    my $all = $mop_method->graph ? $mop_method->graph->returns : [];
    my @returns = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } @$all;
    die "GAP: method '" . $mop_method->name . "' in class '$cname' has no "
      . "Return in its graph — cannot determine the lowering root. "
      . "Merge a Return(value) into the method's graph."
        unless @returns;
    die "GAP: method '" . $mop_method->name . "' in class '$cname' has "
      . scalar(@returns) . " Returns — the lowering root must be exactly one "
      . "(multi-exit method bodies are not lowered yet)."
        if @returns > 1;
    my $value = $returns[0]->inputs->[-1];
    die "GAP: method '" . $mop_method->name . "' in class '$cname' has a "
      . "Return with no value input." unless defined $value;
    return $value;
}

# _method_body_return($mop_method) -> $return_node
#
# The single Return node of a method's graph — the control root the body's
# statement effects (field-store Assign, void Call) hang off. The method body is
# lowered by walking this Return's control chain through _process_control_chain,
# the same mechanism the top-level graph uses, so a BRANCHED body (an if/else
# whose arms store a field) lowers to real basic blocks. A linear control_in walk
# would stop at a merge Region and drop the branch arms.
#
# The exactly-one-Return invariant is the same one _method_body_root enforces
# (and it runs first at registry-build time, so this die is a belt-and-braces
# guard). GAP loudly on a graph without a single unique Return rather than
# returning undef — a silent undef would bare-deref in Dominators->from_return_node
# and _process_control_chain, turning a lowering GAP into an opaque crash.
sub _method_body_return {
    my ($mop_method) = @_;
    my $mname = $mop_method->name // '?';
    my $graph = $mop_method->graph
        or die "GAP: method '$mname' has no graph — cannot determine the body "
             . "control root.";
    my @returns = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } @{ $graph->returns };
    die "GAP: method '$mname' has " . scalar(@returns) . " Returns — the body "
      . "control root must be exactly one (a multi-exit body is not lowered yet)."
        unless @returns == 1;
    return $returns[0];
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
    # Membership only (graph->members), NOT the input closure that nodes()
    # walks: a Call/Assign appearing as an INPUT of a merged statement
    # (e.g. the rhs of a field store) is a sub-expression, not a body
    # statement — counting it produces a spurious second chain head.
    my @stmts = grep {
        blessed($_) && $_->can('operation')
            && (exists $Chalk::IR::NodeFactory::STATEMENT_EFFECT_OPS{ $_->operation }
                || $_->operation eq 'VarDecl')
    } $phaser->graph->members->@*;
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
# Produces the registry record shape from a sealed MOP::Class so downstream
# emission (_emit_class_registry_ir) is unchanged. (Its former ClassInfo sibling
# was deleted in 183a5973.)
sub _populate_registry_from_mop_class {
    my ($registry, $cls) = @_;
    my $cname = $cls->name;
    $registry->{$cname} //= { methods => [], subs => [], fields => [], adjusts => [], parent => undef };
    $registry->{$cname}{subs} //= [];
    $registry->{$cname}{parent} //= $cls->parent_name;

    # SUBS ARE NOT METHODS, and they are kept in their own list rather than
    # appended to {methods}. A sub takes no implicit invocant and is not
    # dispatched, so it needs a `define` but NOT a vtable slot -- appending it
    # to {methods} would emit the define AND silently widen every vtable, and
    # would be inherited by subclasses through _flatten_inheritance, which is
    # wrong for a callable that was never dispatched in the first place.
    #
    # Recording them here is the point of this step: the registry is the
    # backend's read surface for the MOP, and sub metadata now reaches it
    # instead of being recovered by scanning. EMITTING a define from it is
    # gated separately (see the emission loop) because the inliner still owns
    # every direct call.
    for my $s ($cls->subs) {
        my $sname = $s->name;
        next if grep { ($_->{name} // '') eq $sname } @{ $registry->{$cname}{subs} };

        # A callee that reads @_ has no bound arguments OUTSIDE an inline, so
        # its body root carries no repr and _require_repr below would refuse
        # the WHOLE PROGRAM -- even when the sub is never called. Measured:
        # `class W { ... sub twice { my $x = shift; $x * 2 } }` compiled and
        # ran before this step and afterwards GAPped with "MOP::Sub 'twice'
        # body root ... NO representation", blaming TypeInference for what is
        # really an unbound argument.
        #
        # `uses_args` is exactly the signal for that, which is why the producer
        # records it. Registration resumes for these when arguments are bound
        # at a real call boundary (params-by-default, plan steps 3+5).
        next if $s->uses_args;

        my $body_node = _method_body_root($s);
        push @{ $registry->{$cname}{subs} }, {
            name        => $sname,
            body_node   => $body_node,
            body_return => _method_body_return($s),
            # Qualified: an unqualified name made the GAP ambiguous across
            # classes declaring the same sub name.
            return_repr => ($s->return_type
                // _require_repr($body_node, "MOP::Sub '${cname}::${sname}' body root")),
            uses_args   => $s->uses_args,
        };
    }

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
                body_return => _method_body_return($m),
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
        # A field already at this index is either the SAME field re-encountered
        # (idempotent re-add across inheritance passes — skip it) or a DIFFERENT
        # field colliding on the slot (malformed MOP — the second would be
        # silently dropped, shifting no slots but losing the field). Croak on the
        # real collision; skip only the exact re-add.
        my ($existing) = grep { ($_->{field_index} // -1) == $fidx }
                              @{ $registry->{$cname}{fields} };
        if ($existing && ($existing->{name} // '') ne $fname) {
            die "GAP: class '$cname' has two distinct fields at field_index "
              . "$fidx ('$existing->{name}' and '$fname') — a duplicate field_index "
              . "would silently drop the second field.";
        }
        unless ($existing) {
            push @{ $registry->{$cname}{fields} }, {
                name         => $fname,
                # The bare :param key (sigil-free, e.g. 'n' for field '$n').
                # A constructor Call binds by this key; native callers that
                # pass bare param_names fall back to matching name.
                param_name   => (($mf->can('param_name') ? $mf->param_name : undef) // $fname),
                field_index  => $fidx,
                is_param     => $mf->is_param    // false,
                has_reader   => $mf->has_reader  // false,
                has_default  => $mf->has_default // false,
                default_node => $mf->default_value,
                field_repr   => $f_repr,
            };
        }
        if ($mf->has_reader) {
            # The :reader accessor method is named after the field with the
            # sigil stripped ($left -> left); the call site dispatches on that
            # bare name.
            my $rname = $fname =~ s/^[\$\@%]//r;
            unless (grep { ($_->{name} // '') eq $rname } @{ $registry->{$cname}{methods} }) {
                push @{ $registry->{$cname}{methods} }, {
                    name               => $rname,
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
    _need_print_str_fmt
    _need_print_int_fmt
    _need_exit
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
        # Subs share the %StrPair return ABI, so they must be in this pre-scan
        # too -- a Str-returning SUB in a class whose methods all return Int
        # would otherwise emit insertvalue over an undeclared %StrPair.
        for my $m (@{ $reg->{methods} }, @{ $reg->{subs} // [] }) {
            $need_strpair = 1 if ($m->{return_repr} // '') eq 'Str';
        }
    }

    # %Str is declared UNCONDITIONALLY here, unlike %StrPair. This prologue runs
    # BEFORE any method body is lowered, so a pre-scan cannot know whether a body
    # will build one — and %Str is needed by any Str VALUE at all, not merely by
    # a Str-RETURNING method, so the scan above (which keys on return_repr) would
    # miss most uses. An unused type declaration is inert; a missing one makes
    # lli reject the module with "invalid indices for insertvalue".
    unless ($ctx->{_str_type_emitted}) {
        push @lines, '; Str VALUE type (layout: Context::_str_fields)';
        push @lines, Chalk::Target::LLVM::Context::_str_type_decl();
        $ctx->{_str_type_emitted} = 1;
    }

    if ($need_strpair) {
        push @lines, '; StrPair for Str method return values (layout: Context::_strpair_fields)';
        push @lines, Chalk::Target::LLVM::Context::_strpair_type_decl();
        $ctx->{_need_strpair} = 1;
        $ctx->{_strpair_emitted} = 1;  # I3: track emission to prevent double-declare in post-class re-emit
    }

    # Type pre-pass: emit EVERY class's vtable + object-struct type before any
    # class body. An inherited ADJUST flattened into a child (019eb6ff item 6)
    # carries the declaring ancestor's field_stash, so the child's
    # @Child__ADJUST body GEPs into %Ancestor.obj. With per-class inline type
    # defs in sort order, that GEP referenced an as-yet-undefined (opaque,
    # unsized) struct whenever the child sorted before its ancestor — lli:
    # "base element of getelementptr must be sized". Defining all struct types
    # up front makes every cross-class GEP target sized regardless of order.
    for my $cname (sort keys %$registry) {
        my $reg     = $registry->{$cname};
        my $methods = $reg->{methods} // [];
        my $fields  = $reg->{fields}  // [];

        # Vtable type: { i8* class-name, i8* slot0, i8* slot1, ... }
        my $vt_type = '%' . $cname . '.vt';
        my @vt_elems = ('i8*');  # slot 0 = class-name ptr
        push @vt_elems, ('i8*') x scalar(@$methods);
        push @lines, "$vt_type = type { " . join(', ', @vt_elems) . " }  ; vtable for $cname";

        # Object struct type: { %Cls.vt*, %Slot, %Slot, ... }
        my $obj_type = '%' . $cname . '.obj';
        my @obj_elems = ($vt_type . '*');  # slot 0 = vtable ptr
        push @obj_elems, ('%Slot') x scalar(@$fields);  # one %Slot per field
        push @lines, "$obj_type = type { " . join(', ', @obj_elems) . " }  ; object struct for $cname";
    }

    for my $cname (sort keys %$registry) {
        my $reg     = $registry->{$cname};
        my $methods = $reg->{methods} // [];
        my $fields  = $reg->{fields}  // [];

        # Sort fields by field_index to ensure consistent struct layout
        my @sorted_fields = sort { ($a->{field_index} // 0) <=> ($b->{field_index} // 0) } @$fields;

        my $vt_type  = '%' . $cname . '.vt';
        my $obj_type = '%' . $cname . '.obj';

        # Class-name string constant
        my $cn_name_global = '@' . $cname . '__class_name';
        my $cn_bytes = length($cname) + 1;  # +1 for NUL
        my $cn_enc   = _encode_c_string($cname);
        push @lines, "$cn_name_global = private unnamed_addr constant [$cn_bytes x i8] c\"$cn_enc\\00\", align 1";

        # Method body functions (one define per method)
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

            # Lower the method body through an ElaboratedContext, the SAME path
            # the top-level graph uses. A branched body (`method bump { if(C){$n=
            # $n+5}else{$n=$n+1} }`) has its field stores guarded by If/Proj; only
            # ElaboratedContext's _process_if_node emits those as real basic blocks
            # (the base Context stubs it out). The elab plan places any merge phi.
            my $body_return = $minfo->{body_return};
            my $body_dom  = Chalk::IR::Schedule::Dominators->from_return_node($body_return);
            my $body_elab = Chalk::IR::Schedule::Elaborate->from_return_node($body_return, $body_dom);
            my $body_ctx  = Chalk::Target::LLVM::ElaboratedContext->new(
                elab           => $body_elab,
                class_registry => $registry,
            );
            $body_ctx->{_in_method_body} = 1;
            $body_ctx->{_method_self_name} = '%self';
            $body_ctx->{_method_class_name} = $cname;
            $body_ctx->{_method_name} = $mname;  # I1: used to prefix str_const globals uniquely
            $body_ctx->{_need_strpair}  = $ctx->{_need_strpair} // 0;

            # Emit the body's statement effects (field-store Assign, void Call, and
            # any branch-guarded If) in control order BEFORE the return value, so a
            # `method inc { $n += 1 }` writes the field back and a branched `bump`
            # emits both guarded stores. Same mechanism as the top-level graph.
            _process_control_chain($body_ctx, $body_return);

            # Lower the body value node into the method body context
            my $body_val = $body_ctx->lower_value($body_node);

            # Propagate need-flags BACK UP. A method body is lowered in its own
            # Context, so a flag set during that lowering is invisible to the
            # parent $ctx that emits the type declarations — and %Str is
            # declared from $ctx. Without this the body emits insertvalue over
            # an undeclared %Str and lli rejects the module with "invalid
            # indices for insertvalue". (%StrPair avoids this only by having a
            # pre-scan over return_repr; %Str has none, because it is needed by
            # any Str VALUE rather than only by a Str-returning method.)
            $ctx->{_need_str_type} ||= $body_ctx->{_need_str_type};

            push @lines, "define internal $fn_ret $fn_name(i8* %self) {  ; method body for ${cname}::${mname}";
            push @lines, 'entry:';

            # Emit all instructions from the body context (current block
            # renders last; the ret lines below attach textually to it).
            push @lines, _render_context_blocks($body_ctx, 1);

            # Emit return instruction
            if ($ret_repr eq 'Str') {
                # Through the seam, not into the table. This was the one direct
                # A Str-returning body hands back a %Str aggregate, so
                # destructure it for the %StrPair return ABI. Emitted inline
                # because this block pushes onto @lines directly rather than
                # through the context, so _str_parts — which emits into the
                # context's current block — cannot be used here.
                #
                # Keyed on the repr (we are inside `$ret_repr eq 'Str'`), not on
                # a side registry: every Str value is an aggregate, and a phi
                # result is one the registry would never have recorded.
                push @lines, "  %ret_sp = extractvalue %Str $body_val, 0";
                push @lines, "  %ret_sl = extractvalue %Str $body_val, 1";
                my $ptr_val = '%ret_sp';
                my $len_ref = '%ret_sl';

                if (defined $len_ref) {
                    push @lines, "  %ret_r0 = insertvalue %StrPair undef, i8* $ptr_val, 0";
                    push @lines, "  %ret_r1 = insertvalue %StrPair %ret_r0, i64 $len_ref, 1";
                    push @lines, '  ret %StrPair %ret_r1';
                }
                else {
                    # Compute strlen at runtime
                    push @lines, "  %ret_len = call i64 \@strlen(i8* $ptr_val)";
                    push @lines, "  %ret_r0 = insertvalue %StrPair undef, i8* $ptr_val, 0";
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
            elsif ($ret_repr eq 'Undef') {
                # Undef-returning method (discarded if/else field-mutation
                # residual): the body value is the i1 defined-bit (always 0).
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

        # 4a-2. SUB body functions (one define per plain `sub` in the class).
        #
        # The same body-lowering shape as a method, minus the two things a sub
        # does not have: no `i8* %self` parameter (no implicit invocant) and no
        # vtable slot (never dispatched).
        #
        # GATED OFF, and this is the honest state of the work rather than a
        # missing feature. The INLINER (_lower_call_direct) still substitutes
        # every direct-call callee body at its call site -- class subs included,
        # which I had assumed were exempt and measured otherwise. So a define
        # here does not give a sub a call path, it DUPLICATES a body that is
        # already inlined:
        #
        #   pure sub          harmless but dead (measured: correct answer, an
        #                     unreferenced define)
        #   sub with a Str    lli REJECTS the module -- "redefinition of global
        #                     '@str_const_0'", because both copies render the
        #                     same string globals
        #   sub with a print  the effect fires twice
        #
        # The same shape took corpus F9-F13 from 214 to 207 for main's subs.
        # This becomes live in the step that retires the inliner (plan step 5),
        # which is also the step that gives these defines a caller. Until then
        # the REGISTRY carries the metadata -- which is what 1c is for -- and
        # emission stays off.
        my $emit_sub_defines = $ENV{CHALK_EMIT_SUB_DEFINES} ? 1 : 0;
        for my $sinfo ($emit_sub_defines ? @{ $reg->{subs} // [] } : ()) {
            my $sname    = $sinfo->{name};
            my $fn_name  = '@' . $cname . '__' . $sname;
            my $ret_repr = $sinfo->{return_repr} // 'Int';
            my $fn_ret   = _method_fn_llvm_ret_type($ret_repr);

            my $body_return = $sinfo->{body_return};
            my $body_node   = $sinfo->{body_node};
            my $body_dom    = Chalk::IR::Schedule::Dominators->from_return_node($body_return);
            my $body_elab   = Chalk::IR::Schedule::Elaborate->from_return_node($body_return, $body_dom);
            my $body_ctx    = Chalk::Target::LLVM::ElaboratedContext->new(
                elab           => $body_elab,
                class_registry => $registry,
            );
            # NOT _in_method_body: there is no $self to resolve a FieldAccess
            # against. A sub touching a field is a compile error in perl, so a
            # FieldAccess here would be a producer bug and should fail loudly
            # rather than silently bind to a nonexistent invocant.
            $body_ctx->{_method_class_name} = $cname;
            $body_ctx->{_method_name}       = $sname;
            $body_ctx->{_need_strpair}      = $ctx->{_need_strpair} // 0;

            _process_control_chain($body_ctx, $body_return);
            my $body_val = $body_ctx->lower_value($body_node);
            $ctx->{_need_str_type} ||= $body_ctx->{_need_str_type};

            push @lines, "define internal $fn_ret $fn_name() {  ; sub body for ${cname}::${sname}";
            push @lines, 'entry:';
            push @lines, _render_context_blocks($body_ctx, 1);

            if ($ret_repr eq 'Str') {
                push @lines, "  %ret_sp = extractvalue %Str $body_val, 0";
                push @lines, "  %ret_sl = extractvalue %Str $body_val, 1";
                push @lines, "  %ret_r0 = insertvalue %StrPair undef, i8* %ret_sp, 0";
                push @lines, "  %ret_r1 = insertvalue %StrPair %ret_r0, i64 %ret_sl, 1";
                push @lines, '  ret %StrPair %ret_r1';
            }
            elsif ($ret_repr eq 'Num')  { push @lines, "  ret double $body_val" }
            elsif ($ret_repr eq 'Bool'
                || $ret_repr eq 'Undef'){ push @lines, "  ret i1 $body_val" }
            else                        { push @lines, "  ret i64 $body_val" }
            push @lines, '}';
            push @lines, '';

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
            # Same back-propagation as the method-body path above: an ADJUST
            # block is lowered in its own Context, so a %Str built there is
            # invisible to the $ctx that declares the type.
            $ctx->{_need_str_type} ||= $adj_ctx->{_need_str_type};

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

        # Vtable global: @Cls__vtable = { class-name-ptr, fn-ptr0, fn-ptr1, ... }
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

# _process_control_chain($ctx, $return_node) -> void
#
# Walk the control chain from $return_node and drive each control node through
# $ctx->process_control_node (VarDecl/Assign/If/Loop). Shared by the top-level
# graph (lower_with_elaboration) and each method body (_emit_class_registry_ir)
# so a branched method body — an if/else whose arms store a field — lowers to
# real basic blocks exactly like a branched top-level statement, instead of the
# old flat body_stmts list that stopped at the Region and dropped the arms.
#
# When Return.control_in is a Region (not an If/Loop directly), we walk via the
# Region's head back-pointer to find the If/Loop that owns it, then continue
# from head.control_in. This matches the Elaborate pass's M2 path.
sub _process_control_chain {
    my ($ctx, $return_node) = @_;

    my @chain;
    my %seen;
    # Seed the control chain from Return.control_in. The producer's R1.0
    # Call-pin (perl5-son 40d8f8b) pins every Call's control_in unconditionally,
    # void or not, so a trailing void statement-effect Call is never carried as
    # an extra Return input — it rides Return.control_in's own chain like any
    # other effect. A Return's inputs is always exactly [value].
    my @seeds = grep { defined && blessed($_) } ($return_node->control_in);
    for my $ctrl (@seeds) {
        while (defined $ctrl && blessed($ctrl)) {
            last if $seen{ $ctrl->id }++;
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
    }
    # Memory-SSA: scan the graph's memory shape (a store under a branch/loop
    # needs phase 2b), then freeze the element reads valid at ENTRY
    # (memory=MemStart), before the control chain emits any store, so a pre-store
    # read observes the initial array state. MemStart is a data node (not in the
    # chain); find it from the return-reachable graph.
    $ctx->_scan_memory_shape($return_node);
    my $memstart = $ctx->_find_memstart($return_node);
    $ctx->_freeze_memory_reads($memstart) if defined $memstart;

    for my $node (reverse @chain) {
        $ctx->process_control_node($node);
    }
    return;
}

# lower_with_elaboration($class, $ret_node, $elab, %opts) -> $llvm_ir_text
#
# %opts: mop => a SEALED Chalk::MOP carrying class structure (required when
# the graph contains class_name Calls; see _build_registry_from_mop).
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
    _process_control_chain($ctx, $return_node);

    my $value_node  = $return_node->inputs->[0];
    my $result_ref  = $ctx->lower_value($value_node);
    my $result_repr = $value_node->representation;

    # program_mode: this graph IS the whole program, not a value-under-test
    # wrapped by the corpus harness. The type-tag epilogue below exists ONLY so
    # the corpus's return-value oracle (son-corpus-wide.t) can read back what a
    # fragment evaluated to; a standalone program must print exactly what it
    # printed, full stop. Defaults OFF: the corpus depends on the tag being
    # there. Every file-scoring gate sets it (t/lib/.../ProgramRunner.pm).
    my $program_mode = $opts{program_mode};

    my @lines;
    push @lines, '; Generated by Chalk::Target::LLVM (elaboration pass) - dominator-tree placement';
    push @lines, '';

    # Type-tagged output: both sides (perl oracle and lli) emit a canonical tag
    # so Bool is distinguishable from its Str coercion. Tags: Int:<n> Num:<g> Bool:1/Bool:
    # Format strings and string constants are per-representation, libperl-free.
    if ($program_mode) {
        # No epilogue globals — program_mode suppresses the whole type-tag print.
    }
    elsif (!defined $result_repr || $result_repr eq 'Int') {
        # "Int:%lld\n\0" = I,n,t,:,%,l,l,d,\n,\0 = 10 bytes = [10 x i8]
        # %lld (not %d) so printf reads the full i64 payload -- Perl Int is 64-bit
        # and a bare %d truncates the varargs read to 32 bits on LP64 targets.
        push @lines, '@fmt = private unnamed_addr constant [10 x i8] c"Int:%lld\0A\00", align 1';
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
        # "Int:%lld\n\0" = 10 bytes (full i64 payload, not a 32-bit-truncated read); "Undef:\n\0" = 8 bytes.
        push @lines, '@fmt_slot_int   = private unnamed_addr constant [10 x i8] c"Int:%lld\0A\00",  align 1';
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

    # Print emits its list args with a raw (untagged) printf format per arg type.
    # These are distinct from the return-value epilogue formats (which prepend a
    # type tag): a printed value is the raw content, not a tagged result.
    if ($ctx->{_need_print_str_fmt}) {
        # "%.*s\0" = 5 bytes = [5 x i8]
        push @lines, '@fmt_print_str = private unnamed_addr constant [5 x i8] c"%.*s\00", align 1';
    }
    if ($ctx->{_need_print_int_fmt}) {
        # "%lld\0" = %,l,l,d,\0 = 5 bytes = [5 x i8]
        # %lld so printf reads the full i64 arg -- a bare %d truncates the
        # varargs read to 32 bits on LP64 targets.
        push @lines, '@fmt_print_int = private unnamed_addr constant [5 x i8] c"%lld\00", align 1';
    }

    if ($ctx->{_need_num_fmt}) {
        # "%.15g\0" = 6 bytes = [6 x i8]. This is perl's own float
        # stringification rule, verified against perl 5.42 on the corpus floats
        # and on t/base/num.t's cases (0.1, 1e+34, 1.000001, 0.0005).
        push @lines, '@fmt_num_g = private unnamed_addr constant [6 x i8] c"%.15g\00", align 1';
    }

    push @lines, '';
    push @lines, 'declare i32 @printf(i8* nocapture readonly, ...)';
    # snprintf renders a Num to Str: measure with a null buffer, then render.
    # Same host-interface class as printf -- a plain C function, not libperl.
    push @lines, 'declare i32 @snprintf(i8* nocapture, i64, i8* nocapture readonly, ...)'
        if $ctx->{_need_snprintf};

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

    # Emit package-scalar globals (StashAccess): one mutable i64 slot per
    # package/global scalar (`our $g`), keyed by qualified name in _pkg_globals so
    # each is emitted exactly once and store/read resolve the same slot. Zero-init:
    # an unwritten package scalar reads as 0 (the numeric undef the backend uses).
    if (defined $ctx->{_pkg_globals} && %{ $ctx->{_pkg_globals} }) {
        push @lines, '';
        for my $qual (sort keys $ctx->{_pkg_globals}->%*) {
            my $gname = $ctx->{_pkg_globals}{$qual};
            push @lines, "$gname = internal global i64 0, align 8  ; package scalar \$$qual";
        }
    }

    # Emit Str package-scalar globals (StashAccess with a Str repr): a PAIR of
    # mutable slots per qualified name — an i8* ptr (null-init) and an i64 len
    # (zero-init). An unwritten Str package scalar reads as (null, 0), an empty
    # string. Emitted once each via the _pkg_str_globals dedupe map.
    if (defined $ctx->{_pkg_str_globals} && %{ $ctx->{_pkg_str_globals} }) {
        push @lines, '';
        for my $qual (sort keys $ctx->{_pkg_str_globals}->%*) {
            my ($pname, $lname) = $ctx->{_pkg_str_globals}{$qual}->@*;
            push @lines, "$pname = internal global i8* null, align 8  ; Str package scalar \$$qual (ptr)";
            push @lines, "$lname = internal global i64 0, align 8  ; Str package scalar \$$qual (len)";
        }
    }

    # Emit Num package-scalar globals (StashAccess with a Num repr): one mutable
    # `double` slot per qualified name, zero-init — an unwritten Num package
    # scalar reads as 0.0, the numeric undef the backend uses. Its own slot
    # rather than the Int i64 one so the read knows which face the bits hold.
    if (defined $ctx->{_pkg_num_globals} && %{ $ctx->{_pkg_num_globals} }) {
        push @lines, '';
        for my $qual (sort keys $ctx->{_pkg_num_globals}->%*) {
            my $nname = $ctx->{_pkg_num_globals}{$qual};
            push @lines, "$nname = internal global double 0.0, align 8  ; Num package scalar \$$qual";
        }
    }

    # Declare malloc/memcpy when Str concat or aggregate operations were emitted.
    # These are plain C host-interface functions — NOT libperl.
    if ($ctx->{_need_malloc_memcpy}) {
        push @lines, 'declare i8* @malloc(i64)';
        push @lines, 'declare i8* @memcpy(i8*, i8*, i64)';
    }

    # Declare exit when a `die` arm was lowered (Unwind -> exit(255) + unreachable).
    # A plain C host-interface function — NOT libperl.
    if ($ctx->{_need_exit}) {
        push @lines, 'declare void @exit(i32)';
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

    # %Str, the first-class Str VALUE type. Emitted here rather than in the
    # class-registry prologue because _need_str_type is set DURING lowering (by
    # _str_value), and this block runs after it — the same ordering the
    # _need_aggregate_types flag above relies on. Declaring it in the earlier
    # prologue would need a pre-scan, which is the trap the _need_strpair "I3"
    # re-emit below exists to patch around.
    if ($ctx->{_need_str_type} && !$ctx->{_str_type_emitted}) {
        push @lines, '; Str VALUE type (layout: Context::_str_fields)';
        push @lines, Chalk::Target::LLVM::Context::_str_type_decl();
        $ctx->{_str_type_emitted} = 1;
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
        push @lines, '; StrPair for Str values (post-class re-emit, I3; layout: Context::_strpair_fields)';
        push @lines, Chalk::Target::LLVM::Context::_strpair_type_decl();
        $ctx->{_strpair_emitted} = 1;
    }

    push @lines, '';
    push @lines, 'define i32 @main() {';

    # Current block renders last: the epilogue lines below (printf + ret)
    # attach textually to the final rendered block.
    push @lines, _render_context_blocks($ctx, 0);

    if ($program_mode) {
        # No epilogue printf — program_mode suppresses the type-tag print.
        # The correct `ret i32 0` below is still emitted.
    }
    elsif (!defined $result_repr || $result_repr eq 'Int') {
        push @lines, '  %fmt_ptr = getelementptr inbounds [10 x i8], [10 x i8]* @fmt, i64 0, i64 0';
        push @lines, "  call i32 (i8*, ...) \@printf(i8* %fmt_ptr, i64 $result_ref)";
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
        # A Str VALUE is the %Str aggregate, so the epilogue must destructure it
        # before handing a pointer to printf. Emitted inline because this block
        # pushes onto @lines directly rather than through the context, so
        # _str_parts (which emits into the context's current block) cannot be
        # used here — the same constraint the method-return ABI has.
        #
        # Keyed on the REPR, not on the _str_aggregates registry. The registry
        # records refs minted by _str_value, and a PHI is never minted there —
        # it is emitted as `phi %Str [...]` by the merge code and so is an
        # aggregate that the registry has never heard of. Since we are already
        # inside `$result_repr eq 'Str'` and every Str value is now an
        # aggregate, the repr IS the answer, and asking a side registry instead
        # is the same mistake this migration exists to remove.
        push @lines, "  %result_str_p = extractvalue %Str $result_ref, 0  ; epilogue: %Str.ptr";
        push @lines, "  %result_str_l = extractvalue %Str $result_ref, 1  ; epilogue: %Str.len";
        $result_ref = '%result_str_p';
        my $len_ref = '%result_str_l';

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
        push @lines, '  %slot_fmt_int_ptr = getelementptr inbounds [10 x i8], [10 x i8]* @fmt_slot_int, i64 0, i64 0';
        push @lines, "  call i32 (i8*, ...) \@printf(i8* %slot_fmt_int_ptr, i64 $pay_val)";
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
# The lowering context and its Elaborate-driven subclass live in sibling
# files. Load them AFTER the driver subs above are defined: the Context
# glob-aliases \&Chalk::Target::LLVM::_require_repr, so that name must exist.
# Context must load before ElaboratedContext (which isa Context).
# ---------------------------------------------------------------------------
require Chalk::Target::LLVM::Context;
require Chalk::Target::LLVM::ElaboratedContext;

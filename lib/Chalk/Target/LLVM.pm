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

# A method's function TYPE is its return type applied to (i8*). There is one
# definition of that, in Chalk::Target::LLVM::Context, and it derives from
# _method_fn_llvm_ret_type below -- so the vtable bitcast, the call-site cast,
# and the definition can never disagree.
#
# A SECOND copy of this function lived here and answered from its own literal
# chain. It had already drifted: Context's grew a `Scalar` arm that this one
# never got, so a Scalar-returning method died here while lowering fine there.
# Two functions with the same name in different packages is how that stayed
# invisible.

# _method_fn_llvm_ret_type($repr) -> LLVM return type for method function header
sub _method_fn_llvm_ret_type {
    my ($repr) = @_;

    # An absent repr is answered as Int HERE and nowhere else. This is a real
    # third authority -- it decides a machine type with no Chalk type in hand,
    # which _repr_to_llvm_type refuses outright -- and it is kept only because
    # callers rely on it today. It is deliberately NOT pushed down into the
    # type map: the map's refusal is correct, and the default is this
    # function's own leniency, visible at the one site that grants it.
    $repr //= 'Int';

    # Str is the ONLY divergence from %_REPR_LLVM_TYPE, and it is a genuine
    # one: a Str VALUE is %Str (ptr,len,enc) but a Str RETURN crosses the
    # function boundary as %Str (ptr,len).
    return '%Str' if $repr eq 'Str';

    # Every other representation DEFERS. The literal chain that stood here
    # (i64/i1/double/i1/%Slot) answered the same question %_REPR_LLVM_TYPE
    # answers, from its own copy of the answers -- and it had drifted twice by
    # the time it was collapsed:
    #
    #   Scalar is the un-narrowed cell (perigrin, 2026-08-29): a method whose
    #   return type was never narrowed returns the uniform %Slot. That arm was
    #   missing here while _method_fn_type already answered '%Slot (i8*)' for
    #   the POINTER, so a Scalar-returning method could be pointed at but not
    #   called -- the two authorities the call site assumes are one had drifted
    #   apart.
    #
    # Deferring is what makes a third drift impossible rather than merely
    # unlikely: there is no longer a second set of answers to disagree with.
    return Chalk::Target::LLVM::Context::_repr_to_llvm_type($repr);
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
    # ->value() is inputs[0], the LIST reading -- see Return.pm. [-1]
    # silently became the scalar face when a Return gained a second input.
    my $value = $returns[0]->value();
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
# _method_param_index($mop_method) -> { '$name' => positional index }
#
# The declared parameter names, mapped to the argument slot each one binds. A
# body that reads a parameter as a PAD ACCESS (because it forwards it rather
# than consuming it) has no Parameter node to carry the index, so the name is
# the only handle -- and the declaration is where the name and the position are
# recorded together.
sub _method_param_index {
    my ($m) = @_;
    my %idx;
    return \%idx unless $m && $m->can('params') && ref($m->params) eq 'ARRAY';
    my @decl = $m->params->@*;
    for my $i (0 .. $#decl) {
        # A method's params are records; a SUB's are bare names (the wire's
        # `params` passes through declare_sub unchanged). Both reach here.
        my $d = $decl[$i];
        my $n = ref($d) eq 'HASH' ? $d->{name} : $d;
        next unless defined $n && length $n;
        $idx{$n} = $i;
    }
    return \%idx;
}

# _method_param_decl(\@param_reprs) -> the formal parameter list text,
# invocant included, e.g. 'i8* %self, i64 %arg0'.
#
# THE ONE PLACE THAT NAMES THE ARGUMENTS. The definition, an inherited
# forwarder's call, and the vtable's fn-pointer cast must agree exactly or lli
# rejects the module -- and `_lower_parameter` reads %arg$i on the strength of
# the names chosen here. Keeping all of that in one sub is why they cannot
# drift apart.
#
# The same text serves a define's FORMALS and a forwarder's ACTUALS, because in
# LLVM both are `<type> <name>`. An earlier `_method_param_fwd` wrapper existed
# to mark those as separate questions; it delegated straight here, so the
# separation was asserted in a comment and absent from the code. One name, one
# body, nothing to drift.
sub _method_param_decl {
    my ($param_reprs) = @_;
    my @d = ('i8* %self');
    my $i = 0;
    for my $r (@{ $param_reprs // [] }) {
        push @d, _method_fn_llvm_ret_type($r) . ' %arg' . $i;
        $i++;
    }
    return join(', ', @d);
}

# _method_param_reprs($mop_method) -> \@reprs, one per DECLARED parameter,
# dense and ordered by index.
#
# TWO AUTHORITIES, EACH ANSWERING THE QUESTION IT CAN. The ARITY comes from the
# declared signature the producer ships (`method_signatures`, carried onto the
# metaobject by the loader); the TYPE of each parameter comes from the body
# graph's Parameter nodes.
#
# The split is forced, not stylistic. The graph records a Parameter node only
# for a parameter the body READS, so it is a lossy view of the declaration:
#
#     method m($k)      { 42 }        no Parameter node at all
#     method m($a, $b)  { $b }        one node, at index 1
#     method m($a,$b,$c){ $a + $c }   two nodes, at indices 0 and 2
#     method outer($k)  { $self->inner($k) }   the read is PadAccess, not Parameter
#
# Deriving arity from those nodes undercounts every one of them, and the emitted
# signature then disagrees with the call site. An earlier version of this sub did
# exactly that, on the stated premise that "a method's parameters are exactly its
# Parameter nodes" -- which is false, and refused ~57 of the 503 parameterized
# methods in lib/Chalk (interface-conformance parameters like `$ctx` and `%opts`
# are routinely unread).
#
# THE LIST IS DENSE BY CONSTRUCTION -- index N really is position N -- because
# `_method_param_decl` names arguments POSITIONALLY (%arg0, %arg1) while
# `_lower_parameter` reads them by the node's own index. Compacting a sparse
# index map decouples those two: for the `{0,2}` case above, a compacted list
# declares %arg0,%arg1 while the body emits %arg2, which is an undeclared
# register and invalid IR rather than a diagnosable refusal.
#
# A parameter with no Parameter node has no type to read, and `Scalar` is the
# honest answer: the body never constrains it, so the uniform tagged cell is
# exactly what is known. It is a real lattice member with a machine encoding
# (%Slot), not a placeholder.
sub _method_param_reprs {
    my ($m) = @_;
    return [] unless $m;

    my $declared = ($m->can('params') && ref($m->params) eq 'ARRAY')
        ? $m->params : [];
    return [] unless @$declared;

    # Types from the graph, keyed by the SAME index space the declaration uses.
    #
    # TWO SPELLINGS OF THE SAME READ. A parameter CONSUMED by an operation is a
    # `Parameter` node carrying its own index; one FORWARDED to another call is
    # a `PadAccess` carrying only its name, which the declaration maps back to
    # an index. Both are the parameter, so both are read here -- taking the type
    # from whichever spelling the body used.
    #
    # Without the PadAccess arm a forwarded parameter falls to the `Scalar`
    # default below, and the emitted define declares %Slot where the callee it
    # forwards to expects i64: lli refuses with "'%arg0' defined with type
    # '%Slot' but expected 'i64'". The type WAS known -- the loader stamps that
    # pad read from the callsite -- it was simply not being looked at.
    my %repr_at;
    my %index_of;
    my @decl_names =
        map { ref($_) eq 'HASH' ? ($_->{name} // '') : ($_ // '') } @$declared;
    $index_of{ $decl_names[$_] } = $_ for 0 .. $#decl_names;

    my $g = $m->can('graph') ? $m->graph : undef;
    if ($g) {
        for my $n (_graph_all_nodes($g)) {
            next unless blessed($n) && $n->can('operation');
            my $op = $n->operation;

            if ($op eq 'Parameter') {
                my $i = $n->can('index') ? $n->index : undef;
                next unless defined $i;
                my $r = $n->representation or next;
                $repr_at{$i} = $r;
            }
            elsif ($op eq 'PadAccess' && $n->can('varname')) {
                my $i = $index_of{ $n->varname // '' };
                next unless defined $i;
                # A Parameter node is the more direct statement of the same
                # fact, so it wins where both exist.
                next if defined $repr_at{$i};
                my $r = $n->representation or next;
                $repr_at{$i} = $r;
            }
        }
    }

    return [ map { $repr_at{$_} // 'Scalar' } 0 .. $#$declared ];
}

# _graph_all_nodes($g) -> every node belonging to the graph.
#
# Delegates to the loader's enumeration rather than repeating it. An earlier
# private walker here followed only `inputs` and `control_in` from the returns,
# on the stated premise that "$g->nodes walks value inputs only" -- Graph::nodes
# documents itself as walking inputs AND consumers, so the premise was false and
# the private walker was strictly weaker: it missed the Parameter in a one-armed
# `if` entirely (3 nodes seen against 6).
sub _graph_all_nodes {
    my ($g) = @_;
    return Chalk::IR::Analysis::_all_graph_nodes($g);
}

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
            # `return_repr` is a FORCING point: it names a type in the emitted
            # signature, so it must be a real representation. The producer's
            # declaration is authoritative when it determined one; `Unknown`
            # means inference did NOT, and there is no encoding of `Unknown` --
            # so fall through to the body root rather than emit it as a type.
            return_repr => (
                ( ( $s->return_type // 'Unknown' ) ne 'Unknown' )
                ? $s->return_type
                : _require_repr($body_node, "MOP::Sub '${cname}::${sname}' body root")
            ),
            uses_args   => $s->uses_args,
        };
    }

    my $mslot = scalar @{ $registry->{$cname}{methods} };

    for my $m ($cls->methods) {
        my $mname     = $m->name;
        my $body_node = _method_body_root($m);
        # Same rule as MOP::Sub above: the producer's declaration is
        # authoritative when it determined one, but `Unknown` means inference
        # did NOT, and `Unknown` has no encoding -- fall through to the body
        # root. (A method's return_type used to be universally undef, which made
        # `//` do this by accident; now that declare_method carries the wire's
        # value it arrives as the lattice top and must be tested for.)
        my $ret_repr  = ( ( $m->return_type // 'Unknown' ) ne 'Unknown' )
            ? $m->return_type
            : _require_repr($body_node, "MOP::Method '$mname' body root");
        unless (grep { ($_->{name} // '') eq $mname } @{ $registry->{$cname}{methods} }) {
            # THE SIGNATURE COMES FROM THE BODY GRAPH, not from a wire field.
            # A method's parameters are exactly its Parameter nodes, each
            # carrying its own index and stamp, so the graph is the authority
            # and there is nothing to keep in sync with it. Sorted by index so
            # the emitted argument order is the declared order rather than
            # whatever order the walk happened to reach them in.
            push @{ $registry->{$cname}{methods} }, {
                name        => $mname,
                body_node   => $body_node,
                body_return => _method_body_return($m),
                return_repr => $ret_repr,
                param_reprs => _method_param_reprs($m),
                param_index => _method_param_index($m),
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

# _emit_class_registry_ir(\%registry, $ctx) -> @llvm_lines
#
# Emits all class-related LLVM IR declarations: type defs, vtable globals,
# class-name constants, and method body define functions.
# Returns a list of LLVM IR text lines to prepend to the module.
sub _emit_class_registry_ir {
    my ($registry, $ctx) = @_;
    my @lines;

    # Determine if any method returns Str -> need %Str type
    my $need_strpair = 0;
    for my $cname (sort keys %$registry) {
        my $reg = $registry->{$cname};
        # Subs share the %Str return ABI, so they must be in this pre-scan
        # too -- a Str-returning SUB in a class whose methods all return Int
        # would otherwise emit insertvalue over an undeclared %Str.
        for my $m (@{ $reg->{methods} }, @{ $reg->{subs} // [] }) {
            $need_strpair = 1 if ($m->{return_repr} // '') eq 'Str';
        }
    }

    # %Str is declared UNCONDITIONALLY here, unlike %Str. This prologue runs
    # BEFORE any method body is lowered, so a pre-scan cannot know whether a body
    # will build one — and %Str is needed by any Str VALUE at all, not merely by
    # a Str-RETURNING method, so the scan above (which keys on return_repr) would
    # miss most uses. An unused type declaration is inert; a missing one makes
    # lli reject the module with "invalid indices for insertvalue".
    push @lines, $ctx->render_str_type_once;

    if ($need_strpair) {
        push @lines, '; StrPair for Str method return values (layout: Context::_strpair_fields)';
        push @lines, $ctx->render_strpair_type_once;
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
            my $ret_repr  = $minfo->{return_repr};
            my $fn_ret    = _method_fn_llvm_ret_type($ret_repr);

            if ($minfo->{inherited_from}) {
                # Inherited method: emit a wrapper that forwards to the parent's impl
                my $parent = $minfo->{inherited_from};
                my $parent_fn = '@' . $parent . '__' . $mname;
                my $p_decl = _method_param_decl($minfo->{param_reprs});
                my $p_fwd   = $p_decl;   # formals and actuals are the same text
                push @lines, "define internal $fn_ret $fn_name($p_decl) {";
                push @lines, 'entry:';
                if ($ret_repr eq 'Str') {
                    push @lines, "  %r = call %Str $parent_fn($p_fwd)";
                    push @lines, '  ret %Str %r';
                }
                elsif ($ret_repr eq 'Num') {
                    # $fn_ret is already this repr's return type (:700); naming
                    # `double` again here was a second authority for the same
                    # answer, in the one place where disagreeing with the
                    # function's own header is guaranteed-invalid IR.
                    push @lines, "  %r = call $fn_ret $parent_fn($p_fwd)";
                    push @lines, "  ret $fn_ret %r";
                }
                elsif ($ret_repr eq 'Boolean') {
                    push @lines, "  %r = call i1 $parent_fn($p_fwd)";
                    push @lines, '  ret i1 %r';
                }
                else {
                    push @lines, "  %r = call i64 $parent_fn($p_fwd)";
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
                # An object field IS a %Slot cell; its subfield indices are
                # named, never literal (a literal is how the last tag attempt
                # aimed a GEP at the wrong bytes).
                my $fi_def = Chalk::Target::LLVM::Context::_slot_idx('defined');
                my $fi_pay = Chalk::Target::LLVM::Context::_slot_idx('payload');
                push @lines, "define internal $fn_ret $fn_name(i8* %self) {  ; :reader for field $fidx";
                push @lines, 'entry:';
                push @lines, "  %obj = bitcast i8* %self to %${cname}.obj*";
                # Load defined bit
                push @lines, "  %def_gep = getelementptr inbounds %${cname}.obj, %${cname}.obj* %obj, i64 0, i32 $slot_idx, i32 $fi_def";
                push @lines, '  %def = load i1, i1* %def_gep';
                # Load payload
                push @lines, "  %pay_gep = getelementptr inbounds %${cname}.obj, %${cname}.obj* %obj, i64 0, i32 $slot_idx, i32 $fi_pay";
                push @lines, '  %pay = load i64, i64* %pay_gep';
                if ($ret_repr eq 'Str') {
                    # payload = StrPair* (as i64) -> cast back and return {ptr, len}
                    push @lines, '  %pair_ptr = inttoptr i64 %pay to %Str*';
                    push @lines, '  %pp_gep = getelementptr inbounds %Str, %Str* %pair_ptr, i64 0, i32 0';
                    push @lines, '  %sp = load i8*, i8** %pp_gep';
                    push @lines, '  %lp_gep = getelementptr inbounds %Str, %Str* %pair_ptr, i64 0, i32 1';
                    push @lines, '  %sl = load i64, i64* %lp_gep';
                    push @lines, '  %r0 = insertvalue %Str undef, i8* %sp, 0';
                    push @lines, '  %r1 = insertvalue %Str %r0, i64 %sl, 1';
                    push @lines, '  ret %Str %r1';
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
            # I1: method_name is used to prefix str_const globals uniquely
            $body_ctx->configure_as_method_body(
                class_name  => $cname,
                method_name => $mname,
                parent_ctx  => $ctx,
                # THE SAME DECLARATION THE SIGNATURE WAS EMITTED FROM, so the
                # name a body reads and the argument the define declares cannot
                # disagree: both are position N of $m->params.
                param_index => $minfo->{param_index} // {},
            );

            # Emit the body's statement effects (field-store Assign, void Call, and
            # any branch-guarded If) in control order BEFORE the return value, so a
            # `method inc { $n += 1 }` writes the field back and a branched `bump`
            # emits both guarded stores. Same mechanism as the top-level graph.
            _process_control_chain($body_ctx, $body_return);

            # Lower the body value node into the method body context
            my $body_val = $body_ctx->lower_value($body_node);

            # need-flag propagation BACK UP (including _need_str_type) happens
            # once, below, via absorb_need_flags_from -- nothing between here
            # and there reads $ctx's flags, so a single absorb after the body
            # is fully rendered covers this without an extra early copy. A
            # method body is lowered in its own Context, so a flag set during
            # that lowering is invisible to the parent $ctx that emits the
            # type declarations — and %Str is declared from $ctx. Without this
            # the body emits insertvalue over an undeclared %Str and lli
            # rejects the module with "invalid indices for insertvalue".
            # (%Str avoids this only by having a pre-scan over
            # return_repr; %Str has none, because it is needed by any Str
            # VALUE rather than only by a Str-returning method.)

            my $body_p_decl = _method_param_decl($minfo->{param_reprs});
            push @lines, "define internal $fn_ret $fn_name($body_p_decl) {  ; method body for ${cname}::${mname}";
            push @lines, 'entry:';

            # Emit all instructions from the body context (current block
            # renders last; the ret lines below attach textually to it).
            push @lines, $body_ctx->render_blocks(1);

            # Emit return instruction
            if ($ret_repr eq 'Str') {
                # Through the seam, not into the table. This was the one direct
                # A Str-returning body hands back a %Str aggregate, so
                # destructure it for the %Str return ABI. Emitted inline
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
                    push @lines, "  %ret_r0 = insertvalue %Str undef, i8* $ptr_val, 0";
                    push @lines, "  %ret_r1 = insertvalue %Str %ret_r0, i64 $len_ref, 1";
                    push @lines, '  ret %Str %ret_r1';
                }
                else {
                    # Compute strlen at runtime
                    push @lines, "  %ret_len = call i64 \@strlen(i8* $ptr_val)";
                    push @lines, "  %ret_r0 = insertvalue %Str undef, i8* $ptr_val, 0";
                    push @lines, "  %ret_r1 = insertvalue %Str %ret_r0, i64 %ret_len, 1";
                    push @lines, '  ret %Str %ret_r1';
                }
            }
            elsif ($ret_repr eq 'Num') {
                push @lines, "  ret $fn_ret $body_val";
            }
            elsif ($ret_repr eq 'Boolean') {
                push @lines, "  ret i1 $body_val";
            }
            elsif ($ret_repr eq 'Undef') {
                # Undef-returning method (discarded if/else field-mutation
                # residual): the body value is the i1 defined-bit (always 0).
                push @lines, "  ret i1 $body_val";
            }
            elsif ($ret_repr eq 'Scalar') {
                # The ABI is %Slot = { i1 defined, i8 tag, i64 payload }.
                #
                # WHETHER TO BOX DEPENDS ON WHAT THE BODY ALREADY IS, and the
                # body node's own repr is what says so. A body that computed a
                # NARROWED value (an Int, a Num) hands back a bare payload and
                # must be boxed. A body whose own repr is already `Scalar`
                # hands back a COMPLETE %Slot -- a `field $s :param = "hi"`
                # read lowers to a tag-dispatched `phi %Slot` -- and boxing
                # that again puts a %Slot where the payload field wants an
                # i64, which lli rejects: "'%tmp_34' defined with type '%Slot'
                # but expected 'i64'". Measured on classes.md field-str-default
                # and "print a method-call result", which failed identically at
                # the same emission site.
                #
                # This arm read "the body value is the PAYLOAD" as though it
                # were always true. It is true only of the narrowed case, which
                # is the only one that had ever reached here.
                my $body_repr = (blessed($body_node)
                                 && $body_node->can('representation'))
                              ? ($body_node->representation // '')
                              : '';

                if ($body_repr eq 'Scalar') {
                    # Already a %Slot: the tag it carries is the reading the
                    # body established, which is strictly better than the
                    # Opaque one this arm would stamp on.
                    push @lines, "  ret %Slot $body_val";
                }
                elsif ($body_repr eq 'Str') {
                    # A STR BODY IS AN AGGREGATE, NOT A PAYLOAD WORD.
                    # `field $s :param = "hi"; method get { $s }` reads the
                    # field as a Str (`%Str = { ptr, len, enc }`) and this arm
                    # stuffed that straight into the i64 payload slot -- lli
                    # refused with "'%tmp_11' defined with type '%Str' but
                    # expected 'i64'".
                    #
                    # A Str lives in a Slot as a POINTER TO A HEAP %Str, which
                    # is exactly how the CONSTRUCTOR wrote this field, so the
                    # return re-boxes it the same way rather than inventing a
                    # second encoding. One encoding written from both ends is
                    # the property the read half relies on.
                    my $C = 'Chalk::Target::LLVM::Context';
                    # Declared in this arm rather than hoisted: the else-branch
                    # below has its own copies, and one shared set would outlive
                    # the arm that needs it.
                    my $ri_def = $C->can('_slot_idx')->('defined');
                    my $ri_tag = $C->can('_slot_idx')->('tag');
                    my $ri_pay = $C->can('_slot_idx')->('payload');
                    $ctx->{_need_str_type} = 1;
                    push @lines, "  %ret_xp = extractvalue %Str $body_val, "
                               . $C->can('_str_idx')->('ptr') . "  ; %Str.ptr";
                    push @lines, "  %ret_xl = extractvalue %Str $body_val, "
                               . $C->can('_str_idx')->('len') . "  ; %Str.len";
                    push @lines, "  %ret_sm = call i8* \@malloc(i64 "
                               . $C->can('_sizeof_llvm_type')->('%Str')
                               . ")  ; boxed Str for a Str method return";
                    push @lines, "  %ret_pp = bitcast i8* %ret_sm to %Str*";
                    push @lines, "  %ret_g0 = getelementptr inbounds %Str, %Str* %ret_pp, i64 0, i32 "
                               . $C->can('_str_idx')->('ptr');
                    push @lines, "  store i8* %ret_xp, i8** %ret_g0  ; %Str.ptr";
                    push @lines, "  %ret_g1 = getelementptr inbounds %Str, %Str* %ret_pp, i64 0, i32 "
                               . $C->can('_str_idx')->('len');
                    push @lines, "  store i64 %ret_xl, i64* %ret_g1  ; %Str.len";
                    # enc, like the two boxing sites in Context.pm: a field
                    # left as malloc garbage is invisible until it has a
                    # reader, and Chalk's own source is non-ASCII, so one is
                    # coming.
                    push @lines, "  %ret_g2 = getelementptr inbounds %Str, %Str* %ret_pp, i64 0, i32 "
                               . $C->can('_str_idx')->('enc');
                    push @lines, "  store i32 " . $C->can('_str_enc')->('utf8')
                               . ", i32* %ret_g2  ; %Str.enc (utf8)";
                    push @lines, "  %ret_pi = ptrtoint %Str* %ret_pp to i64";
                    my $str_tag = $C->can('_slot_tag_value')->(
                                      $C->can('_slot_tag_for_repr')->('Str'));
                    push @lines, "  %ret_s0 = insertvalue %Slot undef, i1 true, $ri_def";
                    push @lines, "  %ret_st = insertvalue %Slot %ret_s0, i8 $str_tag, $ri_tag";
                    push @lines, "  %ret_s1 = insertvalue %Slot %ret_st, i64 %ret_pi, $ri_pay";
                    push @lines, '  ret %Slot %ret_s1';
                }
                else {
                    my $ri_def = Chalk::Target::LLVM::Context::_slot_idx('defined');
                    my $ri_tag = Chalk::Target::LLVM::Context::_slot_idx('tag');
                    my $ri_pay = Chalk::Target::LLVM::Context::_slot_idx('payload');
                    # The declared return repr is Scalar -- un-narrowed -- so the
                    # reading of these payload bits was never established. 'Opaque'
                    # says exactly that; 'Undef' would falsely assert the value IS
                    # undef when the defined bit right above says it is not.
                    my $ri_tagv = Chalk::Target::LLVM::Context::_slot_tag_value(
                        Chalk::Target::LLVM::Context::_slot_tag_for_repr($ret_repr));
                    push @lines, "  %ret_s0 = insertvalue %Slot undef, i1 true, $ri_def";
                    push @lines, "  %ret_st = insertvalue %Slot %ret_s0, i8 $ri_tagv, $ri_tag";
                    push @lines, "  %ret_s1 = insertvalue %Slot %ret_st, i64 $body_val, $ri_pay";
                    push @lines, '  ret %Slot %ret_s1';
                }
            }
            else {
                push @lines, "  ret i64 $body_val";
            }
            push @lines, '}';
            push @lines, '';

            # Propagate _need_* flags to the main ctx (F6 bug class) and
            # emit the body's string-constant globals into the class section.
            $ctx->absorb_need_flags_from($body_ctx);
            push @lines, $body_ctx->render_str_globals;
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
            my $ret_repr = $sinfo->{return_repr};
            my $fn_ret   = _method_fn_llvm_ret_type($ret_repr);

            my $body_return = $sinfo->{body_return};
            my $body_node   = $sinfo->{body_node};
            my $body_dom    = Chalk::IR::Schedule::Dominators->from_return_node($body_return);
            my $body_elab   = Chalk::IR::Schedule::Elaborate->from_return_node($body_return, $body_dom);
            my $body_ctx    = Chalk::Target::LLVM::ElaboratedContext->new(
                elab           => $body_elab,
                class_registry => $registry,
            );
            # has_self => 0: there is no $self to resolve a FieldAccess
            # against. A sub touching a field is a compile error in perl, so a
            # FieldAccess here would be a producer bug and should fail loudly
            # rather than silently bind to a nonexistent invocant.
            $body_ctx->configure_as_method_body(
                class_name  => $cname,
                method_name => $sname,
                has_self    => 0,
                parent_ctx  => $ctx,
            );

            _process_control_chain($body_ctx, $body_return);
            my $body_val = $body_ctx->lower_value($body_node);
            # _need_str_type (and every other NEED_FLAG) is absorbed below via
            # absorb_need_flags_from, once the body is fully rendered.

            push @lines, "define internal $fn_ret $fn_name() {  ; sub body for ${cname}::${sname}";
            push @lines, 'entry:';
            push @lines, $body_ctx->render_blocks(1);

            if ($ret_repr eq 'Str') {
                push @lines, "  %ret_sp = extractvalue %Str $body_val, 0";
                push @lines, "  %ret_sl = extractvalue %Str $body_val, 1";
                push @lines, "  %ret_r0 = insertvalue %Str undef, i8* %ret_sp, 0";
                push @lines, "  %ret_r1 = insertvalue %Str %ret_r0, i64 %ret_sl, 1";
                push @lines, '  ret %Str %ret_r1';
            }
            elsif ($ret_repr eq 'Num')  { push @lines, "  ret $fn_ret $body_val" }
            elsif ($ret_repr eq 'Boolean'
                || $ret_repr eq 'Undef'){ push @lines, "  ret i1 $body_val" }
            elsif ($ret_repr eq 'Scalar') {
                # Boxed into %Slot -- see the sibling site above.
                my $ri_def = Chalk::Target::LLVM::Context::_slot_idx('defined');
                my $ri_tag = Chalk::Target::LLVM::Context::_slot_idx('tag');
                my $ri_pay = Chalk::Target::LLVM::Context::_slot_idx('payload');
                # The declared return repr is Scalar -- un-narrowed -- so the
                # reading of these payload bits was never established. 'Opaque'
                # says exactly that; 'Undef' would falsely assert the value IS
                # undef when the defined bit right above says it is not.
                my $ri_tagv = Chalk::Target::LLVM::Context::_slot_tag_value(
                    Chalk::Target::LLVM::Context::_slot_tag_for_repr($ret_repr));
                push @lines, "  %ret_s0 = insertvalue %Slot undef, i1 true, $ri_def";
                push @lines, "  %ret_st = insertvalue %Slot %ret_s0, i8 $ri_tagv, $ri_tag";
                push @lines, "  %ret_s1 = insertvalue %Slot %ret_st, i64 $body_val, $ri_pay";
                push @lines, '  ret %Slot %ret_s1';
            }
            else                        { push @lines, "  ret i64 $body_val" }
            push @lines, '}';
            push @lines, '';

            $ctx->absorb_need_flags_from($body_ctx);
            push @lines, $body_ctx->render_str_globals;
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
            $adj_ctx->configure_as_method_body(
                class_name     => $cname,
                method_name    => '__ADJUST',
                class_registry => $registry,
                parent_ctx     => $ctx,
            );

            $adj_ctx->lower_value($_) for @adjust_stmts;
            # Same back-propagation as the method-body path above: an ADJUST
            # block is lowered in its own Context, so a %Str built there is
            # invisible to the $ctx that declares the type. absorb_need_flags_from
            # below covers _need_str_type along with every other NEED_FLAG.

            push @lines, "define internal void \@${cname}__ADJUST(i8* %self) {  ; ADJUST blocks for $cname";
            push @lines, 'entry:';
            push @lines, $adj_ctx->render_blocks(1);
            push @lines, '  ret void';
            push @lines, '}';
            push @lines, '';

            # Same flag/global propagation as the method-body loop above.
            $ctx->absorb_need_flags_from($adj_ctx);
            push @lines, $adj_ctx->render_str_globals;
        }

        # Vtable global: @Cls__vtable = { class-name-ptr, fn-ptr0, fn-ptr1, ... }
        my $vt_global = '@' . $cname . '__vtable';
        my @vt_init;
        push @vt_init, "i8* getelementptr inbounds ([$cn_bytes x i8], [$cn_bytes x i8]* $cn_name_global, i64 0, i64 0)";
        for my $minfo (@$methods) {
            my $mname   = $minfo->{name};
            my $fn_name = '@' . $cname . '__' . $mname;
            my $ret_repr = $minfo->{return_repr};
            my $fn_type_str = Chalk::Target::LLVM::Context::_method_fn_type(
                $ret_repr, $minfo->{param_reprs});
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
                    # A HEADLESS REGION IS A MERGE WITH NO RUNTIME TEST, and
                    # `last` here ABANDONED EVERY EFFECT BEHIND IT.
                    #
                    # try/catch builds exactly this: the producer desugars it to
                    # the same shared-control merge an if/else uses, but there
                    # is no condition to branch on, so no If is ever built and
                    # the Region has no head. Measured on
                    # `try { print "in\n"; $x = 1 } catch ($e) { $x = 2 }`:
                    # the chain stopped here and the emitted main() was EMPTY --
                    # both Prints dropped, lli exit 0, nothing printed where
                    # perl prints "in" then 1. A silent wrong answer.
                    #
                    # The Region's INPUTS are its arms' tails, so the chain
                    # continues through them rather than ending. Walking every
                    # arm is what makes the catch arm reachable too -- taking
                    # only the first would fix the case above and leave its
                    # bilateral partner broken.
                    #
                    # The Region itself is NOT pushed: it emits nothing (see
                    # process_control_node, which has no Region arm and never
                    # needed one), and pushing a node that emits nothing is how
                    # this looked handled while dropping everything.
                    my $inputs = $ctrl->can('inputs') ? $ctrl->inputs : undef;
                    for my $arm (grep { blessed($_) } ($inputs ? $inputs->@* : ())) {
                        my $a = $arm;
                        while (defined $a && blessed($a)) {
                            last if $seen{ $a->id }++;

                            # AN UNWIND ON A HEADLESS-REGION ARM IS A CAUGHT
                            # DIE, AND CHALK CANNOT LOWER ONE.
                            #
                            # The merge exists precisely BECAUSE control rejoins
                            # after the catch, so this `die` does not abort the
                            # program -- it transfers to the other arm. Lowering
                            # it as a mainline abort emits `exit(255)` and kills
                            # everything after the try/catch: measured on
                            # `try { die "boom\n" } catch ($e) { print "caught\n" }`,
                            # chalk printed `caught` and exited 255 where perl
                            # prints `caught` then `2` and exits 0.
                            #
                            # Catching needs an LLVM landingpad and a personality
                            # function, which this backend does not have -- the
                            # TryCatch NODE arm in Context.pm already says so.
                            # That GAP is unreachable here because the producer
                            # desugars try/catch to Region+Unwind rather than
                            # building a TryCatch node, so the refusal has to be
                            # stated again at the shape it actually arrives in.
                            if (($a->can('operation') ? $a->operation : '') eq 'Unwind') {
                                die "GAP: a `die` inside a try block is not lowered "
                                  . "runtime-free -- catching it needs an LLVM "
                                  . "landingpad + personality function. The producer "
                                  . "desugars try/catch to a headless Region, so this "
                                  . "Unwind is a CAUGHT die, not a mainline abort.\n";
                            }

                            push @chain, $a;
                            $a = $a->can('control_in') ? $a->control_in : undef;
                        }
                    }
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
    $ctx->require_class_support if defined $class_registry && %$class_registry;

    # Process the control chain — VarDecl/Assign/If/Loop.
    _process_control_chain($ctx, $return_node);

    my $value_node  = $return_node->inputs->[0];
    my $result_ref  = $ctx->lower_value($value_node);
    my $result_repr = $value_node->representation;

    my @lines;
    push @lines, '; Generated by Chalk::Target::LLVM (elaboration pass) - dominator-tree placement';
    push @lines, '';


    # Pre-class-lowering half of the module prologue: every global/helper
    # this context's NEED_FLAGS say the module will use, given what has been
    # lowered so far (not yet including any class method body — see the F6
    # post-class re-emit call below).
    push @lines, $ctx->render_need_flag_prologue($result_repr);

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
        push @lines, $ctx->require_strlen_once;
        my @class_lines = _emit_class_registry_ir($class_registry, $ctx);
        push @lines, @class_lines;
    }

    # Post-class-lowering half (the F6 fix): a method body or ADJUST block
    # lowers in its OWN Context and is only absorbed into $ctx (via
    # absorb_need_flags_from) after _emit_class_registry_ir runs above, so a
    # flag it set is invisible to render_need_flag_prologue, which ran before
    # any body lowered.
    push @lines, $ctx->render_need_flag_postclass_reemit($result_repr);

    push @lines, '';
    push @lines, 'define i32 @main() {';

    # Current block renders last: the epilogue lines below (printf + ret)
    # attach textually to the final rendered block.
    push @lines, $ctx->render_blocks(0);


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

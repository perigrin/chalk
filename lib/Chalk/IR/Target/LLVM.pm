# ABOUTME: SoN->LLVM IR lowering pass for the typed-representation model (Phase 3a/3b/3c/cfg-phi/G3-Str).
# ABOUTME: Lowers typed SoN graphs to LLVM IR text: arithmetic, VarDecl/PadAccess, control-flow, and Str.
package Chalk::IR::Target::LLVM;
use 5.42.0;
use utf8;

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

# lower_with_elaboration($class, $ret_node, $elab) -> $llvm_ir_text
#
# Variant of lower() that accepts a pre-computed Elaborate pass result for
# phi placement at Region merge points. The $elab object carries emitted_phis()
# — the list of { block_id, vd_id, incoming => [...] } records that the
# elaboration pass determined should be phi nodes at merge blocks. The LLVM
# backend places phis using the dominator-tree scoped value map.
sub lower_with_elaboration {
    my ($class, $return_node, $elab) = @_;

    # Build a context that knows the elaboration phi plan.
    my $ctx = Chalk::IR::Target::LLVM::ElaboratedContext->new(elab => $elab);

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
    push @lines, '; Generated by Chalk::IR::Target::LLVM (elaboration pass) - dominator-tree placement';
    push @lines, '';

    # Type-tagged output: both sides (perl oracle and lli) emit a canonical tag
    # so Bool is distinguishable from its Str coercion. Tags: Int:<n> Num:<g> Bool:1/Bool:
    # Format strings and string constants are per-representation, libperl-free.
    if (!defined $result_repr || $result_repr eq 'Int') {
        # "Int:%d\n" = 7 bytes: 'I','n','t',':','%','d','\n','\0' = [8 x i8]
        push @lines, '@fmt = private unnamed_addr constant [8 x i8] c"Int:%d\0A\00", align 1';
    }
    elsif ($result_repr eq 'Num') {
        # "Num:%g\n" = 7 bytes + NUL = [8 x i8]
        push @lines, '@fmt = private unnamed_addr constant [8 x i8] c"Num:%g\0A\00", align 1';
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
    else {
        die "LLVM backend (elaboration): cannot emit return of repr=$result_repr";
    }

    # When body lowering set _need_bool_str_globals (Coerce(Bool->Str) used
    # internally in a non-Str-return graph), emit those globals now. They are
    # always emitted for a Str result repr (above); this branch handles the
    # case where the return is not Str but the body contains a Coerce(Bool->Str).
    if ($ctx->{_need_bool_str_globals} && $result_repr ne 'Str') {
        push @lines, '@coerce_bool_str_true  = private unnamed_addr constant [2 x i8] c"1\00", align 1';
        push @lines, '@coerce_bool_str_false = private unnamed_addr constant [1 x i8] c"\00",   align 1';
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

    # Declare malloc/memcpy when Str concat operations were emitted.
    # These are plain C host-interface functions — NOT libperl.
    if ($ctx->{_need_malloc_memcpy}) {
        push @lines, 'declare i8* @malloc(i64)';
        push @lines, 'declare i8* @memcpy(i8*, i8*, i64)';
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
        push @lines, '  %fmt_ptr = getelementptr inbounds [8 x i8], [8 x i8]* @fmt, i64 0, i64 0';
        push @lines, "  call i32 (i8*, ...) \@printf(i8* %fmt_ptr, double $result_ref)";
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

    push @lines, '  ret i32 0';
    push @lines, '}';

    return join("\n", @lines) . "\n";
}

# ---------------------------------------------------------------------------
# Internal lowering context
# ---------------------------------------------------------------------------
package Chalk::IR::Target::LLVM::Context;
use 5.42.0;
use utf8;

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

    if (!defined $repr || $repr eq 'Scalar') {
        if (!defined $repr) {
            # Unassigned representation — treat as immediate if it looks like an integer
            if (defined $val && $val =~ /\A-?\d+\z/) {
                my $ref = $self->_fresh;
                $self->_emit("  $ref = add i64 0, $val          ; Constant($val, untyped -> Int literal)");
                $self->{cache}{$node->id} = $ref;
                return $ref;
            }
        }
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
        my $gidx    = scalar @{ $self->{_str_globals} };
        my $gname   = "\@str_const_$gidx";
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
    die "GAP: $op with repr=Scalar reached LLVM backend" if defined $repr && $repr eq 'Scalar';

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

    my $repr = $node->representation // 'Int';
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

    my $repr = $node->representation // 'Int';
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

# _lower_assign: lower the RHS value and update the var_table for the target VarDecl.
# Returns the new SSA value.
sub _lower_assign {
    my ($self, $node) = @_;

    my $repr = $node->representation // 'Int';
    if ($repr eq 'Scalar') {
        die "GAP: Assign with repr=Scalar reached LLVM backend — cannot lower runtime-free.";
    }

    # inputs[0] = lhs (PadAccess or direct VarDecl reference)
    # inputs[1] = rhs (new value)
    my $lhs     = $node->inputs->[0];
    my $rhs     = $node->inputs->[1];

    my $rhs_ref = $self->lower_value($rhs);

    # Find the VarDecl the lhs PadAccess points to.
    my $vd = $lhs;
    if (defined $vd && $vd->operation eq 'PadAccess') {
        $vd = $lhs->inputs->[0];
    }
    unless (defined $vd && $vd->operation eq 'VarDecl') {
        die "LLVM backend: Assign lhs must be a PadAccess(VarDecl) or VarDecl; "
          . "got " . (defined $vd ? $vd->operation : 'undef');
    }

    # Update var_table: the variable now holds the new SSA value.
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
    my $true_repr = $true_node->representation // 'Int';
    my $fals_repr = $fals_node->representation // 'Int';

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

    my $lhs_repr = $lhs_node->representation // 'Int';

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
    my $op_repr = $operand->representation // 'Int';

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

        my $repr = $phi_node->representation // 'Int';
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

        my $repr      = $phi_node->representation // 'Int';
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

1;

# ---------------------------------------------------------------------------
# ElaboratedContext: a Context subclass that uses the Elaborate pass output
# for phi placement at Region merges. Placement is driven by the dominator tree
# and scoped value map computed by Chalk::IR::Schedule::Elaborate.
# ---------------------------------------------------------------------------
package Chalk::IR::Target::LLVM::ElaboratedContext;
use 5.42.0;
use utf8;

use parent -norequire, 'Chalk::IR::Target::LLVM::Context';

sub new {
    my ($class, %args) = @_;
    my $elab = delete $args{elab};
    my $self  = $class->SUPER::new(%args);
    $self->{elab} = $elab;
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
            my $llvm_type = Chalk::IR::Target::LLVM::Context::_repr_to_llvm_type($var_repr);

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

        my $repr      = $phi_node->representation // 'Int';
        my $llvm_type = Chalk::IR::Target::LLVM::Context::_repr_to_llvm_type($repr);
        my $result    = $self->_fresh;
        $self->_emit("  $result = phi $llvm_type [ $then_val, %$then_label ], [ $else_val, %$else_label ]  ; Region phi");
        $self->{cache}{ $phi_node->id } = $result;
    }
}

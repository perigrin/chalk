# ABOUTME: Rooted-wiring gate for shape_subset_check: the 6 shape teeth
# ABOUTME: (operand/store/fold/deref/field/any/sigil) must FAIL; legit subset shapes PASS.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib', 't/lib';
use Chalk::CodeGen::Harness::MdtestCorpus;

my $H = 'Chalk::CodeGen::Harness::MdtestCorpus';

# verdict($spec_ir, $real_ir) -> shape_subset_check verdict against the real
# graph built from $real_ir.
sub verdict ($spec, $real) {
    my ($rn) = $H->build_graph_from_ir($real);
    return $H->shape_subset_check($spec, $rn)->{verdict};
}

# ---------------------------------------------------------------------------
# The 6 shape teeth MUST FAIL (rooted wiring rejects them). These are wrong
# STRUCTURE — an operand/store/field/deref-sigil the spec names is missing or
# miswired. A wrong return VALUE that keeps the spec structure intact (H3, the
# subset-value wrap below) is NOT a shape tooth — it is the behavior leg's job.
# ---------------------------------------------------------------------------

# T1 assign-select: dropped store. my $x; $x=1; $x+1 (perl=2); wrong returns 1.
{
    my $spec = <<'IR';
%xn=Constant("$x") :Str
%vx=VarDecl(%xn) :Int
%one=Constant(1) :Int
%lhs=PadAccess(%vx, "$x") :Int
%as=Assign(%lhs, %one) :Int
%rx=PadAccess(%vx, "$x") :Int
%onep=Constant(1) :Int
%sum=Add(%rx, %onep) :Int
return %sum
control: %vx -> %as
IR
    my $wrong = <<'IR';
%xn=Constant("$x") :Str
%vx=VarDecl(%xn) :Int
%rx=PadAccess(%vx, "$x") :Int
%one=Constant(1) :Int
%sum=Add(%rx, %one) :Int
return %sum
IR
    is verdict($spec, $wrong), 'FAIL', 'T1 assign-select (dropped store) FAILs';
}

# T2 pad operand swap: 3 // 7 (perl=3); wrong DefinedOr(7,3) returns 7.
{
    my $spec = <<'IR';
%an=Constant("$a") :Str
%a1=Constant(3) :Int
%va=VarDecl(%an, %a1) :Int
%bn=Constant("$b") :Str
%b1=Constant(7) :Int
%vb=VarDecl(%bn, %b1) :Int
%pa=PadAccess(%va, "$a") :Int
%pb=PadAccess(%vb, "$b") :Int
%r=DefinedOr(%pa, %pb) :Int
return %r
IR
    my $wrong = <<'IR';
%cb=Constant(7) :Int
%ca=Constant(3) :Int
%r=DefinedOr(%cb, %ca) :Int
return %r
IR
    is verdict($spec, $wrong), 'FAIL', 'T2 pad operand swap FAILs';
}

# T3 fold stray constant: 5-3 (perl=2); wrong returns 99 with buried Constant(2).
{
    my $spec = <<'IR';
%c5=Constant(5) :Int
%c3=Constant(3) :Int
%sub=Subtract(%c5, %c3) :Int
return %sub
IR
    my $wrong = <<'IR';
%c2=Constant(2) :Int
%c99=Constant(99) :Int
%pick=TernaryExpr(%c2, %c99, %c2) :Int
return %pick
IR
    is verdict($spec, $wrong), 'FAIL', 'T3 fold stray constant FAILs';
}

# T4 deref wrong wiring: $r->[1][0] (perl=3); wrong wires $r->[0][1] returns 2.
{
    my $spec = <<'IR';
%ca1=Constant(1) :Int
%ca2=Constant(2) :Int
%ca3=Constant(3) :Int
%ca4=Constant(4) :Int
%ref0=ArrayRef(%ca1, %ca2) :ArrayRef
%ref1=ArrayRef(%ca3, %ca4) :ArrayRef
%outer_ref=ArrayRef(%ref0, %ref1) :ArrayRef
%outer_arr=PostfixDeref(%outer_ref, sigil: "@") :Array
%idx1=Constant(1) :Int
%inner_ref=Subscript(%outer_arr, %idx1) :ArrayRef
%inner_arr=PostfixDeref(%inner_ref, sigil: "@") :Array
%idx0=Constant(0) :Int
%r=Subscript(%inner_arr, %idx0) :Int
return %r
IR
    my $wrong = <<'IR';
%ca1=Constant(1) :Int
%ca2=Constant(2) :Int
%ca3=Constant(3) :Int
%ca4=Constant(4) :Int
%ref0=ArrayRef(%ca1, %ca2) :ArrayRef
%ref1=ArrayRef(%ca3, %ca4) :ArrayRef
%outer_ref=ArrayRef(%ref0, %ref1) :ArrayRef
%idx0=Constant(0) :Int
%inner_ref=Subscript(%outer_ref, %idx0) :ArrayRef
%idx1=Constant(1) :Int
%r=Subscript(%inner_ref, %idx1) :Int
return %r
IR
    is verdict($spec, $wrong), 'FAIL', 'T4 deref wrong wiring FAILs';
}

# H1 FieldAccess operand swap: NumLt(f0,f1) vs NumLt(f1,f0).
{
    my $spec = <<'IR';
%fa=FieldAccess(field_index: 0, field_stash: "C") :Int
%fb=FieldAccess(field_index: 1, field_stash: "C") :Int
%r=NumLt(%fa, %fb) :Bool
return %r
IR
    my $wrong = <<'IR';
%fa=FieldAccess(field_index: 0, field_stash: "C") :Int
%fb=FieldAccess(field_index: 1, field_stash: "C") :Int
%r=NumLt(%fb, %fa) :Bool
return %r
IR
    is verdict($spec, $wrong), 'FAIL', 'H1 FieldAccess operand swap FAILs';
}

# H2 {any} escape on an UNINITIALISED read: my $x; return $x vs Constant(999).
{
    my $spec = <<'IR';
%an=Constant("$a") :Str
%va=VarDecl(%an) :Int
%pa=PadAccess(%va, "$a") :Int
return %pa
IR
    my $wrong = <<'IR';
%c999=Constant(999) :Int
return %c999
IR
    is verdict($spec, $wrong), 'FAIL', 'H2 uninitialised read FAILs';
}

# Sigil tooth (B6): a spec @-deref must not match a real %-deref. PostfixDeref
# is see-through, but the sigil distinguishes an array deref from a hash deref
# and MUST be compared — behaviorally different graphs.
{
    my $spec = <<'IR';
%c1=Constant(1) :Int
%c2=Constant(2) :Int
%ref=ArrayRef(%c1, %c2) :ArrayRef
%arr=PostfixDeref(%ref, sigil: "@") :Array
%i0=Constant(0) :Int
%r=Subscript(%arr, %i0) :Int
return %r
IR
    my $wrong = <<'IR';
%c1=Constant(1) :Int
%c2=Constant(2) :Int
%ref=ArrayRef(%c1, %c2) :ArrayRef
%arr=PostfixDeref(%ref, sigil: "%") :Array
%i0=Constant(0) :Int
%r=Subscript(%arr, %i0) :Int
return %r
IR
    is verdict($spec, $wrong), 'FAIL', 'sigil (@ vs % PostfixDeref) FAILs';
}

# ---------------------------------------------------------------------------
# Legit shapes MUST PASS (rooted wiring accepts them).
# ---------------------------------------------------------------------------

# H3 subset-value wrap: spec a-b vs real (a-b)+100. The spec structure exists as
# a correctly-wired subgraph of the real graph, so it PASSes shape. The wrong
# return VALUE (a-b+100 vs a-b) is the behavior leg's job (lli==perl), NOT a
# shape concern — the same construct as the documented subset wrap in
# shape-subset-check.t (spec Add vs real Multiply(Add,9)).
{
    my $spec = <<'IR';
%an=Constant("$a") :Str
%a1=Constant(3) :Int
%va=VarDecl(%an, %a1) :Int
%bn=Constant("$b") :Str
%b1=Constant(7) :Int
%vb=VarDecl(%bn, %b1) :Int
%pa=PadAccess(%va, "$a") :Int
%pb=PadAccess(%vb, "$b") :Int
%s=Subtract(%pa, %pb) :Int
return %s
IR
    my $wrap = <<'IR';
%an=Constant("$a") :Str
%a1=Constant(3) :Int
%va=VarDecl(%an, %a1) :Int
%bn=Constant("$b") :Str
%b1=Constant(7) :Int
%vb=VarDecl(%bn, %b1) :Int
%pa=PadAccess(%va, "$a") :Int
%pb=PadAccess(%vb, "$b") :Int
%s=Subtract(%pa, %pb) :Int
%k=Constant(100) :Int
%w=Add(%s, %k) :Int
return %w
IR
    is verdict($spec, $wrap), 'PASS', 'H3 subset-value wrap (a-b inside a-b+100) PASSes shape';
}

# Self-match: a spec against a real graph built from the SAME ir passes.
{
    my $spec = <<'IR';
%an=Constant("$a") :Str
%a1=Constant(3) :Int
%va=VarDecl(%an, %a1) :Int
%bn=Constant("$b") :Str
%b1=Constant(7) :Int
%vb=VarDecl(%bn, %b1) :Int
%pa=PadAccess(%va, "$a") :Int
%pb=PadAccess(%vb, "$b") :Int
%s=Subtract(%pa, %pb) :Int
return %s
IR
    is verdict($spec, $spec), 'PASS', 'self-match Subtract PASSes';
}

# D1-style branch-merge: spec pad-based if/else, real TernaryExpr return.
{
    my $spec = <<'IR';
%n     = Constant(5) :Int
%zero  = Constant(0) :Int
%cmp   = NumGt(%n, %zero) :Bool
%xn    = Constant("$x") :Str
%vx    = VarDecl(%xn) :Int
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%lhs1  = PadAccess(%vx, "$x") :Int
%as1   = Assign(%lhs1, %c1) :Int
%lhs2  = PadAccess(%vx, "$x") :Int
%as2   = Assign(%lhs2, %c2) :Int
%if    = If(%vx, %cmp)
%proj0 = Proj(%if, index: 0)
%proj1 = Proj(%if, index: 1)
%region = Region(%proj0, %proj1)
%rx    = PadAccess(%vx, "$x") :Int
return %rx
control: %vx -> %if
branch_control: %proj0 -> %as1
branch_control: %proj1 -> %as2
IR
    my $real = <<'IR';
%n     = Constant(5) :Int
%zero  = Constant(0) :Int
%cmp   = NumGt(%n, %zero) :Bool
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%tern  = TernaryExpr(%cmp, %c1, %c2) :Int
return %tern
IR
    is verdict($spec, $real), 'PASS', 'D1-style branch-merge (pad spec, TernaryExpr real) PASSes';
}

# Element-store read-back: spec Assign(Subscript,rhs), real read-back Subscript.
{
    my $spec = <<'IR';
%c1   = Constant(1) :Int
%c2   = Constant(2) :Int
%c3   = Constant(3) :Int
%arr  = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx  = Constant(0) :Int
%lval = Subscript(%arr, %idx) :Int
%nv   = Constant(42) :Int
%r    = Assign(%lval, %nv) :Int
return %r
IR
    my $real = <<'IR';
%c1    = Constant(1) :Int
%c2    = Constant(2) :Int
%c3    = Constant(3) :Int
%arr   = ArrayRef(%c1, %c2, %c3) :ArrayRef
%idx   = Constant(0) :Int
%lval  = Subscript(%arr, %idx) :Int
%nv    = Constant(42) :Int
%store = Assign(%lval, %nv) :Int
%rback = Subscript(%arr, %idx, %store) :Int
return %rback
IR
    is verdict($spec, $real), 'PASS', 'R6-style element store read-back PASSes';
}

# Concat-assign: spec pad(s) .= "b", real Concat("a","b").
{
    my $spec = <<'IR';
%sn   = Constant("s") :Str
%init = Constant("a") :Str
%vs   = VarDecl(%sn, %init) :Str
%ps   = PadAccess(%vs, "s") :Str
%b    = Constant("b") :Str
%cat  = Concat(%ps, %b) :Str
%as   = Assign(%ps, %cat) :Str
%rs   = PadAccess(%vs, "s") :Str
return %rs
control: %vs -> %as
IR
    my $real = <<'IR';
%a   = Constant("a") :Str
%b   = Constant("b") :Str
%cat = Concat(%a, %b) :Str
return %cat
IR
    is verdict($spec, $real), 'PASS', 'S4-style concat-assign PASSes';
}

done_testing();

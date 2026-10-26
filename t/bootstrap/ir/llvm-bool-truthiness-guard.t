# ABOUTME: And/Or truthiness contract: Int and Boolean operands lower; operands whose
# ABOUTME: reprs disagree GAP loudly, because the merge phi needs one machine type.
use 5.42.0;
use utf8;

use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM;

# ---------------------------------------------------------------------------
# `A && B` lowers to: test A's truthiness -> branch -> phi [A, B]. Two separate
# constraints fall out of that shape, and this file pins both:
#
#   1. The LHS must be usable as an i1 branch condition. Int (icmp ne i64) and
#      Boolean (already an i1) qualify; Num/Str do not. Guarded by
#      _shortcircuit_i1_cond.
#
#   2. The phi's arms ARE the two operand SSA refs, so both operands must share
#      a machine type (Int=i64, Boolean=i1, Num=double, Str=ptr). Guarded by
#      _shortcircuit_phi_repr.
#
# HISTORY -- this file used to assert that a Boolean operand GAPs ("G.7
# gate-hardening"). That contract was DELIBERATELY REVERSED by the L5d/L5e work:
# `$x eq $x && (print ...)` is Boolean && Boolean (a comparison guard and a print's
# builtin::is_bool return), the cond.t idiom, and an i1 IS the branch condition.
# Those subtests were left red rather than updated.
#
# While updating them, two of the six red assertions turned out to be reporting
# a REAL bug, not stale intent: _shortcircuit_phi_repr had a
# `return $node_repr` fallback that fired whenever the operands disagreed,
# defeating its own documented mismatch guard. Measured before the fix,
# And(Int, Num) emitted:
#     %t3 = fadd double 0.0, 2.5
#     %t4 = phi i64 [ %t1, %entry ], [ %t3, %and.rhs ]
# a double feeding an i64 phi -- invalid IR. The RHS of && is NOT a branch
# condition (it is the expression's value when the LHS is truthy), so
# _shortcircuit_i1_cond never inspects it; the phi-type check was the only place
# the mismatch could be caught. Int/Str had the same hole and no test at all.
# ---------------------------------------------------------------------------

# A Boolean-valued node: Constant(N :Int) -> Coerce(Int->Boolean) :Boolean
sub make_bool_node ($f, $val) {
    my $c = $f->make('Constant', value => $val, const_type => 'integer');
    $c->set_stamp('Int');
    my $coerce = $f->make('Coerce', inputs => [$c],
        from_repr => 'Int', to_repr => 'Boolean');
    $coerce->set_stamp('Boolean');
    return $coerce;
}

sub make_const ($f, $repr, $val) {
    my $c = $f->make('Constant', value => $val,
        const_type => ($repr eq 'Num' ? 'number'
                     : $repr eq 'Str' ? 'string' : 'integer'));
    $c->set_stamp($repr);
    return $c;
}

# Lower `$op($lhs, $rhs)` in $f and return (ir, error).
sub lower_binop ($f, $op, $lhs, $rhs, $node_repr) {
    my $node = $f->make($op, inputs => [$lhs, $rhs]);
    $node->set_stamp($node_repr) if defined $node_repr;
    my $ret = $f->make_cfg('Return', inputs => [$node]);
    my $ll  = eval { Chalk::Target::LLVM->lower($ret) };
    return ($ll, $@);
}

for my $op (qw(And Or)) {
    subtest "$op(Int, Int) lowers (matched reprs, i64 phi)" => sub {
        my $f = Chalk::IR::NodeFactory->new;
        my ($ll, $err) = lower_binop($f, $op,
            make_const($f, 'Int', 3), make_const($f, 'Int', 7), 'Int');
        ok(!$err, "$op(Int,Int) lowers without a GAP") or diag $err;
        like($ll // '', qr/icmp ne i64/, 'LHS truthiness is an icmp ne i64');
    };

    subtest "$op(Boolean, Boolean) lowers (L5d/L5e: an i1 IS the condition)" => sub {
        my $f = Chalk::IR::NodeFactory->new;
        my ($ll, $err) = lower_binop($f, $op,
            make_bool_node($f, 1), make_bool_node($f, 0), 'Boolean');
        ok(!$err, "$op(Boolean,Boolean) lowers without a GAP") or diag $err;
        like($ll // '', qr/phi i1/,
            'the merge phi is i1, not a zero-extended i64');
    };

    # Mismatched operand reprs used to GAP unconditionally: the merge phi is one
    # instruction needing one machine type, and nothing bridged the arms. They
    # are now COERCED to the node's repr, so the rule is no longer "a mismatch
    # GAPs" but "a mismatch the node's repr can bridge lowers; one it cannot
    # still GAPs".
    #
    # The node repr is what the LOADER computes -- the JOIN of the operands --
    # so these pass the join here rather than a hand-picked value. Setting a
    # repr the join would never produce (e.g. Int for an Int/Boolean pair) tests an
    # input the pipeline cannot present, and it was that hand-set value, not the
    # coercion, which made the old fallback emit `phi i64 [ ..., double ]`.
    for my $case (['Num', 'Num'], ['Str', 'Str']) {
        my ($rhs_repr, $join) = @$case;
        subtest "$op(Int, $rhs_repr) lowers: the arms coerce to the join ($join)" => sub {
            my $f   = Chalk::IR::NodeFactory->new;
            my $rhs = make_const($f, $rhs_repr, $rhs_repr eq 'Num' ? 2.5 : 'x');
            my ($ll, $err) = lower_binop($f, $op,
                make_const($f, 'Int', 1), $rhs, $join);
            ok(!defined $err || !length $err,
                "$op(Int,$rhs_repr) lowers with the joined repr")
                or diag("error: $err");
            # A Str merge phis the AGGREGATE, not a bare pointer: a Str value is
            # `%Str = { ptr, len, enc }`, so the length rides through the merge
            # with its pointer and the two cannot desynchronize. This used to
            # read `phi i8*` alongside a second, parallel `phi i64` for the
            # length — the arrangement that could lose one and not the other.
            my $ty = $join eq 'Num' ? 'double' : '%Str';
            like($ll // '', qr/phi \Q$ty\E /,
                "the merge phi is $ty -- both arms bridged to the join");
        };
    }

    # Boolean is a SIBLING of the Int <: Num <: Str chain, not a point on it, so an
    # Int/Boolean pair has NO join and the loader leaves the node untyped. Both
    # are scalars, so the merge is the Scalar either one is: each arm boxed to
    # a %Slot, never a phi over two machine types. perl's answers, end to end:
    # llvm-and-or-test-any-scalar-for-truth.t.
    subtest "$op(Int, Boolean) merges as a Scalar: each arm boxed" => sub {
        my $f = Chalk::IR::NodeFactory->new;
        my ($ll, $err) = lower_binop($f, $op,
            make_const($f, 'Int', 1), make_bool_node($f, 1), undef);
        ok(!defined $err || !length $err, "$op(Int,Boolean) lowers")
            or diag("error: $err");
        like($ll // '', qr/phi %Slot /, 'the merge phi is a %Slot');
    };

    # A Num IS a branch condition now, by perl's truth (not 0.0), as an if
    # takes it; the merge is the Num both arms are. End to end:
    # llvm-and-or-test-any-scalar-for-truth.t.
    subtest "$op(Num, Num) lowers: a Num's truth is perl's" => sub {
        my $f = Chalk::IR::NodeFactory->new;
        my ($ll, $err) = lower_binop($f, $op,
            make_const($f, 'Num', 1.5), make_const($f, 'Num', 2.5), 'Num');
        ok(!$err, "$op(Num,Num) lowers") or diag($err);
        like($ll // '', qr/fcmp une double/, 'the truth test is not-equal-to-zero');
        like($ll // '', qr/phi double /, 'the merge phi is double');
    };
}

done_testing();

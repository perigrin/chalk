# ABOUTME: And/Or truthiness contract: Int and Bool operands lower; operands whose
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
#      Bool (already an i1) qualify; Num/Str do not. Guarded by
#      _shortcircuit_i1_cond.
#
#   2. The phi's arms ARE the two operand SSA refs, so both operands must share
#      a machine type (Int=i64, Bool=i1, Num=double, Str=ptr). Guarded by
#      _shortcircuit_phi_repr.
#
# HISTORY -- this file used to assert that a Bool operand GAPs ("G.7
# gate-hardening"). That contract was DELIBERATELY REVERSED by the L5d/L5e work:
# `$x eq $x && (print ...)` is Bool && Bool (a comparison guard and a print's
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

# A Bool-valued node: Constant(N :Int) -> Coerce(Int->Bool) :Bool
sub make_bool_node ($f, $val) {
    my $c = $f->make('Constant', value => $val, const_type => 'integer');
    $c->set_representation('Int');
    my $coerce = $f->make('Coerce', inputs => [$c],
        from_repr => 'Int', to_repr => 'Bool');
    $coerce->set_representation('Bool');
    return $coerce;
}

sub make_const ($f, $repr, $val) {
    my $c = $f->make('Constant', value => $val,
        const_type => ($repr eq 'Num' ? 'number'
                     : $repr eq 'Str' ? 'string' : 'integer'));
    $c->set_representation($repr);
    return $c;
}

# Lower `$op($lhs, $rhs)` in $f and return (ir, error).
sub lower_binop ($f, $op, $lhs, $rhs, $node_repr) {
    my $node = $f->make($op, inputs => [$lhs, $rhs]);
    $node->set_representation($node_repr) if defined $node_repr;
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

    subtest "$op(Bool, Bool) lowers (L5d/L5e: an i1 IS the condition)" => sub {
        my $f = Chalk::IR::NodeFactory->new;
        my ($ll, $err) = lower_binop($f, $op,
            make_bool_node($f, 1), make_bool_node($f, 0), 'Bool');
        ok(!$err, "$op(Bool,Bool) lowers without a GAP") or diag $err;
        like($ll // '', qr/phi i1/,
            'the merge phi is i1, not a zero-extended i64');
    };

    # The real-bug guards: each of these emitted invalid IR before the
    # phi-type fallback was removed.
    for my $rhs_repr (qw(Bool Num Str)) {
        subtest "$op(Int, $rhs_repr) GAPs: phi cannot span two machine types" => sub {
            my $f   = Chalk::IR::NodeFactory->new;
            my $rhs = $rhs_repr eq 'Bool'
                ? make_bool_node($f, 1)
                : make_const($f, $rhs_repr, $rhs_repr eq 'Num' ? 2.5 : 'x');
            # node_repr is deliberately set: it must NOT rescue a real mismatch.
            my ($ll, $err) = lower_binop($f, $op,
                make_const($f, 'Int', 1), $rhs, 'Int');
            ok(defined $err && length $err,
                "$op(Int,$rhs_repr) dies rather than emitting a mismatched phi")
                or diag('no error; ir: ' . substr($ll // '', 0, 200));
            like($err // '', qr/mismatched reprs/,
                'the GAP names the repr mismatch');
        };
    }

    subtest "$op(Num, Num) GAPs: Num is not an i1 branch condition" => sub {
        my $f = Chalk::IR::NodeFactory->new;
        my ($ll, $err) = lower_binop($f, $op,
            make_const($f, 'Num', 1.5), make_const($f, 'Num', 2.5), 'Num');
        ok(defined $err && length $err, "$op(Num,Num) dies loudly")
            or diag('no error; ir: ' . substr($ll // '', 0, 200));
        like($err // '', qr/only Int and Bool truthiness/,
            'the GAP names the truthiness restriction');
    };
}

done_testing();

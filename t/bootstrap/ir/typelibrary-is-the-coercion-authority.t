#!/usr/bin/env perl
# ABOUTME: TypeLibrary is the authority for IR operand coercion targets.
# ABOUTME: Pins that it answers only where it HAS authority, and declines elsewhere.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::Grammar::Perl::TypeLibrary;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Serialize::JSON;

# The accessor under test. Called by name because it is a package sub, not a
# method -- TypeLibrary is a library of functions over static tables.
sub want ($op, $pos) {
    return Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op($op, $pos);
}

# ---------------------------------------------------------------------------
# The signature answers, per LOGICAL operand position
# ---------------------------------------------------------------------------
#
# Position is the operand's index in BOTH the signature and the node's inputs
# array, because those agree: control is carried on its own control_in wire
# key, NOT flattened into inputs[0]. Serialize/JSON.pm:292-299 calls that
# flattening "the old convention", and the producer emits `Concat(%lhs, %rhs)`
# -- two operands, no control slot (t/corpus/mdtest/strings.md:99).
#
# Worth stating because a hand-written test CAN build a node the other way
# (`inputs => [undef, $a, $b]`, as graph-bidirectional-traversal.t does), and
# reading that convention as the producer's is a mistake this file exists to
# not repeat. The last subtest pins that such a node is still handled safely.

subtest 'string comparison operands are Str at both positions' => sub {
    for my $op (qw(StrEq StrNe StrLt StrGt StrLe StrGe StrCmp)) {
        is want($op, 0), 'Str', "$op position 0 wants Str";
        is want($op, 1), 'Str', "$op position 1 wants Str";
    }
    is want('Concat', 0), 'Str', 'Concat position 0 wants Str';
    is want('Concat', 1), 'Str', 'Concat position 1 wants Str';
};

subtest 'a non-Str operand of StrLt gets a coercion' => sub {
    # StrLt cannot be reached by the corpus -- it does not lower. This is the
    # assertion that keeps the signature path honest for the whole comparison
    # family, whose other members lower and so are covered behaviourally.
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', const_type => 'integer', value => 7);
    $lhs->set_representation('Int');
    my $rhs = $f->make('Constant', const_type => 'string', value => 'x');
    $rhs->set_representation('Str');

    # Producer shape: operands at 0 and 1, control on its own edge.
    my $cmp = $f->make('StrLt',
        inputs => [$lhs, $rhs],
        left   => $lhs,
        right  => $rhs,
    );

    my $graph = Chalk::IR::Graph->new;
    $graph->merge($cmp);

    my $n = Chalk::IR::Serialize::JSON::_insert_str_coercions({ main => $graph });
    is $n, 1, 'exactly one coercion inserted';

    my $coerced = $cmp->inputs->[0];
    isa_ok $coerced, 'Chalk::IR::Node::Coerce', 'the Int operand';
    is $coerced->from_repr, 'Int', 'coerces from Int';
    is $coerced->to_repr,   'Str', 'coerces to Str';
    is $coerced->inputs->[0]->id, $lhs->id, 'wraps the original operand';

    is $cmp->inputs->[1]->id, $rhs->id, 'the already-Str operand is untouched';
};

subtest 'an undef input slot is skipped, not coerced' => sub {
    # A hand-written node may carry a leading undef where the producer carries
    # nothing. The pass must skip it rather than treat it as an operand -- and
    # must not shift the positions of the operands that follow.
    my $f = Chalk::IR::NodeFactory->new;

    my $lhs = $f->make('Constant', const_type => 'integer', value => 7);
    $lhs->set_representation('Int');
    my $rhs = $f->make('Constant', const_type => 'string', value => 'x');
    $rhs->set_representation('Str');

    my $cmp = $f->make('StrLt',
        inputs => [undef, $lhs, $rhs],
        left   => $lhs,
        right  => $rhs,
    );

    my $graph = Chalk::IR::Graph->new;
    $graph->merge($cmp);

    Chalk::IR::Serialize::JSON::_insert_str_coercions({ main => $graph });

    ok !defined $cmp->inputs->[0], 'the undef slot is left alone';
    isa_ok $cmp->inputs->[1], 'Chalk::IR::Node::Coerce', 'the Int operand';
    is $cmp->inputs->[2]->id, $rhs->id, 'the Str operand is untouched';
};

# ---------------------------------------------------------------------------
# Where it must DECLINE
# ---------------------------------------------------------------------------

subtest 'the bitwise family declines -- the node does not own its operands' => sub {
    # Numeric `&` is (Int,Int)->Int; string-bitwise `&.` is a Str operator.
    # Both lower to BitAnd, so no single answer is correct and the accessor
    # must have no opinion rather than pick one.
    for my $op (qw(BitAnd BitOr BitXor)) {
        is want($op, 0), undef, "$op logical position 0 has no opinion";
        is want($op, 1), undef, "$op logical position 1 has no opinion";
    }
};

subtest 'Print declines -- variadic Any is not a coercion target' => sub {
    # The Print NODE's Str-only contract is a different claim from `print`'s
    # source signature, which is Any BY DESIGN because perl flattens a list
    # into it. The node contract is carried separately (%_NODE_OPERAND_REPR in
    # Serialize/JSON.pm), not by this accessor.
    is want('Print', 0), undef, 'Print logical position 0 has no opinion here';
    is want('Print', 1), undef, 'Print logical position 1 has no opinion here';
};

subtest 'an unmapped op declines' => sub {
    for my $op (qw(Add Divide Multiply NoSuchOpAtAll)) {
        is want($op, 0), undef, "$op has no opinion";
    }
};

# ---------------------------------------------------------------------------
# Arity: the variadic fallback must not over-extend
# ---------------------------------------------------------------------------

subtest 'a non-variadic op has no opinion beyond its last operand' => sub {
    # `length` is arg_types => ['Str'] -- ONE entry, and NOT variadic. The
    # last-entry-covers-the-rest rule holds only for signatures that ARE
    # variadic (a trailing Any, as `print`/`join`/`sprintf` have). Applying it
    # unconditionally makes the accessor answer for an operand position the
    # operator does not have.
    is want('Length', 0), 'Str', 'Length logical position 0 wants Str';
    is want('Length', 1), undef, 'Length logical position 1 has no opinion';
    is want('Length', 5), undef, 'Length is not variadic at any later position';

    # A genuinely variadic signature still extends, which is what the rule is
    # for: `join(Str, Any...)` constrains position 0 and nothing after it.
    is want('Concat', 9), 'Str', 'a two-operand op still answers its own arity';
};

# ---------------------------------------------------------------------------
# The map itself: every entry must name a node type that exists
# ---------------------------------------------------------------------------

subtest 'every mapped IR op is a node type the factory can build' => sub {
    # An entry naming a nonexistent node type is dead weight that reads as
    # coverage: it can never be consulted, because no such node is ever built.
    my @mapped = Chalk::Grammar::Perl::TypeLibrary::ir_ops_with_signatures();
    ok scalar(@mapped), 'the map is non-empty';

    my $f = Chalk::IR::NodeFactory->new;
    my $s = $f->make('Constant', const_type => 'string', value => 'hi');

    my @missing;
    for my $op (@mapped) {
        my $ok = eval { $f->make($op, inputs => [undef, $s, $s], left => $s, right => $s); 1 }
              || eval { $f->make($op, inputs => [$s]); 1 };
        push @missing, $op unless $ok;
    }
    is_deeply \@missing, [], 'no entry names a nonexistent node type'
        or diag "nonexistent node types: @missing";
};

# ---------------------------------------------------------------------------
# The collision guard
# ---------------------------------------------------------------------------

subtest 'a source name resolving to conflicting signatures DIES' => sub {
    # %IR_OP_SOURCE_NAME is hand-written precisely because inverting
    # Actions.pm's %BINOP_MAP is many-to-one. This guard exists so a future
    # edit that reintroduces a conflict -- a source name carrying DIFFERENT
    # operand types in two of the three tables -- fails loudly instead of
    # silently picking whichever table is consulted first.
    my @conflicts = Chalk::Grammar::Perl::TypeLibrary::signature_conflicts();
    is_deeply \@conflicts, [],
        'no IR-routed source name has conflicting signatures'
        or diag "conflicting: @conflicts";

    # And the detector must actually detect. `-` is in BOTH the binary table
    # (Num,Num->Num) and the unary table (Num->Num); those AGREE, so it is
    # arity overloading and not a conflict.
    ok !Chalk::Grammar::Perl::TypeLibrary::_signature_conflict_for('-'),
        'agreeing tables across arities are not a conflict';

    # A fabricated disagreement IS one.
    ok Chalk::Grammar::Perl::TypeLibrary::_signatures_conflict(
        { operand => 'Str' }, { operand => 'Int' },
    ), 'differing operand types are reported as a conflict';
};

done_testing;

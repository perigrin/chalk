#!/usr/bin/env perl
# ABOUTME: T2 narrows a Num node's candidate set from observed constraints.
# ABOUTME: Collect from three sources, intersect to a fixpoint, default the residue.

use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::Transform::T2;
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;

# ---------------------------------------------------------------------------
# WHAT THIS TESTS
#
# `Num` is the only Chalk type with more than one candidate machine type:
# {double, i64}. Which one it gets cannot be a lookup, because the answer
# depends on what the program DOES with the value -- and getting it wrong is a
# live miscompile, pinned as a GAP in t/corpus/mdtest/arithmetic.md:
#
#     my $n = 9007199254740993; my $s = $n + 0.0;
#     perl:  9007199254740993        chalk: 9.00719925474099e+15
#
# The sitofp forced by `Num |-> double` cannot hold an i64 above 2^53.
#
# THREE CONSTRAINT SOURCES, measured across the corpus at 36 of 54 Num nodes
# directly and 46 of 54 after propagation
# (docs/plans/2026-09-04-narrowing-reaches-85-percent.md):
#
#   (a) a consumer states a requirement  -- Divide wants Num, Modulo wants Int
#   (b) a fractional literal constrains itself -- 1.5 can only be a double
#   (c) every value input is already Int -- the inputs PROVE i64
#
# Read through `observed_operand_repr`, NOT `operand_repr_for_ir_op`: the
# latter feeds a pass that MINTS Coerce nodes, so asking it changes the graph
# being analysed. Measured: 224 -> 184 on the gate.
# ---------------------------------------------------------------------------

sub build (%opt) {
    my $f = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');
    my $g = Chalk::IR::Graph->new(start => $start);
    return ($f, $g, $start);
}

subtest 'a fractional literal narrows to double' => sub {
    my ($f, $g) = build();
    my $c = $f->make('Constant', value => 1.5, stamp => 'Num');
    is Chalk::IR::Transform::T2->narrow_num($c), 'double',
        'Constant(1.5) :Num narrows to double -- the literal is its own constraint';
};

subtest 'an integral literal with no observation takes the default' => sub {
    my ($f, $g) = build();
    my $c = $f->make('Constant', value => 42, stamp => 'Num');
    is Chalk::IR::Transform::T2->narrow_num($c), 'i64',
        'Constant(42) :Num defaults to i64';
};

subtest 'all-Int inputs narrow to i64 -- the 2^53 shape' => sub {
    # THE MISCOMPILE, in miniature. A Coerce(Int -> Num) whose only input is an
    # Int constant: nothing here is fractional, so forcing a double is what
    # loses the value above 2^53.
    my ($f, $g) = build();
    my $lit  = $f->make('Constant', value => 9007199254740993, stamp => 'Int');
    my $coer = $f->make('Coerce', inputs => [$lit],
                        from_repr => 'Int', to_repr => 'Num', stamp => 'Num');
    is Chalk::IR::Transform::T2->narrow_num($coer), 'i64',
        'Coerce(Int -> Num) over an Int input narrows to i64, not double';

    # AND IT MUST BE SOURCE (c) THAT SAYS SO, not the default falling the same
    # way. Verified by disabling source (c) and re-running: this subtest still
    # passed, because `i64` is ALSO the default -- a vacuous pass, and exactly
    # the failure mode this project keeps recording.
    #
    # The discriminating question is asked with the default INVERTED. Under a
    # `double` default the answer can only be `i64` if the all-Int rule fired.
    {
        no warnings 'redefine';
        local *Chalk::IR::Transform::T2::_default_num_repr = sub { 'double' };
        is Chalk::IR::Transform::T2->narrow_num($coer), 'i64',
            'still i64 with the default inverted -- source (c) is load-bearing';

        my $bare = $f->make('Constant', value => 42, stamp => 'Num');
        is Chalk::IR::Transform::T2->narrow_num($bare), 'double',
            'and the inverted default IS reached when nothing constrains';
    }
};

subtest 'a fractional input still wins over integral siblings' => sub {
    my ($f, $g) = build();
    my $i = $f->make('Constant', value => 2,   stamp => 'Int');
    my $d = $f->make('Constant', value => 1.5, stamp => 'Num');
    my $add = $f->make('Add', inputs => [$i, $d], stamp => 'Num');
    is Chalk::IR::Transform::T2->narrow_num($add), 'double',
        'Add(Int, Num) does not claim all-Int inputs';
};

subtest 'a consumer requiring Num does not force double' => sub {
    # `Divide` observes Num at both positions, and `Num` is the CHALK type --
    # it says nothing about which machine type. A requirement of `Num` must not
    # be read as a requirement of `double`, or every divisor becomes a float
    # and source (c) can never fire.
    my ($f, $g) = build();
    my $a = $f->make('Constant', value => 6, stamp => 'Int');
    my $b = $f->make('Constant', value => 3, stamp => 'Int');
    my $q = $f->make('Divide', inputs => [$a, $b], stamp => 'Num');
    is Chalk::IR::Transform::T2->narrow_num($q), 'i64',
        'Divide over Int operands narrows to i64 on its inputs';
};

subtest 'the answer is always one of the declared candidates' => sub {
    # THE FENCE: `_candidates` is the only place sets are constructed, so
    # whatever narrowing returns must be a member. A typo'd machine type here
    # would otherwise reach the emitter.
    my $cands = $Chalk::IR::Transform::T2::CANDIDATES{Num};
    my %ok = map { $_ => 1 } $cands->@*;
    my ($f, $g) = build();
    for my $probe ([1.5, 'Num'], [42, 'Num']) {
        my $c = $f->make('Constant', value => $probe->[0], stamp => $probe->[1]);
        my $got = Chalk::IR::Transform::T2->narrow_num($c);
        ok $ok{$got}, "narrowing yields a declared candidate (got $got)";
    }
};

subtest 'narrowing refuses a stamp that is not Num' => sub {
    # Num is the ONLY multi-candidate type today. Asking about anything else is
    # a caller error, and answering would invent an authority this does not
    # have.
    my ($f, $g) = build();
    my $c = $f->make('Constant', value => 1, stamp => 'Int');
    my $err = do { local $@; eval { Chalk::IR::Transform::T2->narrow_num($c) }; $@ };
    like $err, qr/\bNum\b/,
        'narrow_num on a non-Num stamp dies naming the expectation';
};

done_testing;

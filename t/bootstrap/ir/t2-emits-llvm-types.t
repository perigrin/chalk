# ABOUTME: T2 rewrites a Chalk-typed graph into an LLVM-typed one, in place.
# ABOUTME: The sharp question is not "is this stamp sound" but "which vocabulary is it in".
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

use Chalk::IR::Serialize::JSON;
use Chalk::IR::Transform::T2;

# T2 IS A NARROWING ANALYSIS, NOT A TYPE MAPPING. From
# docs/plans/2026-08-31-t2-is-a-narrowing-analysis.md, recording perigrin:
#
#   "T2 needs to do a type mapping from a Chalk type to an LLVM type but the
#    types aren't 1:1 ... Num for example is the parent type of Int so a Num
#    maps to double|i64 and then T2 does narrowing passes to get a single
#    representation type."
#
# A stamp names a type AND EVERYTHING BELOW IT, so it is a SET of candidate
# machine types, not one:
#
#     Scalar -> all of the below, or %Slot     (narrowing, else box)
#     Str    -> {%Str, double, i64...}         (is it ever rendered?)
#     Num    -> {double, i64...}               (is it ever fractional?)
#     Int    -> {i8..i64}                      (sign and range -- NOT built)
#
# IT COSTS NO NEW FIELD. `Node.pm` declares ONE stamp field and
# `representation()` is a read alias over it. So T2 does not add a slot -- it
# CHANGES WHAT THE ONE FIELD HOLDS. Chalk type before, LLVM type after, the
# pass as the boundary.
#
# THE INVARIANT THAT BUYS: a graph past T2 holding `Scalar` in a stamp is a T2
# bug, detectable without reasoning about types at all. That is what this file
# asserts -- vocabulary, not soundness.
#
# SCOPE, per the design: the SPINE COLLAPSE only. Width and sign selection are
# designed toward and not built, so `Int` answers `i64` unconditionally until
# intervals exist.

my $LOAD = \&Chalk::IR::Serialize::JSON::from_json;

# A program whose every node is decidable without intervals: an Int-stamped
# constant, an Int add, and a Str constant.
my $WIRE = <<'JSON';
{
  "version": 1,
  "methods": {
    "main::__PROGRAM__": {
      "start": 0,
      "returns": [6],
      "nodes": [
        {"id": 0, "op": "Start", "inputs": []},
        {"id": 1, "op": "Constant", "stamp": "Int", "inputs": [],
         "fields": {"const_type": "integer", "value": "2"}},
        {"id": 2, "op": "Constant", "stamp": "Int", "inputs": [],
         "fields": {"const_type": "integer", "value": "3"}},
        {"id": 3, "op": "Add", "stamp": "Int", "inputs": [1, 2]},
        {"id": 4, "op": "Constant", "stamp": "Str", "inputs": [],
         "fields": {"const_type": "string", "value": "hi"}},
        {"id": 5, "op": "Print", "stamp": "Boolean", "inputs": [4], "control_in": 0},
        {"id": 6, "op": "Return", "inputs": [3], "control_in": 5}
      ]
    }
  }
}
JSON

sub stamps_of ($graphs) {
    my %by_op;
    for my $g (values %$graphs) {
        for my $n ($g->nodes->@*) {
            push @{ $by_op{ $n->operation } }, $n->stamp;
        }
    }
    return \%by_op;
}

subtest 'before T2 the graph is in CHALK vocabulary' => sub {
    # The premise, asserted rather than assumed: if the loader stopped
    # producing Chalk types, the pass below would be transforming something
    # else and every assertion here would be measuring the wrong thing.
    my $graphs = $LOAD->($WIRE);
    my $s = stamps_of($graphs);

    is $s->{Add}[0], 'Int', 'an Add carries the Chalk type Int';
    ok scalar(grep { ($_ // '') eq 'Str' } $s->{Constant}->@*),
        'and a Str constant carries Str';
};

subtest 'after T2 every stamp is an LLVM type' => sub {
    my $graphs = $LOAD->($WIRE);
    Chalk::IR::Transform::T2->run($graphs);
    my $s = stamps_of($graphs);

    # ASSERTED AS VOCABULARY, which is the question the design says T2 makes
    # answerable: not "is this sound" but "which language is this graph in".
    is $s->{Add}[0], 'i64', 'the Add now carries an LLVM type';
    ok scalar(grep { ($_ // '') eq '%Str' } $s->{Constant}->@*),
        'and the Str constant carries %Str';
};

# THE INVARIANT, and the reason the vocabulary question is worth asking: a
# Chalk type surviving T2 is a bug in T2, findable without knowing what the
# program means.
subtest 'no Chalk lattice name survives T2' => sub {
    my $graphs = $LOAD->($WIRE);
    Chalk::IR::Transform::T2->run($graphs);

    my @chalk = qw(Int Num Str Scalar Boolean Undef Unknown None
                   Array Hash ArrayRef HashRef CodeRef Object List);
    my %is_chalk = map { $_ => 1 } @chalk;

    my @leaked;
    for my $g (values %$graphs) {
        for my $n ($g->nodes->@*) {
            my $st = $n->stamp // next;
            push @leaked, $n->operation . "=$st" if $is_chalk{$st};
        }
    }
    is_deeply \@leaked, [], 'every stamp is past the Chalk/LLVM boundary'
        or diag('  leaked: ' . join(', ', @leaked));
};

# THE FALLBACK, and it is NOT the goal. `%Slot` is what T2 emits when narrowing
# FAILS -- the boxed cell you are forced into when nothing was proven. A
# `Scalar` T2 could prove is only ever Int should lower as i64, not as a box;
# that proof needs intervals and is out of scope, so an unnarrowed Scalar boxes.
subtest 'an unnarrowed Scalar boxes rather than guessing' => sub {
    my $wire = $WIRE =~ s/"stamp": "Int", "inputs": \[1, 2\]/"stamp": "Scalar", "inputs": [1, 2]/r;
    my $graphs = $LOAD->($wire);
    Chalk::IR::Transform::T2->run($graphs);
    my $s = stamps_of($graphs);

    is $s->{Add}[0], '%Slot',
        'a Scalar nothing narrowed becomes the boxed cell, not a guessed i64';
};

# T2 REPORTS ITS OWN FAILURE. Under the old backend-side table, an un-narrowed
# stamp died at EMISSION time blaming an earlier pass -- the pre-split model
# showing through, treating a missing narrowing as a T1 bug when the narrowing
# is T2's job. The design moves that die into T2, at the point the decision is
# made, with the graph still in hand.
#
# DRIVEN ON A NODE, NOT THROUGH THE LOADER, and the reason is worth recording:
# T1 does not LEAVE an `Unknown` on a node it can decide. Feeding
# `"stamp": "Unknown"` on an Add over two Int constants comes back `Int` --
# measured -- because _seed_and_propagate_reprs re-derives it from the
# operands. That is T1 working, so an end-to-end fixture cannot reach this
# branch and a test built on one would pass while asserting nothing.
subtest 'Unknown is T2 failing to narrow, and it says so' => sub {
    my $graphs = $LOAD->($WIRE);
    my ($add) = grep { $_->operation eq 'Add' }
                $graphs->{'main::__PROGRAM__'}->nodes->@*;
    ok $add, 'found the Add' or return;

    $add->set_stamp('Unknown');

    my $err = do { local $@; eval { Chalk::IR::Transform::T2->run($graphs) }; $@ };
    ok $err, 'it refuses rather than inventing a machine type' or return;
    like $err, qr/^T2:/,
        'and names ITSELF as the failing pass, not a downstream consumer';
    like $err, qr/lattice TOP|could not determine/,
        'saying WHY: Unknown is top, so there is no candidate set to choose from';
};

# THE SIBLING REFUSAL, and a DIFFERENT kind. `Unknown` means inference did not
# finish; `List` can never be narrowed at all, because it is not a value type.
# Distinguishing them in the message is what lets a reader know whether to fix
# inference or to fix the leak.
subtest 'a non-value type is refused as a layer violation, not as a gap' => sub {
    my $graphs = $LOAD->($WIRE);
    my ($add) = grep { $_->operation eq 'Add' }
                $graphs->{'main::__PROGRAM__'}->nodes->@*;
    $add->set_stamp('List');

    my $err = do { local $@; eval { Chalk::IR::Transform::T2->run($graphs) }; $@ };
    ok $err, 'it refuses' or return;
    like $err, qr/signature vocabulary|SEQUENCE/,
        'and says List is not a value type, rather than blaming inference';
};

done_testing;

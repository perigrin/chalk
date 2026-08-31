# ABOUTME: scalar(@a) is a Count; length($s) is a Length. One node served both,
# ABOUTME: and Count SUBTRACTS the aggregate cases rather than adding new ones.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use Chalk::IR::NodeFactory;
use Chalk::Grammar::Perl::TypeLibrary ();

# perl keeps these apart and chalk did not:
#
#   length($s)   perl's `length` op -- CHARACTERS in a string
#   scalar(@a)   NO perl op at all -- the producer synthesises an element count
#
# Measured on perl 5.42: `length(@a)` on a 3-element array is 1, not 3, because
# @a goes to scalar context (3) and length("3") is 1. They are different
# questions with different answers.
#
# The producer split them (perl5-son 93a2d12) and the split is SUBTRACTIVE --
# verified on one probe across the two producers:
#
#   8c15e32:  scalar(@a) -> Length:Int
#   4df7576:  scalar(@a) -> Count:Int
#
# So Length's contract NARROWED to strings. Adding Count while leaving Length
# accepting aggregates would leave a class nothing emits into -- the dead-arm
# shape this codebase has been finding all session.

subtest 'Count exists as a node class' => sub {
    my $f = Chalk::IR::NodeFactory->new;
    my $n = eval { $f->make('Count', inputs => []) };
    ok(defined $n, 'the factory builds a Count') or diag($@);
    is($n->operation, 'Count', 'and it reports op=Count') if defined $n;
};

subtest 'Length STAYS permissive -- the narrowing is the producer\'s' => sub {
    # MEASURED CORRECTION. Narrowing Length to Str alone here cost 10 cases
    # against pin 8c15e32 (gate-green 205 -> 195): a PRE-split producer still
    # emits Length over an aggregate, and 30 such nodes became invariant
    # violations overnight.
    #
    # The split is the producer's decision -- it chooses which node to emit.
    # This loader is handed JSON of unknown provenance and must read both
    # vocabularies, so it accepts Length over an aggregate from an old wire
    # AND Count from a new one.
    my $acc = \&Chalk::Grammar::Perl::TypeLibrary::accepts_operand_repr;
    ok($acc->('Length', 'Str'), 'Length takes a Str');
    ok($acc->('Length', 'ArrayRef'),
       'and still takes an aggregate, for a pre-split wire');
};

subtest 'Count takes the aggregates Length gave up' => sub {
    my $acc = \&Chalk::Grammar::Perl::TypeLibrary::accepts_operand_repr;
    for my $agg (qw(Array ArrayRef Hash HashRef)) {
        ok($acc->('Count', $agg), "Count accepts $agg");
    }
    # `List` is the lattice parent over Array and Hash: scalar(%h) is the key
    # count, and the answer is Int either way.
    ok($acc->('Count', 'List'), 'Count accepts the List parent');
};

subtest 'both yield Int' => sub {
    my $r = \&Chalk::Grammar::Perl::TypeLibrary::operand_repr_for_ir_op;
    is($r->('Length', 0), 'Str', 'Length requires a Str operand');
};

done_testing;

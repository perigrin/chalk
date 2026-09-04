# ABOUTME: Tests loader repr-inference for aggregate reads (RC1) in NON-class graphs.
# ABOUTME: ArrayRef/HashRef get their aggregate repr; Subscript gets the element type.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# `my @a = (1,2,3); $a[1]` loads as ArrayLiteral(Int,Int,Int) -> Subscript.
# The backend needs a repr on the container (ArrayRef) and the element read
# (Subscript = the element type). This must work for a plain graph with NO
# classes section (the repr passes previously ran only in the classes replay).

# THE FIXTURES CARRY THE STAMP THE PRODUCER EMITS. An earlier version left
# every constructed ArrayLiteral/HashLiteral unstamped, which is a shape B::SoN
# NEVER PRODUCES -- measured across the corpus: 67 aggregate literals on the
# wire, ZERO of them unstamped. The loader's aggregate rescue is scoped to
# nodes the wire stamped `List`, so an unstamped one fell through it, reached
# the end of analysis untyped, and tripped the every-Value-node-is-stamped
# invariant (94316971).
#
# That was the FIXTURE being unrealistic rather than the loader being wrong,
# and the distinction matters: this file's subject is ELEMENT-TYPE INFERENCE on
# a Subscript, not rescuing a container the producer would have stamped.
my $json = JSON::PP->new->encode({
    version => 1,
    source  => 'agg-test',
    methods => {
        'main::f' => {
            start   => 0,
            returns => [6],
            nodes   => [
                { id => 0, op => 'Start', cfg => JSON::PP::true, inputs => [] },
                { id => 1, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 1, const_type => 'integer' } },
                { id => 2, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 2, const_type => 'integer' } },
                { id => 3, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 3, const_type => 'integer' } },
                { id => 4, op => 'ArrayLiteral', inputs => [1, 2, 3], stamp => 'Array' },
                { id => 5, op => 'Constant', inputs => [], stamp => 'Int',
                  fields => { value => 1, const_type => 'integer' } },
                { id => 6, op => 'Subscript', inputs => [4, 5] },
            ],
        },
    },
});

my $graphs = Chalk::IR::Serialize::JSON::from_json($json);
my $g = $graphs->{'main::f'};

my %by_op;
push $by_op{ $_->operation }->@*, $_ for $g->nodes->@*;

subtest 'ArrayRef container gets the aggregate repr' => sub {
    # `$by_op{ArrayLiteral}`, because that is the OP. `ArrayRef` is the
    # REPRESENTATION the op carries, and the two are different axes -- which is
    # why the assertion below still reads `ArrayRef` and is right to.
    #
    # 7e77dd60 renamed the ops (ArrayRef/HashRef -> ArrayLiteral/HashLiteral,
    # following the wire) and converted the `op =>` fields in this file's
    # constructed JSON, but not the lookups that read them back. So this
    # subtest has been asking for an op that no longer exists: $by_op{ArrayRef}
    # was empty, $arr was undef, and the file DIED on the next line rather than
    # failing an assertion.
    my ($arr) = $by_op{ArrayLiteral}->@*;
    ok(defined $arr, 'has an ArrayRef');
    # `Array`, NOT `ArrayRef`. Measured on the real pipeline for
    # `my @a = (1,2,3); $a[1]`: the producer stamps the ArrayLiteral `Array`
    # and the loader keeps it. `ArrayRef` is the repr of a REFERENCE to an
    # aggregate (a boxed pointer); a literal aggregate is the aggregate itself.
    is($arr->stamp, 'Array', 'the aggregate literal carries the Array repr');
};

subtest 'Subscript element read gets the element type' => sub {
    my ($sub) = $by_op{Subscript}->@*;
    ok(defined $sub, 'has a Subscript');
    is($sub->stamp, 'Int',
        'Subscript(ArrayRef of Int, idx) reads an Int element');
};

# A NESTED aggregate: an ArrayRef whose elements are themselves ArrayRefs
# ([[1,2],[3,4]]). The element type of the outer ArrayRef is ArrayRef, so a
# Subscript reading an inner element must get repr ArrayRef (not undef).
# References R8 ($r->[1][0]); the widening logic previously only handled scalar
# element reprs (Int/Num/Str) and returned undef for a homogeneous aggregate.
subtest 'a Subscript over an ArrayRef of ArrayRefs reads an ArrayRef element' => sub {
    my $nested = JSON::PP->new->encode({
        version => 1, source => 'nested-agg', methods => {
            'main::f' => {
                start => 0, returns => [9],
                nodes => [
                    { id => 0, op => 'Start', cfg => JSON::PP::true, inputs => [] },
                    { id => 1, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 1, const_type => 'integer' } },
                    { id => 2, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 2, const_type => 'integer' } },
                    { id => 3, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 3, const_type => 'integer' } },
                    { id => 4, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 4, const_type => 'integer' } },
                    { id => 5, op => 'ArrayLiteral', inputs => [1, 2], stamp => 'Array' },   # [1,2]
                    { id => 6, op => 'ArrayLiteral', inputs => [3, 4], stamp => 'Array' },   # [3,4]
                    { id => 7, op => 'ArrayLiteral', inputs => [5, 6], stamp => 'Array' },   # [[1,2],[3,4]]
                    { id => 8, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 1, const_type => 'integer' } },
                    { id => 9, op => 'Subscript', inputs => [7, 8] },  # $r->[1]
                ],
            },
        },
    });
    my $ng = Chalk::IR::Serialize::JSON::from_json($nested)->{'main::f'};
    my ($sub) = grep { $_->operation eq 'Subscript' } $ng->nodes->@*;
    ok(defined $sub, 'has a Subscript');
    is($sub->stamp, 'Array',
        'Subscript(Array of Arrays, idx) reads an Array element');
};

# An OUT-OF-BOUNDS inner index in a nested deref ($r->[1][5]) must load a Slot
# (perl's undef), NOT the element type. _static_miss must resolve the nested
# container the same way _element_repr does; if they disagree, the OOB read gets
# the element repr (Int) and silently reads 0 instead of undef -- a miscompile
# the R8 adversarial review caught. The outer read here indexes an inner ArrayRef
# ([3,4]) at index 5 (OOB) -> Slot, not Int.
subtest 'an OOB inner index in a nested deref reads a Slot (not the element type)' => sub {
    my $oob = JSON::PP->new->encode({
        version => 1, source => 'nested-oob', methods => {
            'main::f' => {
                start => 0, returns => [11],
                nodes => [
                    { id => 0, op => 'Start', cfg => JSON::PP::true, inputs => [] },
                    { id => 1, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 1, const_type => 'integer' } },
                    { id => 2, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 2, const_type => 'integer' } },
                    { id => 3, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 3, const_type => 'integer' } },
                    { id => 4, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 4, const_type => 'integer' } },
                    { id => 5, op => 'ArrayLiteral', inputs => [1, 2], stamp => 'Array' },   # [1,2]
                    { id => 6, op => 'ArrayLiteral', inputs => [3, 4], stamp => 'Array' },   # [3,4]
                    { id => 7, op => 'ArrayLiteral', inputs => [5, 6], stamp => 'Array' },   # [[1,2],[3,4]]
                    { id => 8, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 1, const_type => 'integer' } },
                    { id => 9, op => 'Subscript', inputs => [7, 8] },  # $r->[1] = [3,4]
                    { id => 10, op => 'Constant', inputs => [], stamp => 'Int',
                      fields => { value => 5, const_type => 'integer' } },
                    { id => 11, op => 'Subscript', inputs => [9, 10] }, # [3,4][5] OOB
                ],
            },
        },
    });
    my $og = Chalk::IR::Serialize::JSON::from_json($oob)->{'main::f'};
    my @subs = grep { $_->operation eq 'Subscript' } $og->nodes->@*;
    my ($outer) = grep {
        my $c = $_->inputs->[0];
        blessed($c) && $c->operation eq 'Subscript';
    } @subs;
    ok(defined $outer, 'has the outer (OOB) Subscript');

    # `Undef`, NOT `Slot`, and the loader says why in its own words: "the
    # honest type for a statically-missing read is `Undef` ... When the OOB
    # path records that instead, this filter stops firing on its own"
    # (Serialize/JSON.pm, on the guard that drops a non-lattice `Slot` before
    # it reaches the wire).
    #
    # `Slot` is a machine ENCODING, not a lattice type -- it is what `Scalar`
    # lowers to -- so a TYPE axis cannot carry it. The condition that comment
    # describes has been met, and this assertion held the older view.
    #
    # It was not caught earlier because this subtest NEVER RAN: the file died
    # before reaching it, on an unstamped ArrayLiteral tripping the
    # every-Value-node-is-stamped invariant. Fixing the fixture made the
    # subtest reachable and the stale expectation visible.
    is($outer->stamp, 'Undef',
        'an OOB inner index reads Undef -- the honest type for a '
      . 'statically-missing read, not the Int element type');
};

done_testing();

# ABOUTME: Tests loader repr-inference for aggregate reads (RC1) in NON-class graphs.
# ABOUTME: ArrayRef/HashRef get their aggregate repr; Subscript gets the element type.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP;

use lib 'lib';
use Chalk::IR::Serialize::JSON ();

# `my @a = (1,2,3); $a[1]` loads as ArrayRef(Int,Int,Int) -> Subscript(arr,idx).
# The backend needs a repr on the container (ArrayRef) and the element read
# (Subscript = the element type). This must work for a plain graph with NO
# classes section (the repr passes previously ran only in the classes replay).

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
                { id => 4, op => 'ArrayRef', inputs => [1, 2, 3] },
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
    my ($arr) = $by_op{ArrayRef}->@*;
    ok(defined $arr, 'has an ArrayRef');
    is($arr->representation, 'ArrayRef', 'ArrayRef repr is ArrayRef');
};

subtest 'Subscript element read gets the element type' => sub {
    my ($sub) = $by_op{Subscript}->@*;
    ok(defined $sub, 'has a Subscript');
    is($sub->representation, 'Int',
        'Subscript(ArrayRef of Int, idx) reads an Int element');
};

done_testing();

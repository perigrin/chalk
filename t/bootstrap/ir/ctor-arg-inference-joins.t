# ABOUTME: A :param field's type joins over EVERY construction site, not the first.
# ABOUTME: Taking the first makes the answer depend on graph iteration order.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;

# WHY: `_ctor_arg_reprs` used `$map{...} //= $repr` -- first writer wins -- over
# a `sort keys %$graphs` walk. So for
#
#     class Holder { field $v :param; method get { $v } }
#     Holder->new(v => 42);
#     Holder->new(v => "hello");
#
# the field was stamped from whichever site the walk reached first. Measured:
# Int-then-Str gave `Str` (the correct join) and Str-then-Int gave `Int`, which
# is WRONG -- a Str is stored into a field stamped Int.
#
# The inference itself is legitimate: chalk is ahead-of-time, so every
# construction site is in the program graph and a join over all of them is true
# of every value the field can hold (perigrin). It is `//=` that was the bug,
# not the premise -- the same discipline `_seed_direct_call_arg_reprs` already
# applies to sub arguments after measuring the identical failure on
# `g(1); g("hello")`.

my %expect = (
    'ctor-arg-join-int-then-str' => 'Str',
    'ctor-arg-join-str-then-int' => 'Str',
);

for my $fixture (sort keys %expect) {
    subtest $fixture => sub {
        my $path = "t/bootstrap/ir/data/$fixture.json";
        my $wire = do {
            open my $fh, '<', $path or plan skip_all => "fixture missing: $!";
            local $/; <$fh>;
        };
        my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
        my ($any)  = values $graphs->%*;
        my $mop    = $any->mop or plan skip_all => 'no mop';

        my ($holder) = grep { $_->name eq 'Holder' } $mop->classes;
        ok $holder, 'class Holder is in the MOP' or return;

        my ($v) = $holder->fields;
        ok $v, 'field $v exists' or return;

        is $v->type, $expect{$fixture},
            "field \$v is the JOIN of its construction sites, whatever the order";
    };
}

subtest 'the two orderings agree' => sub {
    my @types;
    for my $fixture (sort keys %expect) {
        my $wire = do {
            open my $fh, '<', "t/bootstrap/ir/data/$fixture.json" or next;
            local $/; <$fh>;
        };
        my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
        my ($any)  = values $graphs->%*;
        my $mop    = $any->mop or next;
        my ($holder) = grep { $_->name eq 'Holder' } $mop->classes;
        next unless $holder;
        my ($v) = $holder->fields;
        push @types, $v->type // 'undef';
    }
    is scalar(@types), 2, 'both fixtures loaded' or return;
    is $types[0], $types[1],
        'source order does not change the inferred field type';
};

done_testing;

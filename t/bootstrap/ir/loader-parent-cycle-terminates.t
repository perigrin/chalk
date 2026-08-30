# ABOUTME: A cyclic parent chain on the wire GAPs; it does not exhaust memory.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';
use Chalk::IR::Analysis ();

# The loader is defensive over JSON of unknown provenance, so a malformed or
# adversarial wire must fail in a way the caller can catch. _classes_in_parent_order
# marks a class placed AFTER recursing into its parent, so a cycle recurses
# forever: "Deep recursion" warnings, then the process dies with no output --
# memory exhausted, not a catchable error.
#
# The MOP OBJECT graph cannot cycle (superclass is constructor-only and parents
# are declared first), which is why this was missed: the risk is one layer
# earlier, on the RAW WIRE RECORDS, before any metaobject exists.
#
# _stamp_method_call_reprs already walks the same {parent} chain defensively
# (`while (defined $c && !$walked{$c}++)`). This is that guard, applied to the
# one walker that lacked it.

my $order = \&Chalk::IR::Analysis::_classes_in_parent_order;

subtest 'an acyclic chain still orders parents first' => sub {
    my @got = $order->({
        Child  => { parent => 'Middle' },
        Middle => { parent => 'Base'   },
        Base   => {},
    });
    my %pos; $pos{ $got[$_] } = $_ for 0 .. $#got;
    is(scalar @got, 3, 'every class is placed exactly once');
    ok($pos{Base} < $pos{Middle}, 'Base precedes Middle');
    ok($pos{Middle} < $pos{Child}, 'Middle precedes Child');
};

subtest 'a cycle terminates instead of exhausting memory' => sub {
    my $got = eval {
        local $SIG{__WARN__} = sub {};   # silence "Deep recursion"
        [ $order->({ A => { parent => 'B' }, B => { parent => 'A' } }) ];
    };
    ok(defined $got, 'the walk RETURNS rather than recursing forever')
        or diag("died: $@");
    is(scalar @$got, 2, 'and still places both classes') if defined $got;
};

subtest 'a self-parent terminates' => sub {
    my $got = eval {
        local $SIG{__WARN__} = sub {};
        [ $order->({ Loop => { parent => 'Loop' } }) ];
    };
    ok(defined $got, 'a class that is its own parent does not hang');
    is(scalar @$got, 1, 'and is placed once') if defined $got;
};

done_testing;

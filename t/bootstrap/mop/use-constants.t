# ABOUTME: MOP unit tests for Chalk::MOP::Class.declare_use_constant.
# ABOUTME: Verifies `use constant { K => V };` decls are recorded as named/value pairs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;
use Chalk::IR::Node::Constant;

my $id_counter = 0;
sub make_const ($val) {
    return Chalk::IR::Node::Constant->new(
        id         => 'c_' . $id_counter++,
        inputs     => [],
        const_type => 'integer',
        value      => $val,
    );
}

# Test 1: empty class has empty use_constants list
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my @empty = $cls->use_constants;
    is(scalar @empty, 0, 'fresh class has zero use_constants');
}

# Test 2: single declare records the {name, value} entry
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $val = make_const(42);

    my $returned = $cls->declare_use_constant('FOO', $val);

    is(ref $returned, 'HASH', 'declare_use_constant returns a hashref');
    is($returned->{name}, 'FOO', 'returned entry name matches input');
    is($returned->{value}, $val, 'returned entry value is the same node');

    my @list = $cls->use_constants;
    is(scalar @list, 1, 'use_constants has 1 entry after one declare');
    is($list[0]{name}, 'FOO', 'list[0] name is FOO');
    is($list[0]{value}, $val, 'list[0] value is the const node');
}

# Test 3: multiple declarations preserve insertion order
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    my $v1 = make_const(1);
    my $v2 = make_const(2);
    my $v3 = make_const(3);

    $cls->declare_use_constant('A', $v1);
    $cls->declare_use_constant('B', $v2);
    $cls->declare_use_constant('C', $v3);

    my @list = $cls->use_constants;
    is(scalar @list, 3, 'use_constants has 3 entries');
    is($list[0]{name}, 'A', 'insertion order [0] is A');
    is($list[1]{name}, 'B', 'insertion order [1] is B');
    is($list[2]{name}, 'C', 'insertion order [2] is C');
}

done_testing();

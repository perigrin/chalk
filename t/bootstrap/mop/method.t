# ABOUTME: Tests for Chalk::MOP::Method metaobject.
# ABOUTME: Verifies accessors: name, class, params, return_type, graph.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Basic method construction via declare_method
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Calculator');
    my $method = $cls->declare_method('add', params => ['$a', '$b']);

    isa_ok($method, 'Chalk::MOP::Method');
    is($method->name, 'add', 'method name');
    is(refaddr($method->class), refaddr($cls), 'method class points back');
    is_deeply($method->params, ['$a', '$b'], 'params accessor');
}

# return_type defaults to undef
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Untyped');
    my $method = $cls->declare_method('foo');

    ok(!defined $method->return_type, 'return_type defaults to undef');
}

# return_type can be set
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Typed');
    my $method = $cls->declare_method('bar', return_type => 'Int');

    is($method->return_type, 'Int', 'return_type when set');
}

# params default to empty list
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NoArgs');
    my $method = $cls->declare_method('run');

    is_deeply($method->params, [], 'params default to empty');
}

# graph defaults to undef (no graph construction in Phase 0)
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Stub');
    my $method = $cls->declare_method('stub');

    ok(!defined $method->graph, 'graph defaults to undef in Phase 0');
}

# multiple methods on one class
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Multi');
    $cls->declare_method('alpha');
    $cls->declare_method('beta');
    $cls->declare_method('gamma');

    my @methods = $cls->methods;
    is(scalar @methods, 3, 'three methods declared');
    my @names = map { $_->name } @methods;
    is_deeply(\@names, [qw(alpha beta gamma)], 'methods in declaration order');
}

done_testing();

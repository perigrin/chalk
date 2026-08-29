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

# THE RETURN TYPE MAY BE NARROWED AFTER DECLARATION.
#
# declare_method populates return_type from the WIRE, which is the producer's
# answer. The loader then walks the graph and can often do better -- it has the
# whole program where the producer works one CV at a time. When the two are
# ORDERED (the graph derives a subtype of what the wire declared) the narrower
# one is the answer, and the metaobject must be able to carry it: Target::LLVM
# reads return_type directly for the callee's signature, so a metaobject left
# holding the wider type emits a wider return than the call sites expect.
#
# NARROWING ONLY. A setter that accepts anything lets a later pass WEAKEN a
# determined type, which is the defect t/bootstrap/loader-return-type.t exists
# to forbid ("may only NARROW it, never weaken it"). Widening is refused.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Narrowable');
    my $method = $cls->declare_method('m', return_type => 'Scalar');

    $method->set_return_type('Int');
    is($method->return_type, 'Int', 'a subtype narrows the declared type');
}

{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Unset');
    my $method = $cls->declare_method('m');

    $method->set_return_type('Int');
    is($method->return_type, 'Int', 'an undef return type takes the first answer');
}

{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('FromUnknown');
    my $method = $cls->declare_method('m', return_type => 'Unknown');

    $method->set_return_type('Int');
    is($method->return_type, 'Int', 'Unknown is replaced by any determined type');
}

# BILATERAL: a setter that only ever accepts is not enforcing anything.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NoWiden');
    my $method = $cls->declare_method('m', return_type => 'Int');

    my $ok = eval { $method->set_return_type('Scalar'); 1 };
    ok(!$ok, 'widening a determined type is refused');
    # Name the METHOD and BOTH types. A qr/narrow/ alone passed over a message
    # that interpolated the class object's address instead of its name.
    like($@, qr/NoWiden::m/, 'the refusal names the method');
    like($@, qr/'Int'.*'Scalar'/, 'and both types, in from-to order');
    like($@, qr/narrow/i, 'and says why');
    is($method->return_type, 'Int', 'the determined type survives the refusal');
}

{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Unrelated');
    my $method = $cls->declare_method('m', return_type => 'Code');

    my $ok = eval { $method->set_return_type('Array'); 1 };
    ok(!$ok, 'an unrelated type is refused, not silently taken');
}

# params default to empty list
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NoArgs');
    my $method = $cls->declare_method('run');

    is_deeply($method->params, [], 'params default to empty');
}

# graph defaults to a fresh Chalk::IR::Graph instance
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Stub');
    my $method = $cls->declare_method('stub');

    isa_ok($method->graph, 'Chalk::IR::Graph', 'graph is a Chalk::IR::Graph');
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

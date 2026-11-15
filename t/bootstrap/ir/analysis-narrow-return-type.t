# ABOUTME: Whole-program analysis settles a sub's or a method's return type on its metaobject:
# ABOUTME: it may only narrow what is there, never weaken it (Chalk::IR::Analysis::narrow_return_type).
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::MOP;
use Chalk::IR::Analysis;

# (The rule was the metaobject's own setter's; the MOP depends on nothing
# above it, and the type lattice is the compiler's, so it is analysis's now.)

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

    Chalk::IR::Analysis::narrow_return_type($method, 'Int');
    is($method->return_type, 'Int', 'a subtype narrows the declared type');
}

{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Unset');
    my $method = $cls->declare_method('m');

    Chalk::IR::Analysis::narrow_return_type($method, 'Int');
    is($method->return_type, 'Int', 'an undef return type takes the first answer');
}

{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('FromUnknown');
    my $method = $cls->declare_method('m', return_type => 'Unknown');

    Chalk::IR::Analysis::narrow_return_type($method, 'Int');
    is($method->return_type, 'Int', 'Unknown is replaced by any determined type');
}

# BILATERAL: a setter that only ever accepts is not enforcing anything.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NoWiden');
    my $method = $cls->declare_method('m', return_type => 'Int');

    my $ok = eval { Chalk::IR::Analysis::narrow_return_type($method, 'Scalar'); 1 };
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

    my $ok = eval { Chalk::IR::Analysis::narrow_return_type($method, 'Array'); 1 };
    ok(!$ok, 'an unrelated type is refused, not silently taken');
}

# THE RETURN TYPE MAY BE NARROWED AFTER DECLARATION, and only narrowed. Same
# contract as a method's (above). A sub carries it for the same consumer: Target::LLVM reads
# return_type directly when emitting the callee's signature.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NarrowableSub');
    my $sub = $cls->declare_sub('s', return_type => 'Scalar');

    Chalk::IR::Analysis::narrow_return_type($sub, 'Int');
    is($sub->return_type, 'Int', 'a subtype narrows the declared type');

    my $ok = eval { Chalk::IR::Analysis::narrow_return_type($sub, 'Scalar'); 1 };
    ok(!$ok, 'widening a determined type is refused');
    is($sub->return_type, 'Int', 'the determined type survives the refusal');
}


done_testing;

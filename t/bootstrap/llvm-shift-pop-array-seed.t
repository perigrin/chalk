# ABOUTME: Pins that shift/pop seeds its array's repr when the loader left it uncommitted.
# ABOUTME: `Unknown` means uncommitted, so the seed must fire on it exactly as on undef.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::NodeFactory;
use Chalk::Target::LLVM::Context;

# _lower_builtin_shift_pop needs its array operand to carry a container repr,
# because _load_array_header -> _container_ptr resolves the container pointer
# through it. The array often has no repr: `while (shift @q) { ... }` drains a
# queue whose value nobody reads, so no inference pass ever types it.
#
# The backend covers that itself -- an ArrayRef literal is always the ArrayRef
# repr, so it seeds one before resolving. The seed's guard asked
# `!defined $array->representation`.
#
# That guard is wrong for the same reason the loader's nine were (fixed in
# d3053a2a): `Unknown` is how the producer says it could not type a value, and
# it is not `undef`. Once slice 3b stops dropping it at the wire-stamp seed,
# an ArrayRef node arrives holding `Unknown`, the guard reads it as "already
# committed", the seed is skipped, and _container_ptr resolves against a repr
# that is not a container.
#
# So the guard tests COMMITMENT. This pins both polarities, since a guard that
# seeds unconditionally would also pass a test that only checked the Unknown
# case -- and that would clobber a real repr the loader had committed.

sub array_node_with_repr ($repr) {
    my $f = Chalk::IR::NodeFactory->new;
    my $n = $f->make('ArrayRef', inputs => []);
    $n->set_representation($repr) if defined $repr;
    return $n;
}

subtest 'an uncommitted array gets seeded' => sub {
    for my $uncommitted (undef, 'Unknown') {
        my $n = array_node_with_repr($uncommitted);
        Chalk::Target::LLVM::Context::_seed_container_repr($n);
        is $n->representation, 'ArrayRef',
            sprintf('%s is uncommitted, so the seed fires',
                $uncommitted // 'undef');
    }
};

subtest 'a committed array is left alone' => sub {
    # The other polarity. `Array` is the repr for a non-boxed aggregate; if the
    # loader committed to it, overwriting with ArrayRef would change which
    # container-pointer path _container_ptr takes.
    my $n = array_node_with_repr('Array');
    Chalk::Target::LLVM::Context::_seed_container_repr($n);
    is $n->representation, 'Array',
        'a committed repr survives -- the seed is a fallback, not an override';
};

subtest 'only an ArrayRef literal is seeded' => sub {
    # The seed's justification is "an ArrayRef literal is ALWAYS the ArrayRef
    # repr". That reasoning does not extend to other ops, so neither does the
    # seed: guessing a container repr for a node whose op does not guarantee
    # one is how a wrong repr becomes a wrong container pointer.
    my $f = Chalk::IR::NodeFactory->new;
    my $n = $f->make('HashRef', inputs => []);
    Chalk::Target::LLVM::Context::_seed_container_repr($n);
    is $n->representation, undef,
        'a HashRef is not seeded with ArrayRef';
};

done_testing;

# ABOUTME: keys %h lowers to the hash's key list in a deterministic order.
# ABOUTME: perl's own key order is randomised, so only order-independent uses are honest.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::Target::LLVM;

# PERL'S KEY ORDER IS NOT DETERMINISTIC. Measured, three runs of the same
# program on 5.42.0:
#
#   my %h=(b=>2,a=>1,c=>3); print join(",", keys %h)
#     run 1  b,a,c
#     run 2  b,c,a
#     run 3  a,b,c
#
# It is randomised per process (hash key randomisation, PERL_PERTURB_KEYS), so
# there is no order for chalk to reproduce -- and chalk's codegen must be
# byte-identical across runs, which forbids adopting a random one even if
# perl's were observable.
#
# So `keys` emits INSERTION ORDER: deterministic, and a valid answer to a
# question perl deliberately leaves unordered. Any program whose output
# depends on which order it gets is already relying on unspecified behaviour.
#
# Every corpus use is order-independent -- `sort keys %h` twice, and a
# `scalar(keys %h)` count -- so nothing here depends on the choice. It is
# recorded because a future case that DOES depend on it would be testing
# something perl does not promise.

my $FIXTURE = 't/bootstrap/ir/data/builtin-keys.json';
my $wire = do {
    open my $fh, '<', $FIXTURE or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};
my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);

subtest 'a program using keys lowers' => sub {
    my $prog = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';
    my ($ret) = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } $prog->returns->@*;
    ok($ret, 'the program has a Return') or return;

    my $ir = eval { Chalk::Target::LLVM->lower($ret) };
    my $err = $@;
    ok($ir, 'the program lowers')
        or diag "died: " . (split /\n/, $err)[0];
    return unless $ir;

    # LOWERING IS NOT CORRECTNESS. The first version of this arm lowered
    # cleanly and printed NOTHING: the Call arrives stamped Unknown, so the
    # Coerce took the Unknown path and rendered an empty string where perl
    # prints 2 -- an emitted Print with `i64 0` as its length. A test that
    # stopped at "it lowers" would have passed over that.
    #
    # The count must reach the output, so the emitted IR has to read a
    # container's field 0. Asserting the READ is what distinguishes a real
    # count from a zero-length string.
    like($ir, qr/scalar context = element count/,
        'the emitted IR reads the container count, not an empty string');
};

# The Call is stamped Unknown on the wire, NOT List -- so a rule that read the
# stamp to decide lowerability would refuse this. What makes it lowerable is
# the OPERAND: a Hash has a count and an entries array, both at known offsets,
# so the key list is a structural read rather than a typed one.
subtest 'lowerability comes from the operand, not the stamp' => sub {
    # A FRESH LOAD. Lowering STAMPS the Call (the arm states what it produced,
    # so a downstream Coerce does not take the Unknown path), which means the
    # graph the previous subtest lowered no longer shows the wire's stamp.
    # Reading it there would assert the post-lowering state while claiming to
    # describe the wire.
    my $fresh = Chalk::IR::Serialize::JSON::from_json($wire);
    my $prog = $fresh->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';

    my ($keys) = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Call'
            && $_->can('name') && ($_->name // '') eq 'keys'
    } $prog->nodes->@*;
    ok($keys, 'the fixture has a keys call') or return;

    ok(!defined $keys->representation,
        'Call(keys) carries NO representation -- its List return has no machine type');

    my ($operand) = grep { blessed($_) } $keys->inputs->@*;
    ok($operand, 'keys has an operand');
    is($operand->representation // '<undef>', 'Hash',
        'and the operand IS a Hash -- which is what makes the read possible');
};

done_testing;

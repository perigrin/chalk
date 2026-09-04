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

# THE TWO CONTEXTS ARE DIFFERENT LOWERINGS, and the producer states which is
# which from the callsite's own OPf_WANT -- want=2 stamps the Call Int, want=3
# stamps it List. Reading that decision rather than remaking it is what keeps
# the two honest:
#
#   print scalar(keys %h)          Call :Int    -> the count, an i64
#   my @k = keys %h; scalar(@k)    Call :List   -> an %Array of %Slot
#
# Building the %Array in both cases was a TYPE ERROR, not a slow path: the
# consumer of an Int-stamped Call expects an i64 and got an %Array*.
my %FIXTURE = (
    'scalar context' => 't/bootstrap/ir/data/builtin-keys.json',
    'list context'   => 't/bootstrap/ir/data/builtin-keys-array.json',
);

for my $ctx (sort keys %FIXTURE) {
    subtest "keys in $ctx lowers" => sub {
        my $wire = do {
            open my $fh, '<', $FIXTURE{$ctx} or plan skip_all => "fixture missing: $!";
            local $/; <$fh>;
        };
        my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
        my $prog = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';
        my ($ret) = grep {
            blessed($_) && $_->can('operation') && $_->operation eq 'Return'
        } $prog->returns->@*;
        ok($ret, 'the program has a Return') or return;

        my $ir = eval { Chalk::Target::LLVM->lower($ret) };
        my $err = $@;
        ok($ir, "the $ctx program lowers")
            or diag "died: " . (split /\n/, $err)[0];
        return unless $ir;

        # LOWERING IS NOT CORRECTNESS. The first version of this arm lowered
        # cleanly and printed NOTHING -- the Call arrived stamped Unknown, so
        # the Coerce took the Unknown path and rendered an empty string where
        # perl prints 2, an emitted Print with `i64 0` as its length. A test
        # that stopped at "it lowers" passed over that.
        like($ir, qr/keys: key count/,
            'the emitted IR reads the hash count');
    };
}

# The wire stamp decides the shape, so the two fixtures must NOT agree -- if
# both said the same thing, one lowering would serve both and this file would
# be testing a constant.
subtest 'the two contexts are stamped differently' => sub {
    my %stamp;
    for my $ctx (sort keys %FIXTURE) {
        my $wire = do {
            open my $fh, '<', $FIXTURE{$ctx} or plan skip_all => "fixture missing: $!";
            local $/; <$fh>;
        };
        my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
        my $prog = $graphs->{'main::__PROGRAM__'} or next;
        my ($keys) = grep {
            blessed($_) && $_->can('operation') && $_->operation eq 'Call'
                && $_->can('name') && ($_->name // '') eq 'keys'
        } $prog->nodes->@*;
        ok($keys, "$ctx has a keys call") or next;
        $stamp{$ctx} = $keys->stamp // '<undef>';
    }

    is($stamp{'scalar context'}, 'Int',
        'a scalar-context keys is an Int -- the count itself');
    is($stamp{'list context'}, 'Array',
        'a list-context keys is an Array -- the materialised keys');
    isnt($stamp{'scalar context'}, $stamp{'list context'},
        'and the two DIFFER, so the stamp is doing work');
};

done_testing;

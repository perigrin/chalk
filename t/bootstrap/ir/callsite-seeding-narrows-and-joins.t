# ABOUTME: Callsite reprs JOIN across sites, then MEET against the prior stamp.
# ABOUTME: Joining the prior stamp in lets an absence of evidence outrank evidence.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Serialize::JSON;

# TWO QUESTIONS, TWO OPERATORS, asked at one site in
# _seed_direct_call_arg_reprs:
#
#   across callsites   -- "must hold for EVERY caller"      -> join (climb)
#   vs the prior stamp -- "we said Scalar, we measured Int"  -> meet (descend)
#
# Both arms went through _join_repr. The prior stamp is not a caller: `Scalar`
# on a `shift @_` read records that nothing narrowed it yet, and
# join(Scalar, Int) = Scalar, so the absence of evidence outranked the
# evidence. The read never moved, the producer's Coerce[Scalar -> Num] stood,
# Add(Num, Int) joined to Num, and `sub f { my $x = shift; $x + 1 }` called
# once as f(10) returned Num where the corpus spec says Int.
#
# The join arm must NOT be weakened: the read is one node shared by every
# caller, so its stamp has to be true of all of them.

my %case = (
    'single-callsite-narrows' => {
        graph  => 'main::f',
        expect => 'Int',
        why    => 'one callsite passes Int, so the shift read narrows to Int',
    },
    'multi-callsite-joins' => {
        graph  => 'main::g',
        expect => 'Str',
        why    => 'callers pass Int and Str, so the read must be their JOIN',
    },
);

for my $fixture (sort keys %case) {
    my $c = $case{$fixture};
    subtest "$fixture: $c->{why}" => sub {
        my $wire = do {
            open my $fh, '<', "t/bootstrap/ir/data/$fixture.json"
                or plan skip_all => "fixture missing: $!";
            local $/; <$fh>;
        };
        my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
        my $g = $graphs->{ $c->{graph} } or plan skip_all => "no $c->{graph}";

        # The positional argument read: a builtin `shift` over ArgsSource.
        my ($read) = grep {
            $_->operation eq 'Call'
                && ($_->can('dispatch_kind') ? ($_->dispatch_kind // '') : '') eq 'builtin'
                && ($_->name // '') eq 'shift'
        } $g->nodes->@*;
        ok $read, 'found the shift read' or return;

        is $read->representation, $c->{expect},
            "the shift read is $c->{expect}";
    };
}

subtest 'the narrowed case reaches the Call result' => sub {
    my $wire = do {
        open my $fh, '<', 't/bootstrap/ir/data/single-callsite-narrows.json'
            or plan skip_all => "fixture missing: $!";
        local $/; <$fh>;
    };
    my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);
    my $driver = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no driver';

    my ($call) = grep {
        $_->operation eq 'Call'
            && ($_->can('dispatch_kind') ? ($_->dispatch_kind // '') : '') eq 'direct'
    } $driver->nodes->@*;
    ok $call, 'found the direct call' or return;

    # The corpus spec for F5 pins `Call :Int`. Int <: Num and the only call is
    # f(Int), so f : Int -> Int.
    is $call->representation, 'Int',
        'Call(main::f) is Int, matching the corpus spec for F5';
};

done_testing;

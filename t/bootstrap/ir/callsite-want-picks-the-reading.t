# ABOUTME: A callsite's want selects which of a callee's two return readings it takes.
# ABOUTME: scalar takes Return inputs[1]; list and void take inputs[0].
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::IR::Serialize::JSON;
use Chalk::IR::Analysis;

# A list-returning sub carries BOTH readings, because it is compiled once and
# cannot see its caller's context -- perl leaves entersub's context slot empty
# for a call in last-operand position, which is why `wantarray` is a runtime
# function. The CALLSITE states its own context, and picking between the two
# readings is the consumer's job:
#
#   Return inputs[0]   the LIST reading: all N values
#   Return inputs[1]   the SCALAR reading, or absent
#
# Measured against perl 5.42.0 -- these are the numbers this selection has to
# produce:
#
#   sub lit { return (10,20,30) }             my $s = lit()  -> 30
#   sub agg { my @a=(10,20,30); return @a }   my $s = agg()  ->  3
#   sub mix { my @x=(10,20); return (99,@x) } my $s = mix()  ->  2
#
# `mix` is the discriminating case: taking the last ELEMENT of the flattened
# list gives 20 where perl gives 2. The rule is the comma operator's -- the
# last OPERAND read in scalar context -- and the producer has already applied
# it, so the consumer's whole job is to take the right slot.
#
# A CONSUMER THAT ALWAYS TAKES value() IS WRONG FOR EVERY SCALAR CALLSITE and
# right for every list one, so a fixture with only list-context calls cannot
# tell a correct consumer from a broken one. The fixture here calls lit() in
# BOTH contexts for exactly that reason.

my $FIXTURE = 't/bootstrap/ir/data/list-return.json';

my $wire = do {
    open my $fh, '<', $FIXTURE or plan skip_all => "fixture missing: $!";
    local $/; <$fh>;
};

my $graphs = Chalk::IR::Serialize::JSON::from_json($wire);

sub calls_in {
    my ($graph) = @_;
    return grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Call'
            && $_->can('name') && defined $_->name
    } $graph->nodes->@*;
}

subtest 'the reading a callsite takes follows its want' => sub {
    my $prog = $graphs->{'main::__PROGRAM__'} or plan skip_all => 'no program graph';

    my %by_want;
    for my $c (calls_in($prog)) {
        next unless defined $c->want;
        push $by_want{ $c->want }->@*, $c;
    }

    # The fixture calls lit() scalar AND list, and mix() void. Assert the
    # three are DISTINCT rather than that each has a value -- a per-call check
    # passes when every call reports the same thing, which is the bug that
    # would make `want` worthless.
    is_deeply([sort keys %by_want], ['list', 'scalar', 'void'],
        'the fixture exercises all three contexts');

    for my $want (sort keys %by_want) {
        for my $call ($by_want{$want}->@*) {
            my $callee = $graphs->{ $call->name } or next;

            my ($ret) = grep {
                blessed($_) && $_->can('operation') && $_->operation eq 'Return'
            } $callee->returns->@*;
            ok($ret, $call->name . " ($want) has a Return") or next;

            my $taken = Chalk::IR::Analysis::return_reading_for_want($ret, $want);

            if ($want eq 'scalar' && defined $ret->scalar_value) {
                is($taken, $ret->scalar_value,
                    $call->name . " in scalar context takes the SCALAR face");
                isnt($taken, $ret->value,
                    $call->name . " in scalar context does NOT take the list reading");
            }
            else {
                is($taken, $ret->value,
                    $call->name . " in $want context takes the list reading");
            }
        }
    }
};

# A sub with ONE reading has no scalar face to take, and a scalar callsite
# must fall back to the single value rather than to undef. `agg` is that case:
# `return @a` needs no second face because the container already answers both
# readings (its scalar reading is its length).
subtest 'a single-reading callee answers every context' => sub {
    my $agg = $graphs->{'main::agg'} or plan skip_all => 'no agg graph';
    my ($ret) = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } $agg->returns->@*;
    ok($ret, 'agg has a Return') or return;

    ok(!defined $ret->scalar_value, 'agg has NO scalar face');

    for my $want (qw(scalar list void)) {
        is(Chalk::IR::Analysis::return_reading_for_want($ret, $want), $ret->value,
            "agg in $want context falls back to its single reading");
    }
};

# An UNDEF want is a real state, not missing data: perl leaves the context
# slot empty for a call in last-operand position, whose context arrives at
# runtime from the caller's frame. The list reading is the sound default --
# it carries all N values, so nothing is lost that a later collapse needs.
subtest 'an absent want is not a scalar want' => sub {
    my $lit = $graphs->{'main::lit'} or plan skip_all => 'no lit graph';
    my ($ret) = grep {
        blessed($_) && $_->can('operation') && $_->operation eq 'Return'
    } $lit->returns->@*;
    ok($ret, 'lit has a Return') or return;

    is(Chalk::IR::Analysis::return_reading_for_want($ret, undef), $ret->value,
        'an undef want takes the LIST reading, not the scalar face');
    isnt(Chalk::IR::Analysis::return_reading_for_want($ret, undef),
         $ret->scalar_value,
        'and specifically not the scalar face');
};

done_testing;

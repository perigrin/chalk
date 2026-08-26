# ABOUTME: Tests the loader SEEDS method return types from the wire and refuses on disagreement.
# ABOUTME: Validate-and-refine, not discard-and-rebuild: a divergence must be loud, not silent.

use 5.42.0;
use utf8;
use Test2::V0;

use Chalk::IR::Serialize::JSON ();

# _stamp_method_call_reprs used to rebuild class::method -> return_repr purely
# by walking each method graph to its Return, ignoring the wire. For plain subs
# that derivation is redundant with the producer's `return_type`; for METHODS
# the wire carried nothing at all (measured: absent for 9 of 9), so the walk was
# the only source.
#
# The producer now ships `method_return_types` as a sibling map (perl5-son
# 3e9557c). This test pins the consumer contract:
#   - the wire's answer is USED, not ignored;
#   - `Unknown` on the wire defers to the loader, which sees the whole program;
#   - a genuine DISAGREEMENT is a defect and must die, because nothing else
#     compares the two and the backend would otherwise consume one answer while
#     the metadata channel carried the other.

# A minimal hand-built wire: one class, one method returning an Int constant.
# Hand-built rather than produced, so the test can set the wire's claim
# INDEPENDENTLY of the graph and exercise the disagreement path at all.
sub wire_with_method_return_type ($claimed) {
    my %method_graph = (
        start   => 0,
        returns => [2],
        nodes   => [
            { id => 0, op => 'Start',    inputs => [] },
            { id => 1, op => 'Constant', inputs => [],
              stamp => 'Int', fields => { value => 7, const_type => 'integer' } },
            { id => 2, op => 'Return',   inputs => [1] },
        ],
    );
    my $data = {
        version => 1,
        methods => { 'P::m' => \%method_graph },
        classes => {
            P => {
                name    => 'P',
                fields  => [],
                methods => { m => 'P::m' },
                (defined $claimed
                    ? (method_return_types => { m => $claimed })
                    : ()),
            },
        },
    };
    require JSON::PP;
    return JSON::PP->new->canonical->encode($data);
}

subtest 'the wire agreeing with the graph loads cleanly' => sub {
    my $json = wire_with_method_return_type('Int');
    my $graphs;
    ok lives { $graphs = Chalk::IR::Serialize::JSON::from_json($json) },
        'loads without dying' or note $@;
    ok $graphs && $graphs->{'P::m'}, 'the method graph is present';
};

subtest 'Unknown on the wire defers to the loader' => sub {
    # The producer says Unknown when it cannot tell. That is not a
    # disagreement -- the loader has the whole program and may do better.
    my $json = wire_with_method_return_type('Unknown');
    ok lives { Chalk::IR::Serialize::JSON::from_json($json) },
        'Unknown does not trip the assertion';
};

subtest 'a wire with NO type at all still loads' => sub {
    # Back-compat: a producer predating the sibling map emits no
    # method_return_types key. The loader must fall back to the graph walk.
    my $json = wire_with_method_return_type(undef);
    ok lives { Chalk::IR::Serialize::JSON::from_json($json) },
        'an absent method_return_types map is tolerated';
};

subtest 'a genuine DISAGREEMENT is refused, loudly' => sub {
    # The wire claims Str; the graph plainly returns an Int constant. Before
    # this contract the loader silently preferred its own derivation and the
    # wire's claim went unread -- so a producer bug of exactly this shape was
    # undetectable.
    my $json = wire_with_method_return_type('Str');
    my $err = dies { Chalk::IR::Serialize::JSON::from_json($json) };

    ok $err, 'a disagreement dies rather than picking silently';
    like $err, qr/\bP::m\b/,     'the message names the method';
    like $err, qr/\bStr\b/,      'the message names the wire type';
    like $err, qr/\bInt\b/,      'the message names the derived type';
    like $err, qr/refus|wrong/i, 'the message says it is refusing, not guessing';
};

done_testing;

# ABOUTME: Tests for Chalk::IR::Serialize::JSON serialization and deserialization.
# ABOUTME: Verifies to_json and from_json produce correct, deterministic SoN-compatible output.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::IR::NodeFactory;
use Chalk::IR::Graph;
use Chalk::IR::Serialize::JSON qw(to_json from_json);

# --- Helpers -----------------------------------------------------------------

sub make_simple_graph {
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $c     = $f->make('Constant', value => '42', const_type => 'integer');
    my $ret   = $f->make_cfg('Return', inputs => [$start, $c]);
    return Chalk::IR::Graph->new(start => $start, returns => [$ret]);
}

# =============================================================================
# Test 1: Simple graph serializes to expected JSON structure
# =============================================================================

{
    my $graph = make_simple_graph();
    my $json  = to_json({ main => $graph });

    ok(defined $json, 'to_json returns a value');
    like($json, qr/"version"\s*:\s*1/, 'JSON has version 1');
    like($json, qr/"methods"/, 'JSON has methods key');
    like($json, qr/"main"/, 'JSON has "main" method');
    like($json, qr/"nodes"/, 'JSON has nodes array');
    like($json, qr/"Start"/, 'JSON contains Start node');
    like($json, qr/"Constant"/, 'JSON contains Constant node');
    like($json, qr/"Return"/, 'JSON contains Return node');
    like($json, qr/"cfg"\s*:\s*true/, 'CFG nodes marked with cfg:true');
}

# =============================================================================
# Test 2: Round-trip — serialize then deserialize, verify node count and ops
# =============================================================================

{
    my $graph = make_simple_graph();
    my $json  = to_json({ main => $graph });

    my $loaded = from_json($json);
    ok(ref $loaded eq 'HASH', 'from_json returns a hashref');
    ok(exists $loaded->{main}, 'loaded graphs include "main"');

    my $g2    = $loaded->{main};
    my $nodes = $g2->nodes();
    my %ops   = map { $_->operation() => 1 } $nodes->@*;

    ok($ops{Start},    'round-trip: Start present');
    ok($ops{Constant}, 'round-trip: Constant present');
    ok($ops{Return},   'round-trip: Return present');
    is(scalar $nodes->@*, 3, 'round-trip: exactly 3 nodes');
}

# =============================================================================
# Test 3: Constant fields (value, const_type) survive round-trip
# =============================================================================

{
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $c     = $f->make('Constant', value => 'hello', const_type => 'string');
    my $ret   = $f->make_cfg('Return', inputs => [$start, $c]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $json   = to_json({ constants => $graph });
    my $loaded = from_json($json);
    my $g2     = $loaded->{constants};

    my ($const) = grep { $_->operation() eq 'Constant' } $g2->nodes()->@*;
    ok(defined $const, 'Constant node found after round-trip');
    is($const->value(),      'hello',  'Constant value survives round-trip');
    is($const->const_type(), 'string', 'Constant const_type survives round-trip');
}

# =============================================================================
# Test 4: Call fields (dispatch_kind, name) survive round-trip
# =============================================================================

{
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $arg   = $f->make('Constant', value => '1', const_type => 'integer');
    my $call  = $f->make('Call', dispatch_kind => 'builtin', name => 'push',
                          inputs => [$arg]);
    my $ret   = $f->make_cfg('Return', inputs => [$start, $call]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $json   = to_json({ call_test => $graph });
    my $loaded = from_json($json);
    my $g2     = $loaded->{call_test};

    my ($cn) = grep { $_->operation() eq 'Call' } $g2->nodes()->@*;
    ok(defined $cn, 'Call node found after round-trip');
    is($cn->dispatch_kind(), 'builtin', 'Call dispatch_kind survives round-trip');
    is($cn->name(),          'push',    'Call name survives round-trip');
}

# =============================================================================
# Test 5: Phi region field (node reference) survives round-trip
# =============================================================================

{
    my $f      = Chalk::IR::NodeFactory->new();
    my $start  = $f->make_cfg('Start');
    my $region = $f->make_cfg('Region', inputs => [$start]);
    my $c0     = $f->make('Constant', value => '0', const_type => 'integer');
    my $phi    = $f->make('Phi', region => $region, inputs => [$c0]);
    my $ret    = $f->make_cfg('Return', inputs => [$start, $phi]);
    my $graph  = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $json   = to_json({ phi_test => $graph });
    my $loaded = from_json($json);
    my $g2     = $loaded->{phi_test};

    my ($pn) = grep { $_->operation() eq 'Phi' } $g2->nodes()->@*;
    ok(defined $pn, 'Phi node found after round-trip');
    ok(defined $pn->region(), 'Phi region is defined after round-trip');
    is($pn->region()->operation(), 'Region', 'Phi region is a Region node');
}

# =============================================================================
# Test 6: Determinism — serialize twice, byte-identical output
# =============================================================================

{
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $c1    = $f->make('Constant', value => '1', const_type => 'integer');
    my $c2    = $f->make('Constant', value => '2', const_type => 'integer');
    my $add   = $f->make('Add', inputs => [$c1, $c2]);
    my $ret   = $f->make_cfg('Return', inputs => [$start, $add]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $json1 = to_json({ det => $graph });
    my $json2 = to_json({ det => $graph });
    is($json1, $json2, 'to_json is deterministic: identical output across calls');
}

# =============================================================================
# Test 7: Multiple named methods serialize and round-trip correctly
# =============================================================================

{
    my $f1     = Chalk::IR::NodeFactory->new();
    my $start1 = $f1->make_cfg('Start');
    my $c1     = $f1->make('Constant', value => 'a', const_type => 'string');
    my $ret1   = $f1->make_cfg('Return', inputs => [$start1, $c1]);
    my $graph1 = Chalk::IR::Graph->new(start => $start1, returns => [$ret1]);

    my $f2     = Chalk::IR::NodeFactory->new();
    my $start2 = $f2->make_cfg('Start');
    my $c2     = $f2->make('Constant', value => 'b', const_type => 'string');
    my $ret2   = $f2->make_cfg('Return', inputs => [$start2, $c2]);
    my $graph2 = Chalk::IR::Graph->new(start => $start2, returns => [$ret2]);

    my $json   = to_json({ method_a => $graph1, method_b => $graph2 });
    my $loaded = from_json($json);

    ok(exists $loaded->{method_a}, 'method_a loaded');
    ok(exists $loaded->{method_b}, 'method_b loaded');

    my ($ca) = grep { $_->operation() eq 'Constant' } $loaded->{method_a}->nodes()->@*;
    my ($cb) = grep { $_->operation() eq 'Constant' } $loaded->{method_b}->nodes()->@*;
    is($ca->value(), 'a', 'method_a Constant value correct');
    is($cb->value(), 'b', 'method_b Constant value correct');
}

# =============================================================================
# Branch-review I3: the G6/G7 nodes round-trip — RegexCapture(n), EnvRead(key),
# and Call param_names (the constructor arg list) must survive to_json/from_json.
# =============================================================================

{
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg(q{Start});
    my $subj  = $f->make(q{Constant}, value => q{ab-cd}, const_type => q{string});
    my $m     = $f->make(q{RegexMatch}, pattern => q{(a)}, flags => q{}, inputs => [$subj]);
    my $cap   = $f->make(q{RegexCapture}, n => 1, inputs => [$m]);
    my $env   = $f->make(q{EnvRead}, key => q{CHALK_TEST});
    my $call  = $f->make(q{Call}, dispatch_kind => q{method}, name => q{new},
        param_names => [q{left}, q{right}], inputs => [$cap, $env]);
    my $ret   = $f->make_cfg(q{Return}, inputs => [$start, $call]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $json   = to_json({ g7 => $graph });
    my $loaded = from_json($json);
    ok(ref $loaded eq q{HASH}, q{G7 graph round-trips through JSON});
    my $g = $loaded->{g7};
    ok(defined $g, q{g7 graph present});

    my ($cap2) = grep { $_->operation eq q{RegexCapture} } $g->nodes()->@*;
    ok(defined $cap2, q{RegexCapture survived});
    is($cap2->n, 1, q{RegexCapture n preserved});

    my ($env2) = grep { $_->operation eq q{EnvRead} } $g->nodes()->@*;
    ok(defined $env2, q{EnvRead survived});
    is($env2->key, q{CHALK_TEST}, q{EnvRead key preserved});

    my ($call2) = grep { $_->operation eq q{Call} } $g->nodes()->@*;
    ok(defined $call2, q{Call survived});
    is_deeply($call2->param_names, [q{left}, q{right}], q{Call param_names preserved});
}

done_testing();

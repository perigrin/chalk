# ABOUTME: Tests for Chalk::IR::Serialize::JSON serialization and deserialization.
# ABOUTME: Verifies to_json and from_json produce correct, deterministic SoN-compatible output.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Scalar::Util qw(blessed);
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

# =============================================================================
# Test: to_json faithfully round-trips a LOADED loop graph whose condition is
# attached to its Loop via control_in (produce-time control). Historically
# (zhi 019f29ed-974a) from_json demoted control into control_in and attached
# the loop condition to its Loop via a loop_control side-key; neither was a
# value input, so on a loaded control-flow graph those nodes could fall
# outside the input-reachable serializable set, and to_json refused to emit
# the resulting condition-less (unlowerable) JSON, dying loudly instead
# (GAP-not-corruption). _all_nodes_topo is now control-aware (control_in is
# both a membership-extending edge and a topo predecessor), so the condition
# is always captured and always ordered before the Loop's other consumers --
# the old GAP no longer applies, and to_json round-trips the graph faithfully
# instead of refusing it. A freshly-built graph (control in inputs) still
# round-trips too.
# =============================================================================

{
    # A minimal while-loop producer graph: `my $s=0; my $n=3; while ($n>0){
    # $s+=$n; $n-=1 } $s`. Node 11 = NumGt(n_phi, 0) control_in:1 is the
    # condition, attached to the Loop (id 1) via control_in (produce-time
    # control wire key).
    my $loop_json = <<'JSON';
{"methods":{"main::corpus_case":{"nodes":[{"cfg":true,"id":0,"inputs":[],"op":"Start"},{"cfg":true,"id":1,"inputs":[0],"op":"Loop"},{"cfg":true,"fields":{"index":1},"id":2,"inputs":[1],"op":"Proj"},{"cfg":true,"id":3,"inputs":[2],"op":"Region"},{"fields":{"const_type":"integer","value":"0"},"id":4,"inputs":[],"op":"Constant","stamp":"Int"},{"fields":{"region":1},"id":5,"inputs":[4,10],"op":"Phi","stamp":"Int"},{"cfg":true,"id":6,"inputs":[5],"op":"Return"},{"cfg":true,"fields":{"index":0},"id":7,"inputs":[1],"op":"Proj"},{"fields":{"const_type":"integer","value":"3"},"id":8,"inputs":[],"op":"Constant","stamp":"Int"},{"fields":{"region":1},"id":9,"inputs":[8,13],"op":"Phi","stamp":"Int"},{"id":10,"inputs":[5,9],"op":"Add","stamp":"Int"},{"id":11,"inputs":[9,4],"control_in":1,"op":"NumGt","stamp":"Boolean"},{"fields":{"const_type":"integer","value":"1"},"id":12,"inputs":[],"op":"Constant","stamp":"Int"},{"id":13,"inputs":[9,12],"op":"Subtract","stamp":"Int"}],"returns":[6],"start":0}},"source":null,"version":1}
JSON

    my ($g1) = from_json($loop_json);
    my $graph = $g1->{'main::corpus_case'};
    ok(defined $graph, 'loaded the loop graph');

    # _all_nodes_topo (not Graph::nodes(), which does not walk a Phi's
    # region field) is the reachability contract to_json itself relies on;
    # use it here too to confirm the condition is genuinely captured.
    my $topo = Chalk::IR::Serialize::JSON::_all_nodes_topo($graph);
    my ($loop_node) = grep { $_->operation eq 'Loop' } $topo->@*;
    ok(defined $loop_node, 'the Loop node is present after load');
    my ($cond_node) = grep { $_->operation eq 'NumGt' } $topo->@*;
    ok(defined $cond_node, 'the loop condition is reachable from the loaded graph');
    ok(defined $cond_node->control_in && $cond_node->control_in->id eq $loop_node->id,
        q{the condition's control_in resolved to the Loop});

    # to_json must round-trip faithfully, not die.
    my $json = do { local $@; eval { to_json({ 'main::corpus_case' => $graph }) } };
    ok(defined $json && $json =~ /\S/,
        'to_json round-trips a loaded loop graph instead of refusing it');

    my $reloaded = from_json($json);
    my $graph2 = $reloaded->{'main::corpus_case'};
    ok(defined $graph2, 're-loading the round-tripped JSON succeeds');
    my $topo2 = Chalk::IR::Serialize::JSON::_all_nodes_topo($graph2);
    my ($cond_node2) = grep { $_->operation eq 'NumGt' } $topo2->@*;
    ok(defined $cond_node2, 'the loop condition survives a second round-trip');
}

{
    # A freshly-BUILT graph (control in inputs, no control_in threading) must
    # still round-trip cleanly and NOT trip the guard.
    my $graph = make_simple_graph();
    my $json  = do { local $@; eval { to_json({ main => $graph }) } };
    ok(defined $json && $json =~ /\S/,
        'a freshly-built graph still serializes (guard does not over-fire)');
    my $loaded = from_json($json);
    ok(exists $loaded->{main}, 'and it round-trips');
}

{
    # from_json must DIE loudly on an unresolvable FORWARD input reference (a
    # producer ordering bug), naming the node/slot/index, rather than resolving
    # it to undef and crashing deep in the backend (zhi 019f26a5). Build a valid
    # graph, then corrupt one node's input index to point past the array.
    use JSON::PP ();
    my $graph = make_simple_graph();
    my $json  = to_json({ main => $graph });
    my $data  = JSON::PP->new->decode($json);
    my $nodes = $data->{methods}{main}{nodes};

    # The Return (last node) references the Constant. Point its value input at a
    # non-existent forward index.
    my ($ret) = grep { $_->{op} eq 'Return' } @$nodes;
    ok(defined $ret, 'found the Return node to corrupt');
    $ret->{inputs} = [ 999 ];   # forward/out-of-range: no such node
    my $bad_json = JSON::PP->new->canonical->encode($data);

    my $err = do { local $@; eval { from_json($bad_json); 1 } ? '' : $@ };
    like($err, qr/unresolvable forward input reference/,
        'from_json dies loudly on a forward input reference');
    like($err, qr/Return/,
        'the error names the offending node op');
}

{
    # The guard must NOT fire on the sanctioned loop-Phi backedge (inputs[1] is a
    # legitimate forward reference the loader defers). A real loop graph loaded
    # via B::SoN exercises this; the ir-serialize round-trip test above already
    # loads a loop graph without the guard firing, so assert the message never
    # appears for a valid Phi-backedge graph here as a focused regression.
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $loop  = $f->make_cfg('Loop', inputs => [$start]);
    my $init  = $f->make('Constant', value => '0', const_type => 'integer');
    my $phi   = $f->make('Phi', inputs => [$init], region => $loop);
    my $one   = $f->make('Constant', value => '1', const_type => 'integer');
    my $add   = $f->make('Add', inputs => [$phi, $one]);
    $phi->set_backedge($add) if $phi->can('set_backedge');
    my $ret   = $f->make_cfg('Return', inputs => [$start, $phi]);
    my $graph = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $json = do { local $@; eval { to_json({ loopish => $graph }) } // '' };
    # If this graph serializes (a Phi-backedge round-trips), loading must not trip
    # the forward-ref guard.
  SKIP: {
        skip 'loop graph did not serialize in this build', 1 unless $json =~ /\S/;
        my $err = do { local $@; eval { from_json($json); 1 } ? '' : $@ };
        unlike($err, qr/unresolvable forward input reference/,
            'the guard does not fire on a sanctioned loop-Phi backedge');
    }
}

# _all_nodes_topo is exported for reuse by perl5-son's own JSON serializer
# (SoN::Serialize::JSON), which needs the identical Phi-region-precedes-Phi
# topo-order fix once B::SoN's FromOptree builds Chalk::IR::Node objects via
# a Chalk::IR::Graph: Chalk::IR::Graph::nodes() walks inputs()/consumers()
# only, so a merge-Phi's region (a separate named field, not an inputs[]
# edge) can otherwise be missing from -- or ordered after -- the node the
# Phi refers to it by position.
subtest '_all_nodes_topo is exported for cross-repo reuse' => sub {
    require Chalk::IR::Serialize::JSON;
    ok(Chalk::IR::Serialize::JSON->can('_all_nodes_topo'),
        '_all_nodes_topo is callable via the package');

    my $f      = Chalk::IR::NodeFactory->new();
    my $start  = $f->make_cfg('Start');
    my $region = $f->make_cfg('Region', inputs => [$start]);
    my $left   = $f->make('Constant', value => '1', const_type => 'integer');
    my $right  = $f->make('Constant', value => '2', const_type => 'integer');
    my $phi    = $f->make('Phi', inputs => [$left, $right], region => $region);
    my $ret    = $f->make_cfg('Return', inputs => [$region, $phi]);
    my $graph  = Chalk::IR::Graph->new(start => $start, returns => [$ret]);

    my $ordered = Chalk::IR::Serialize::JSON::_all_nodes_topo($graph);
    my %pos = map { $ordered->[$_]->id => $_ } 0 .. $#$ordered;
    ok(exists $pos{ $region->id }, 'the merge Phi region is present in the topo order');
    ok($pos{ $region->id } < $pos{ $phi->id },
        'the region precedes its Phi in the topo order');
};

# _all_nodes_topo also accepts a plain arrayref of nodes in place of a Graph
# object. A producer whose nodes are reachable ONLY via consumers() of an
# already-included node (never as an input on the Return's value chain) --
# e.g. a while-loop's false-exit Proj, a consumer of Loop with no downstream
# input reference -- needs a full inputs+consumers BFS from start+returns to
# find them; Chalk::IR::Graph::nodes() cannot supply that (its consumer walk
# is gated on its own incrementally-built membership cache, populated via
# merge() as Actions.pm constructs each node -- a producer that instead
# builds the whole graph via a bare factory and wraps start/returns into a
# Graph only at the end never populates that cache). Accepting a plain node
# list lets a caller supply its own BFS while still reusing the shared
# Phi-region-precedes-Phi topo-sort.
subtest '_all_nodes_topo accepts a plain arrayref of nodes' => sub {
    my $f      = Chalk::IR::NodeFactory->new();
    my $start  = $f->make_cfg('Start');
    my $loop   = $f->make_cfg('Loop', inputs => [$start]);
    my $proj1  = $f->make_cfg('Proj', inputs => [$loop], index => 1);
    my $proj0  = $f->make_cfg('Proj', inputs => [$loop], index => 0);
    my $region = $f->make_cfg('Region', inputs => [$proj1]);
    my $init   = $f->make('Constant', value => '0', const_type => 'integer');
    my $phi    = $f->make('Phi', inputs => [$init], region => $loop);
    my $ret    = $f->make_cfg('Return', inputs => [$region, $phi]);

    # A full inputs+consumers BFS from start+returns (mirroring the
    # pre-unification SoN::IR::Graph::nodes() contract), passed as a plain
    # arrayref rather than a Chalk::IR::Graph.
    my @worklist = ($start, $ret);
    my %seen;
    my @all;
    while (my $n = shift @worklist) {
        next if $seen{ $n->id }++;
        push @all, $n;
        push @worklist, grep { blessed($_) } $n->inputs->@*;
        push @worklist, $n->consumers->@* if $n->can('consumers');
    }

    my $ordered = Chalk::IR::Serialize::JSON::_all_nodes_topo(\@all);
    my %pos = map { $ordered->[$_]->id => $_ } 0 .. $#$ordered;
    ok(exists $pos{ $proj0->id },
        'a node reachable only via consumers (the false-exit Proj) is present');
};

# A loop-header Phi's backedge input (inputs[1]) is the cycle-closing edge
# that necessarily forward-references in ANY serialization order (the loader
# defer-patches it via set_backedge once every node exists -- see the
# "sanctioned loop-Phi backedge" guard elsewhere in this file). _all_nodes_topo
# must NOT treat that backedge as an ordinary predecessor to eagerly visit:
# if the Phi happens to be visited before the value that consumes it (e.g. an
# Add computing the next iteration, itself reading the Phi), visiting the
# Phi's predecessors would descend into the Add via the backedge, hit the
# Add-is-in-progress cycle guard, and let the Add finish (get appended) BEFORE
# the Phi -- producing a genuine forward reference (Add -> Phi) that is NOT
# the sanctioned backedge and that the loader correctly refuses to load.
subtest 'a loop Phi backedge is never treated as a topo predecessor to visit' => sub {
    my $f     = Chalk::IR::NodeFactory->new();
    my $start = $f->make_cfg('Start');
    my $loop  = $f->make_cfg('Loop', inputs => [$start]);
    my $init  = $f->make('Constant', value => '0', const_type => 'integer');
    my $phi   = $f->make('Phi', inputs => [$init], region => $loop);
    my $one   = $f->make('Constant', value => '1', const_type => 'integer');
    my $add   = $f->make('Add', inputs => [$phi, $one]);
    $phi->set_backedge($add);
    my $proj  = $f->make_cfg('Proj', inputs => [$loop], index => 1);
    my $ret   = $f->make_cfg('Return', inputs => [$proj, $phi]);

    # Construct the reachable-node list in an order that visits the Phi
    # BEFORE the Add -- the shape that triggers the bug (a caller's BFS
    # order need not match construction order; this is exactly what a
    # producer computing its own inputs+consumers BFS can hand in).
    my @all = ($start, $loop, $init, $phi, $one, $add, $proj, $ret);

    my $ordered = Chalk::IR::Serialize::JSON::_all_nodes_topo(\@all);
    my %pos = map { $ordered->[$_]->id => $_ } 0 .. $#$ordered;
    ok($pos{ $phi->id } < $pos{ $add->id },
        'the Phi precedes the Add that reads it (no spurious forward reference)');

    # Full round-trip proof: to_json/from_json over a Graph built with this
    # merge order must not trip the loader's forward-input-reference guard.
    my $region_wrap = $f->make_cfg('Region', inputs => [$proj]);
    my $ret2 = $f->make_cfg('Return', inputs => [$region_wrap, $phi]);
    my $g = Chalk::IR::Graph->new(start => $start, returns => [$ret2]);
    $g->merge($_) for ($start, $loop, $init, $phi, $one, $add, $proj, $region_wrap, $ret2);

    my $json = to_json({ main => $g });
    my $graphs = eval { from_json($json) };
    ok(!$@, 'round-trips without the forward-input-reference guard firing')
        or diag("from_json died: $@");
};

done_testing();

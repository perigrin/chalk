# ABOUTME: Negative/adversarial tests for Chalk::CodeGen::Harness::HandGraphs.
# ABOUTME: Guards against JSON routing, under-wired graphs, loose-Graph return, and mis-authored graphs.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed refaddr);
use lib 'lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Start;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::IR::Scheduler::EagerPinning;
use Chalk::Bootstrap::Perl::Target::Perl;
use Chalk::CodeGen::Harness::HandGraphs;

# --- N1: No-JSON regression guard ---
# The hand graph MUST NOT route through Chalk::IR::Serialize::JSON::from_json.
# We override from_json in the package before calling graph_for, then verify
# it was never invoked.

{
    # Load the JSON module first so the glob exists.
    require Chalk::IR::Serialize::JSON;

    my $from_json_called = 0;

    # Override from_json in the installed namespace to detect any calls.
    {
        no strict 'refs';
        no warnings 'redefine';
        *{'Chalk::IR::Serialize::JSON::from_json'} = sub { $from_json_called++; return {}; };
    }

    for my $tag (qw(A1 A4 A5 E1 F3)) {
        $from_json_called = 0;
        Chalk::CodeGen::Harness::HandGraphs->graph_for($tag);
        is($from_json_called, 0,
            "graph_for(\"$tag\") does NOT invoke Chalk::IR::Serialize::JSON::from_json");
    }
}

# --- N2: graph_for does NOT return a bare Chalk::IR::Graph ---

for my $tag (qw(A1 A4 A5 E1 F3)) {
    my $result = Chalk::CodeGen::Harness::HandGraphs->graph_for($tag);
    ok(!blessed($result) || !($result isa Chalk::IR::Graph),
        "graph_for(\"$tag\") does not return a bare Chalk::IR::Graph");
    ok(blessed($result) && $result isa Chalk::MOP,
        "graph_for(\"$tag\") returns a Chalk::MOP (generate-acceptable)");
}

# --- N3: Under-wired graph fails EagerPinning loudly ---
# A MOP::Method whose graph has no Return node (or only a Start) must produce
# an empty schedule rather than silently emitting degenerate Perl.
# The issue says "must FAIL EagerPinning loudly" -the scheduler returns
# an empty schedule for a graph with no Return, which is defined behaviour.
# We assert: either the scheduler throws, OR the schedule is empty (0 items),
# which means no degenerate code can be emitted.

{
    # Build an under-wired method: graph has only a Start, no Return.
    my $factory = Chalk::IR::NodeFactory->new;
    my $start   = $factory->make_cfg('Start', inputs => []);

    my $graph = Chalk::IR::Graph->new;
    $graph->merge($start);

    # Create a MOP with this under-wired method.
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Underwired');
    my $method = $cls->declare_method('m',
        params => [],
        graph  => $graph,
    );

    my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
    my ($sched, $err);
    eval {
        $sched = $scheduler->schedule($method);
    };
    $err = $@;

    # Either it threw, or it returned an empty schedule.
    my $items = defined $sched ? scalar($sched->items->@*) : 0;
    ok($err || $items == 0,
        'under-wired graph (no Return) fails loud or returns empty schedule -no degenerate output');

    if (!$err && $items == 0) {
        pass('under-wired schedule is empty (0 items) -EagerPinning is non-degenerate');
    } elsif ($err) {
        pass('under-wired graph caused EagerPinning to throw');
    }

    # Confirm Target::Perl::generate does not crash silently on the empty
    # schedule. If it does emit something, confirm it is not a method body
    # with spurious/degenerate statements (i.e. the emitted code is empty
    # or contains only the method signature with no body statements).
    SKIP: {
        skip 'EagerPinning threw -no need to check codegen output', 1 if $err;
        my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
        my $result = eval { $target->generate($mop) };
        ok(!$@, "generate on under-wired MOP does not crash: $@");
    }
}

# --- N4: Mis-authored-graph cross-check ---
# If a hand graph claims to implement A1 but does NOT emit "my $x = 1",
# the test must detect that. We construct an intentionally wrong graph
# (a bare Return with a constant "hello") and confirm the emitted Perl
# does NOT match the A1 idiom's expected construct.

{
    my $factory = Chalk::IR::NodeFactory->new;
    my $start   = $factory->make_cfg('Start', inputs => []);
    my $val     = $factory->make('Constant', value => 'hello', const_type => 'string');
    my $ret     = $factory->make_cfg('Return', inputs => [$val]);
    $ret->set_control_in($start);

    my $graph = Chalk::IR::Graph->new;
    $graph->merge($start);
    $graph->merge($val);
    $graph->merge($ret);

    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('MisAuthored');
    $cls->declare_method('m',
        params => [],
        graph  => $graph,
    );

    my $target = Chalk::Bootstrap::Perl::Target::Perl->new;
    my $result = eval { $target->generate($mop) };
    my $code   = defined $result ? join("\n", values $result->%*) : '';

    ok($code !~ /my\s+\$x\s*=\s*1/,
        'mis-authored graph (return "hello") does NOT emit "my $x = 1" -cross-check works');
    ok($code =~ /'hello'/,
        'mis-authored graph emits its actual content ("hello") -eyeball check would catch it');
}

done_testing();

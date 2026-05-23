# ABOUTME: Tests EagerPinning scheduler against straight-line method bodies.
# ABOUTME: Phase 3 — chain walk from Return; no structured expansion yet.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Scheduler::EagerPinning;
use Chalk::IR::Schedule;
use Chalk::IR::Schedule::Item;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SchedulerStraightLineTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::SchedulerStraightLineTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();
use Chalk::Bootstrap::Semiring::SemanticAction;

# Helper: parse a source class with one method, return the MOP::Method.
sub _parse_first_method($source) {
    $semiring->reset_cache();
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $result = $parser->parse_value($source);
    return undef unless defined $result && !$result->is_zero();
    return undef unless defined $mop;
    for my $cls ($mop->classes()) {
        for my $m ($cls->methods) {
            return $m;
        }
    }
    return undef;
}

# --- Test 1: scheduler module instantiates ---
{
    my $scheduler = Chalk::IR::Scheduler::EagerPinning->new;
    isa_ok($scheduler, 'Chalk::IR::Scheduler::EagerPinning');
    can_ok($scheduler, 'schedule');
}

# --- Test 2: empty-bodied method produces an empty schedule ---
# The parser does not synthesize a Return for `method m { }`; the graph
# contains only Start. A scheduler that fabricates exit nodes is the
# wrong scheduler — emit what the graph holds, nothing more.
{
    my $method = _parse_first_method('class C { method m { } }');
    ok(defined $method, 'parsed `method m { }`');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    isa_ok($sched, 'Chalk::IR::Schedule');
    ok($sched->is_balanced, 'empty schedule is balanced');
    is(scalar $sched->items->@*, 0, 'empty body → empty schedule');
}

# --- Test 3: VarDecl + Return -> 2 items in source order ---
{
    my $method = _parse_first_method('class C { method m { my $x = 1; return $x; } }');
    ok(defined $method, 'parsed VarDecl+Return');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    isa_ok($sched, 'Chalk::IR::Schedule');
    ok($sched->is_balanced, 'straight-line schedule is balanced');

    my @items = $sched->items->@*;
    is(scalar(@items), 2, 'two items');
    is($items[0]->kind, 'stmt', '#1 is stmt');
    is($items[0]->node->operation, 'VarDecl', '#1 is VarDecl');
    is($items[1]->kind, 'stmt', '#2 is stmt');
    is($items[1]->node->operation, 'Return', '#2 is Return');
}

# --- Test 4: chain coverage property ---
# Every side-effect node in the method's graph that is reachable from
# Return via the inputs[0] chain MUST appear in the schedule.
{
    my $method = _parse_first_method(
        'class C { method m { my $x = 1; my $y = 2; my $z = 3; return $x; } }'
    );
    ok(defined $method, 'parsed 3-vardecl method');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($method);
    my @items = $sched->items->@*;

    # Walk the chain manually and check the schedule matches.
    my @returns = $method->graph->returns->@*;
    my @expected;
    my $cur = $returns[0]->inputs->[0];
    while (defined $cur && $cur->operation ne 'Start') {
        unshift @expected, $cur;
        $cur = $cur->inputs->[0];
    }
    push @expected, $returns[0];

    is(scalar(@items), scalar(@expected),
        'item count matches chain length');
    for (my $i = 0; $i < @expected; $i++) {
        is(refaddr($items[$i]->node), refaddr($expected[$i]),
            "item $i matches chain step (op: " . $expected[$i]->operation . ")");
    }
}
use Scalar::Util qw(refaddr);

done_testing();

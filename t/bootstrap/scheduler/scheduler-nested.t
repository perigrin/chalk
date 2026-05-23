# ABOUTME: Tests EagerPinning scheduler on nested control structures.
# ABOUTME: Phase 4e — if-in-loop, loop-in-try, etc., produce balanced nested pairs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::Scheduler::EagerPinning;
use Chalk::Bootstrap::Semiring::SemanticAction;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SchedulerNestedTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::SchedulerNestedTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();

sub _parse_method($source) {
    $semiring->reset_cache();
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $r = $parser->parse_value($source);
    return undef unless defined $r && !$r->is_zero();
    return undef unless defined $mop;
    for my $cls ($mop->classes()) {
        for my $m ($cls->methods) { return $m; }
    }
    return undef;
}

sub _kinds($sched)       { return map { $_->kind } $sched->items->@*; }
sub _form_open_count($sched, $f) {
    return scalar grep { $_->kind eq 'block_open' && defined $_->form && $_->form eq $f }
        $sched->items->@*;
}

# --- Test 1: if inside while ---
{
    my $m = _parse_method(
        'class C { method m {
            my $x = 0;
            while ($x) { if ($x) { $x = 1; } }
            return $x;
        } }'
    );
    ok(defined $m, 'if-in-while parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'if-in-while balanced');
    is(_form_open_count($sched, 'while'), 1, 'one block_open(while)');
    is(_form_open_count($sched, 'if'),    1, 'one block_open(if)');

    # The inner if's block_open should appear BETWEEN the while's
    # open and close.
    my @kinds = _kinds($sched);
    my @forms = map { $_->form // '' } $sched->items->@*;

    my $while_open  = (grep { $kinds[$_] eq 'block_open'  && $forms[$_] eq 'while' } 0..$#kinds)[0];
    my $while_close = (grep { $kinds[$_] eq 'block_close' && $forms[$_] eq 'while' } 0..$#kinds)[0];
    my $if_open     = (grep { $kinds[$_] eq 'block_open'  && $forms[$_] eq 'if'    } 0..$#kinds)[0];
    my $if_close    = (grep { $kinds[$_] eq 'block_close' && $forms[$_] eq 'if'    } 0..$#kinds)[0];

    cmp_ok($while_open, '<', $if_open,     'while_open before if_open');
    cmp_ok($if_open,    '<', $if_close,    'if_open before if_close');
    cmp_ok($if_close,   '<', $while_close, 'if_close before while_close');
}

# --- Test 2: while inside if ---
{
    my $m = _parse_method(
        'class C { method m {
            my $x = 0;
            if ($x) { while ($x) { $x = $x + 1; } }
            return $x;
        } }'
    );
    ok(defined $m, 'while-in-if parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'while-in-if balanced');
    is(_form_open_count($sched, 'while'), 1, 'one block_open(while)');
    is(_form_open_count($sched, 'if'),    1, 'one block_open(if)');
}

# --- Test 3: chain coverage property ---
# Every side-effect node reachable from Return via the control chain
# must appear as a stmt-or-block_open item with that node, exactly once.
{
    my $m = _parse_method(
        'class C { method m {
            my $x = 0;
            my $y = 1;
            if ($x) { $x = 2; } else { $x = 3; }
            return $x;
        } }'
    );
    ok(defined $m, 'chain coverage method parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    my %nodes_seen;
    for my $i ($sched->items->@*) {
        if (defined $i->node) {
            $nodes_seen{refaddr($i->node)}++;
        }
    }

    # Every value in nodes_seen must be exactly 1 (no duplicates).
    my @dups = grep { $nodes_seen{$_} > 1 } keys %nodes_seen;
    is(scalar(@dups), 0, 'no node appears more than once in schedule')
        or diag("dups: @dups");

    # The outer VarDecls and Return must be present.
    my @body_nodes;
    my $returns = $m->graph->returns;
    my $exit = $returns->[0];
    my $cur = $exit->inputs->[0];
    while (defined $cur && ref($cur) && $cur->operation ne 'Start') {
        push @body_nodes, $cur;
        my $next = $cur->can('control_in') ? $cur->control_in : undef;
        if (!defined $next) {
            $next = $cur->inputs->[0];
        }
        $cur = $next;
        last if ref($cur) eq 'ARRAY';  # Region's arrayref inputs
    }
    push @body_nodes, $exit;

    # At least the outer chain steps should each appear. (Region's head
    # is included if encountered; we don't recurse into the elaborate
    # head-jump here because the schedule already handles it.)
    for my $n (@body_nodes) {
        next if $n->operation eq 'Region';  # Region not directly emitted
        ok(exists $nodes_seen{refaddr($n)},
            sprintf('node in outer chain present: %s', $n->operation));
    }
}
use Scalar::Util qw(refaddr);

done_testing();

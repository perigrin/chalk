# ABOUTME: Tests EagerPinning scheduler loop structured expansion.
# ABOUTME: Phase 4c — Loop becomes block_open(while|for|foreach) / body / block_close.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SchedulerLoopsTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::SchedulerLoopsTest::grammar();
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

sub _kinds_forms($sched) {
    return map { [$_->kind, $_->form // ''] } $sched->items->@*;
}

# Helper: count items by kind+form pair.
sub _count_form($sched, $form) {
    my $n = 0;
    for my $i ($sched->items->@*) {
        $n++ if $i->kind eq 'block_open' && defined $i->form && $i->form eq $form;
    }
    return $n;
}

# --- Test 1: while loop ---
{
    my $m = _parse_method(
        'class C { method m { my $x = 0; while ($x) { $x = $x + 1; } return $x; } }'
    );
    ok(defined $m, 'while parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'while schedule balanced');
    is(_count_form($sched, 'while'), 1, 'one block_open(while)');
    is(_count_form($sched, 'for'),   0, 'no block_open(for)');
    is(_count_form($sched, 'foreach'), 0, 'no block_open(foreach)');
}

# --- Test 2: foreach loop ---
{
    my $m = _parse_method(
        'class C { method m { my $sum = 0; for my $x (1, 2, 3) { $sum = $sum + $x; } return $sum; } }'
    );
    ok(defined $m, 'foreach parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'foreach schedule balanced');
    is(_count_form($sched, 'foreach'), 1, 'one block_open(foreach)');
    is(_count_form($sched, 'while'),   0, 'no block_open(while)');
}

# --- Test 3: C-style for loop ---
{
    my $m = _parse_method(
        'class C { method m { for (my $i = 0; $i < 10; $i = $i + 1) { my $a = $i; } return 0; } }'
    );
    ok(defined $m, 'C-style for parses');

    my $sched = Chalk::IR::Scheduler::EagerPinning->new->schedule($m);
    ok($sched->is_balanced, 'C-for schedule balanced');
    is(_count_form($sched, 'for'), 1, 'one block_open(for)');
    is(_count_form($sched, 'while'), 0, 'no block_open(while)');
    is(_count_form($sched, 'foreach'), 0, 'no block_open(foreach)');
}

done_testing();

# ABOUTME: Verifies all loop forms populate EagerPinning::Loop.body_stmts.
# ABOUTME: Phase 1 mig 6 — covers while, foreach, C-style for, postfix loops.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::Node::Loop;
use Chalk::Scheduler::EagerPinning::Loop;
use Chalk::Bootstrap::BNF::Target::Perl;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScheduleDataLoopBodyTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::ScheduleDataLoopBodyTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();

sub _parse_loop($src) {
    $semiring->reset_cache();
    my $r = $parser->parse_value($src);
    return undef unless defined $r;
    my $state = $r->cfg_state();
    return undef unless defined $state;
    return $state->{loop};
}

# --- while ---
{
    my $loop = _parse_loop('my $x = 0; while ($x) { my $a = 1; }');
    ok(defined $loop, 'while parses');
    my $sd = $loop->schedule_data;
    ok(defined $sd, 'while Loop has schedule_data');
    ok(scalar $sd->body_stmts->@* >= 1, 'while body_stmts populated');
}

# --- foreach ---
{
    my $loop = _parse_loop('for my $x (1, 2, 3) { my $a = $x; }');
    ok(defined $loop, 'foreach parses');
    my $sd = $loop->schedule_data;
    ok(defined $sd, 'foreach Loop has schedule_data');
    ok(scalar $sd->body_stmts->@* >= 1, 'foreach body_stmts populated');
    # And the prior iterator/list fields still work.
    ok(defined $sd->iterator, 'foreach still has iterator');
    ok(defined $sd->list,     'foreach still has list');
}

# --- C-style for ---
{
    my $loop = _parse_loop('for (my $i = 0; $i < 10; $i = $i + 1) { my $a = $i; }');
    ok(defined $loop, 'C-style for parses');
    my $sd = $loop->schedule_data;
    ok(defined $sd, 'C-for Loop has schedule_data');
    ok(scalar $sd->body_stmts->@* >= 1, 'C-for body_stmts populated');
    ok($sd->is_for_style,            'C-for still has is_for_style');
    ok(defined $sd->for_init,        'C-for still has for_init');
    ok(defined $sd->for_step,        'C-for still has for_step');
}

# --- postfix while ---
{
    my $loop = _parse_loop('my $x = 0; $x = $x + 1 while $x;');
    ok(defined $loop, 'postfix while parses');
    my $sd = $loop->schedule_data;
    ok(defined $sd, 'postfix-while Loop has schedule_data');
    ok(scalar $sd->body_stmts->@* >= 1, 'postfix-while body_stmts has body expr');
}

done_testing();

# ABOUTME: Verifies IfStatement / ElsifChain / PostfixModifier populate
# ABOUTME: EagerPinning::If with then_stmts and else_stmts. Phase 1 mig 5.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::Node::If;
use Chalk::Scheduler::EagerPinning::If;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScheduleDataIfElseTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::ScheduleDataIfElseTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();

# Helper: parse, return cfg_state's if_node.
sub _parse_if($src) {
    $semiring->reset_cache();
    my $r = $parser->parse_value($src);
    return undef unless defined $r;
    my $state = $r->cfg_state();
    return undef unless defined $state;
    return $state->{if_node};
}

# --- if with then and else ---
{
    my $if = _parse_if('my $x = 0; if ($x) { my $a = 1; } else { my $b = 2; } return $x;');
    ok(defined $if, 'if/else parses');
    my $sd = $if->schedule_data;
    ok(defined $sd, 'If has schedule_data');
    isa_ok($sd, 'Chalk::Scheduler::EagerPinning::If');
    ok(scalar $sd->then_stmts->@* >= 1, 'then_stmts populated (>=1)');
    ok(defined $sd->else_stmts && scalar $sd->else_stmts->@* >= 1,
        'else_stmts populated (>=1)');
}

# --- if with then only (no else) ---
{
    my $if = _parse_if('my $x = 0; if ($x) { my $a = 1; } return $x;');
    ok(defined $if, 'if-no-else parses');
    my $sd = $if->schedule_data;
    ok(defined $sd, 'If has schedule_data');
    ok(scalar $sd->then_stmts->@* >= 1, 'then_stmts populated');
    is($sd->else_stmts, undef, 'else_stmts undef when no else clause');
}

# --- postfix if (non-loop-jump) ---
{
    my $if = _parse_if('my $x = 0; $x = 1 if $x;');
    ok(defined $if, 'postfix-if parses');
    my $sd = $if->schedule_data;
    ok(defined $sd, 'postfix-If has schedule_data');
    is($sd->is_loop_jump, undef, 'not a loop_jump');
    ok(scalar $sd->then_stmts->@* >= 1, 'postfix-if then_stmts has the body expression');
    is($sd->else_stmts, undef, 'postfix-if has no else');
}

done_testing();

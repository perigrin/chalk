# ABOUTME: Verifies TryCatchStatement populates EagerPinning::TryCatch on the TryCatch IR.
# ABOUTME: Migration 4 of Phase 1 — moves try_stmts/catch_var/catch_stmts onto IR.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::Node::TryCatch;
use Chalk::Scheduler::EagerPinning::TryCatch;
use Chalk::Bootstrap::BNF::Target::Perl;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScheduleDataTryCatchTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::ScheduleDataTryCatchTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();
$semiring->reset_cache();

my $src = 'try { my $x = 1; } catch ($e) { my $y = 2; }';
my $result = $parser->parse_value($src);
ok(defined $result, 'try/catch parses');

my $state = $result->cfg_state();
ok(defined $state && defined $state->{try_node}, 'cfg_state exposes the TryCatch node');

my $try = $state->{try_node};
isa_ok($try, 'Chalk::IR::Node::TryCatch');

my $sd = $try->schedule_data();
ok(defined $sd, 'TryCatch has schedule_data populated')
    or BAIL_OUT('migration not applied — TryCatch.schedule_data still undef');
isa_ok($sd, 'Chalk::Scheduler::EagerPinning::TryCatch');
is($sd->node(), $try, 'schedule_data.node points back at the TryCatch');

is($sd->catch_var(), '$e', 'catch_var = "$e"');
ok(scalar $sd->try_stmts->@* >= 1, 'try_stmts populated (>=1 element)');
ok(scalar $sd->catch_stmts->@* >= 1, 'catch_stmts populated (>=1 element)');

done_testing();

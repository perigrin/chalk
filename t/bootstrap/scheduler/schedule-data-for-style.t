# ABOUTME: Verifies ForStatement populates EagerPinning::Loop with is_for_style + init/step.
# ABOUTME: Migration 3 of Phase 1 — moves C-style for recognition from Context onto IR.
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
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScheduleDataForStyleTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::ScheduleDataForStyleTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();
$semiring->reset_cache();

my $src = 'for (my $i = 0; $i < 10; $i = $i + 1) { $i; }';
my $result = $parser->parse_value($src);
ok(defined $result, 'C-style for parses');

my $state = $result->cfg_state();
ok(defined $state && defined $state->{loop}, 'cfg_state exposes the Loop node');

my $loop = $state->{loop};
isa_ok($loop, 'Chalk::IR::Node::Loop');

my $sd = $loop->schedule_data();
ok(defined $sd, 'Loop has schedule_data populated')
    or BAIL_OUT('migration not applied — Loop.schedule_data still undef');
isa_ok($sd, 'Chalk::Scheduler::EagerPinning::Loop');

is($sd->is_for_style(), true, 'is_for_style true for C-style for');
ok(defined $sd->for_init(), 'for_init populated');
ok(defined $sd->for_step(), 'for_step populated');
is($sd->iterator(), undef, 'C-style for has no foreach-iterator');
is($sd->list(),     undef, 'C-style for has no foreach-list');

done_testing();

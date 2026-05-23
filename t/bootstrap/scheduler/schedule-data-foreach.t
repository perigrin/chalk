# ABOUTME: Verifies ForeachStatement populates Roundtrip::Loop on the Loop IR node.
# ABOUTME: Migration 1 of Phase 1 — moves iterator/list annotation from Context onto IR.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::Node::Loop;
use Chalk::Scheduler::Roundtrip::Loop;
use Chalk::Bootstrap::BNF::Target::Perl;

my $ir = perl_pipeline();
plan skip_all => 'Perl grammar failed' unless defined $ir;

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScheduleDataForeachTest/g;
eval $generated;
plan skip_all => "Generated code failed: $@" if $@;

my $gen_grammar = Chalk::Grammar::Perl::ScheduleDataForeachTest::grammar();
my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
plan skip_all => 'IR parser not built' unless defined $parser;

my $semiring = $parser->semiring();
$semiring->reset_cache();

# Parse a method containing a foreach. We want a single Loop node in
# the resulting graph whose schedule_data is a populated Roundtrip::Loop.
my $src = 'my $sum = 0; for my $x (1, 2, 3) { $sum = $sum + $x; }';
my $result = $parser->parse_value($src);
ok(defined $result, 'foreach parses');

my $state = $result->cfg_state();
ok(defined $state && defined $state->{loop}, 'cfg_state exposes the Loop node');

my $loop = $state->{loop};
isa_ok($loop, 'Chalk::IR::Node::Loop');

my $sd = $loop->schedule_data();
ok(defined $sd, 'Loop has schedule_data populated')
    or BAIL_OUT('migration not applied — Loop.schedule_data still undef');
isa_ok($sd, 'Chalk::Scheduler::Roundtrip::Loop');
is($sd->node(), $loop, 'schedule_data.node points back at the Loop');

# Iterator should be the IR node for $x.
my $iter = $sd->iterator();
ok(defined $iter, 'schedule_data carries iterator');
isa_ok($iter, 'Chalk::IR::Node::Constant');
is($iter->value(), '$x', 'iterator is the IR node holding "$x"');

# List should be present (the (1, 2, 3) arrayref-of-Constants).
ok(defined $sd->list(), 'schedule_data carries list');

# This is a foreach, not a C-style for.
is($sd->is_for_style(), false, 'foreach is not for-style');
is($sd->for_init(),     undef, 'foreach has no for_init');
is($sd->for_step(),     undef, 'foreach has no for_step');

done_testing();

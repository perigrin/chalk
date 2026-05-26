# ABOUTME: Phase 7d unit tests for Target::C's schedule walker.
# ABOUTME: Exercises _emit_scheduled_c_body and _emit_c_schedule_item against minimal fixtures.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::MOP::Method;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::Bootstrap::Perl::Target::C;

# Build a minimal MOP::Method whose body is a single Return of a Constant.
my $factory = Chalk::IR::NodeFactory->new;
my $graph   = Chalk::IR::Graph->new;

my $mop = Chalk::MOP->new;
my $mop_class = $mop->declare_class('Test::ScheduleWalker');

# Construct the IR: Start -> Return(Constant('hello'))
my $start = $factory->make('Start');
$graph->merge($start);
my $value = $factory->make('Constant', const_type => 'string', value => 'hello');
$graph->merge($value);
my $ret = $factory->make_cfg('Return', inputs => [$start, $value]);
$graph->merge($ret);

my $method = $mop_class->declare_method('greet',
    params => ['$self'],
    body   => [$ret],
    graph  => $graph,
);

my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Test::ScheduleWalker',
);
$target->_set_current_slug('schedulewalker');

# _emit_scheduled_c_body should return an arrayref of C lines.
my $lines = $target->_emit_scheduled_c_body($method);
isa_ok($lines, 'ARRAY', '_emit_scheduled_c_body returns an arrayref');

# The body should contain the constant value somewhere.
my $body_text = join("\n", $lines->@*);
like($body_text, qr/hello/, 'body C contains the constant value');

done_testing();

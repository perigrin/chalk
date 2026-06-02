# ABOUTME: Phase 7d test that simple-body shortcuts fire from the schedule path.
# ABOUTME: Verifies single-Return-of-Constant emits `return newSViv(1)`, not the complex-method template.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::Perl::Target::C;

my $factory = Chalk::IR::NodeFactory->new;
my $graph   = Chalk::IR::Graph->new;
my $mop     = Chalk::MOP->new;
my $cls     = $mop->declare_class('Test::SimpleBody');

# Build IR: Start -> Return(Constant('42'))
# NOTE: use 42 not 1 — the simple-return path maps '1' to &PL_sv_yes
# and '0' to &PL_sv_no per legacy C.pm:129-132. Use a generic
# integer like 42 to exercise the `newSViv($raw)` path.
my $start = $factory->make('Start');
$graph->merge($start);
my $val = $factory->make('Constant', const_type => 'string', value => '42');
$graph->merge($val);
my $ret = $factory->make_cfg('Return', inputs => [$val]);
$ret->set_control_in($start);
$graph->merge($ret);

my $method = $cls->declare_method('answer',
    params => ['$self'],
    body   => [$ret],
    graph  => $graph,
);

my $target = Chalk::Bootstrap::Perl::Target::C->new(
    module_name => 'Test::SimpleBody',
);
$target->_set_current_slug('simplebody');

my $result = $target->_emit_method($method);
ok(defined $result, '_emit_method returns defined result');
ok(ref($result) eq 'HASH' && defined $result->{helper}, 'result has helper key');

my $helper = join("\n", $result->{helper}->@*);

# Simple-body shortcut for integer-42 should emit `return newSViv(42);` directly.
like($helper, qr/newSViv\(42\)/, 'integer literal 42 uses newSViv');
unlike($helper, qr/SV \*retval = NULL/, 'simple body does NOT use RETVAL pattern');

# Bonus: verify the special-case for '1' → &PL_sv_yes still works.
# Uses a fresh graph + factory to avoid scheduler ambiguity from the first graph.
{
    my $factory2 = Chalk::IR::NodeFactory->new;
    my $graph2   = Chalk::IR::Graph->new;
    my $start2   = $factory2->make('Start');
    $graph2->merge($start2);
    my $val_one = $factory2->make('Constant', const_type => 'string', value => '1');
    $graph2->merge($val_one);
    my $ret_one = $factory2->make_cfg('Return', inputs => [$val_one]);
    $ret_one->set_control_in($start2);
    $graph2->merge($ret_one);
    my $method_one = $cls->declare_method('one',
        params => ['$self'],
        body   => [$ret_one],
        graph  => $graph2,
    );
    my $result_one = $target->_emit_method($method_one);
    my $helper_one = join("\n", $result_one->{helper}->@*);
    like($helper_one, qr/PL_sv_yes/, "integer '1' maps to &PL_sv_yes (legacy parity)");
}

done_testing();

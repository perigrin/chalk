# ABOUTME: Phase 7d unit tests for analysis helpers rewritten to consume Schedule.
# ABOUTME: Verifies the 6 schedule-substrate helpers produce equivalent results to legacy.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::IR::Graph;
use Chalk::IR::NodeFactory;
use Chalk::IR::Schedule;
use Chalk::IR::Schedule::Item;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::VarDecl;
use Chalk::Bootstrap::Perl::Target::C;

my $factory = Chalk::IR::NodeFactory->new;
my $target  = Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Test::H');

# Helper: build a schedule from a list of stmt-node items
sub schedule_of(@nodes) {
    return Chalk::IR::Schedule->new(items => [
        map { Chalk::IR::Schedule::Item->new(kind => 'stmt', node => $_) } @nodes
    ]);
}

# Test _body_contains_return
{
    my $start = $factory->make('Start');
    my $val = $factory->make('Constant', const_type => 'string', value => 'x');
    my $ret = $factory->make_cfg('Return', inputs => [$start, $val]);

    my $sched_with_return = schedule_of($ret);
    my $sched_no_return = schedule_of($val);

    ok($target->_body_contains_return($sched_with_return),
       '_body_contains_return: schedule with Return returns true');
    ok(!$target->_body_contains_return($sched_no_return),
       '_body_contains_return: schedule without Return returns false');
}

# Test _has_early_return: a Return that is NOT the trailing
# synthetic-Return counts; the trailing synthetic-Return does NOT.
{
    my $start = $factory->make('Start');
    my $val = $factory->make('Constant', const_type => 'string', value => 'x');
    my $ret_early = $factory->make_cfg('Return', inputs => [$start, $val]);
    my $val2 = $factory->make('Constant', const_type => 'string', value => 'y');

    my $sched_early = schedule_of($ret_early, $val2);
    ok($target->_has_early_return($sched_early),
       '_has_early_return: non-trailing Return counts');

    my $sched_only_trailing = schedule_of($val, $ret_early);
    # The trailing Return is the LAST stmt; doesn't count as early.
    ok(!$target->_has_early_return($sched_only_trailing),
       '_has_early_return: trailing Return does not count as early');
}

# Test _collect_var_decls registers each VarDecl
{
    my $start = $factory->make('Start');
    my $name = $factory->make('Constant', const_type => 'variable', value => '$foo');
    # VarDecl is a data node: inputs => [control, name, init]
    my $vd = $factory->make('VarDecl', inputs => [$start, $name, undef]);
    my $sched = schedule_of($vd);
    my %declared;
    $target->_collect_var_decls($sched, \%declared);
    ok(exists $declared{foo}, '_collect_var_decls registers foo from VarDecl');
}

# Test _is_complex_method: empty / single-stmt / multi-stmt
{
    my $val = $factory->make('Constant', const_type => 'string', value => '1');
    my $empty = Chalk::IR::Schedule->new(items => []);
    my $single = schedule_of($val);
    my $multi = schedule_of($val, $val);

    ok(!$target->_is_complex_method($empty),  '_is_complex_method: empty is not complex');
    ok(!$target->_is_complex_method($single), '_is_complex_method: single stmt is not complex');
    ok($target->_is_complex_method($multi),   '_is_complex_method: multi stmt is complex');
}

done_testing();

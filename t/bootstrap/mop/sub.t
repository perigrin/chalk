# ABOUTME: Tests for Chalk::MOP::Sub metaobject.
# ABOUTME: Verifies accessors: name, class, params, return_type, graph.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Basic sub construction via declare_sub
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Utils');
    my $sub = $cls->declare_sub('helper', params => ['$x']);

    isa_ok($sub, 'Chalk::MOP::Sub');
    is($sub->name, 'helper', 'sub name');
    is(refaddr($sub->class), refaddr($cls), 'sub class points back');
    is_deeply($sub->params, ['$x'], 'params accessor');
}

# return_type defaults to undef
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Plain');
    my $sub = $cls->declare_sub('notype');

    ok(!defined $sub->return_type, 'return_type defaults to undef');
}

# params default to empty
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NoParams');
    my $sub = $cls->declare_sub('bare');

    is_deeply($sub->params, [], 'params default to empty');
}

# graph defaults to a fresh Chalk::IR::Graph instance
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Graphless');
    my $sub = $cls->declare_sub('stub');

    isa_ok($sub->graph, 'Chalk::IR::Graph', 'graph is a Chalk::IR::Graph');
}

# top-level subs belong to main
{
    my $mop = Chalk::MOP->new;
    my $main = $mop->for_class('main');
    my $sub = $main->declare_sub('run_app', params => ['@args']);

    is($sub->name, 'run_app', 'top-level sub name');
    is($main->name, $sub->class->name, 'sub belongs to main');
    is_deeply($sub->params, ['@args'], 'top-level sub params');

    my @subs = $main->subs;
    is(scalar @subs, 1, 'main has one sub');
}

done_testing();

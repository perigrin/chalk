# ABOUTME: Tests for Chalk::MOP::Sub metaobject.
# ABOUTME: Verifies accessors: name, class, params, return_type, graph.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

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

# THE METAOBJECT HOLDS THE RETURN TYPE it is given: which answer wins (only
# narrowing) is whole-program analysis's (t/bootstrap/ir/analysis-narrow-return-type.t).
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('HoldsSub');
    my $sub = $cls->declare_sub('s', return_type => 'Scalar');
    $sub->set_return_type('Int');
    is($sub->return_type, 'Int', 'set_return_type holds the type it is given');
}

# params default to empty
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('NoParams');
    my $sub = $cls->declare_sub('bare');

    is_deeply($sub->params, [], 'params default to empty');
}

# ITS BODY IS THE COMPILER'S: none unless one is handed in (the MOP makes
# none), and the one handed in is the one it holds, untouched.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Graphless');
    my $sub = $cls->declare_sub('stub');

    ok(!defined $sub->graph, 'no body unless the compiler hands one in');
    my $body = bless {}, 'An::Opaque::Body';
    my $given = $cls->declare_sub('stub', graph => $body);
    is($given->graph, $body, 'the body handed in is the one held');
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

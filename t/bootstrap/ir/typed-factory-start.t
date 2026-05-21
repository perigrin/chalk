# ABOUTME: Tests that Chalk::IR::NodeFactory->make('Start') and ->make('Return')
# ABOUTME: hash-cons like data nodes — matching Bootstrap factory's permissive
# ABOUTME: make() behavior. Required for Phase 7c Actions.pm flip away from
# ABOUTME: the Bootstrap singleton.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);
use lib 'lib';

use Chalk::IR::NodeFactory;

# make('Start') hash-conses across calls within one factory.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $s1 = $f->make('Start');
    my $s2 = $f->make('Start');
    isa_ok($s1, 'Chalk::IR::Node::Start', 'make Start returns Start node');
    is(refaddr($s1), refaddr($s2),
        'two make(Start) calls on the same factory return the same node');
}

# Different factories produce different Start objects.
{
    my $f1 = Chalk::IR::NodeFactory->new;
    my $f2 = Chalk::IR::NodeFactory->new;
    my $s1 = $f1->make('Start');
    my $s2 = $f2->make('Start');
    isnt(refaddr($s1), refaddr($s2),
        'Start from different factories are distinct objects');
}

# make_cfg('Start') still works and still allocates fresh (legacy semantics).
{
    my $f = Chalk::IR::NodeFactory->new;
    my $c1 = $f->make_cfg('Start');
    my $c2 = $f->make_cfg('Start');
    isnt(refaddr($c1), refaddr($c2),
        'make_cfg(Start) still allocates fresh objects per call');
}

# make('Return', ...) hash-conses across identical-input calls.
# Return has inputs => [control, value]; identical inputs ⇒ same content_hash.
{
    my $f = Chalk::IR::NodeFactory->new;
    my $start = $f->make('Start');
    my $val   = $f->make('Constant', const_type => 'integer', value => 7);
    my $r1 = $f->make('Return', inputs => [$start, $val]);
    my $r2 = $f->make('Return', inputs => [$start, $val]);
    isa_ok($r1, 'Chalk::IR::Node::Return', 'make Return returns Return node');
    is(refaddr($r1), refaddr($r2),
        'identical-input Returns are hash-consed by make()');
}

done_testing;

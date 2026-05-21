# ABOUTME: Tests that MOP::Method and MOP::Sub own a $factory field
# ABOUTME: parallel to their existing $graph field. Each new instance
# ABOUTME: gets a fresh Chalk::IR::NodeFactory by default.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(refaddr);
use lib 'lib';

use Chalk::MOP;
use Chalk::IR::NodeFactory;

# MOP::Method factory ownership
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('M');
    my $m = $cls->declare_method('foo');

    can_ok($m, 'factory');
    isa_ok($m->factory, 'Chalk::IR::NodeFactory',
        'MOP::Method->factory is a typed NodeFactory by default');

    # Two methods in the same class get independent factories.
    my $n = $cls->declare_method('bar');
    isnt(refaddr($m->factory), refaddr($n->factory),
        'two methods on the same class have distinct factories');
}

# MOP::Sub factory ownership
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('S');
    my $s = $cls->declare_sub('helper');

    can_ok($s, 'factory');
    isa_ok($s->factory, 'Chalk::IR::NodeFactory',
        'MOP::Sub->factory is a typed NodeFactory by default');

    my $t = $cls->declare_sub('other');
    isnt(refaddr($s->factory), refaddr($t->factory),
        'two subs on the same class have distinct factories');
}

# Explicit factory at construction wins over default
{
    my $f = Chalk::IR::NodeFactory->new;
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('X');
    my $m = $cls->declare_method('with_explicit', factory => $f);
    is(refaddr($m->factory), refaddr($f),
        'explicit factory at declare_method honored');
}

# Method's factory and graph are coupled (same per-method scope)
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Y');
    my $m = $cls->declare_method('m');
    my $n = $cls->declare_method('n');
    isnt(refaddr($m->graph),   refaddr($n->graph),   'distinct graphs');
    isnt(refaddr($m->factory), refaddr($n->factory), 'distinct factories');
}

done_testing;

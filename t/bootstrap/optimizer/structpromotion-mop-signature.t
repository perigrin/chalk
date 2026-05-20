# ABOUTME: Tests that StructPromotion::run accepts a Chalk::MOP and returns one.
# ABOUTME: Per Phase 5, schemas live as a side-structure / annotation on the MOP.
use 5.42.0;
use utf8;
use Test::More;
use Scalar::Util qw(blessed);
use lib 'lib';

use Chalk::Bootstrap::Optimizer::StructPromotion;
use Chalk::MOP;

ok(Chalk::Bootstrap::Optimizer::StructPromotion->can('run'),
    'StructPromotion has run method');

# Empty MOP in, MOP out (in scalar context - no tuple).
{
    my $mop = Chalk::MOP->new;
    my $pass = Chalk::Bootstrap::Optimizer::StructPromotion->new;
    my $out = $pass->run($mop);

    ok(defined $out, 'run($mop) returns a defined value');
    ok(blessed($out) && $out isa Chalk::MOP,
        'run($mop) returns a Chalk::MOP')
        or diag('got: ' . (defined $out ? ref($out) : 'undef'));
}

# MOP with one class: still returns MOP unchanged when no schemas.
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Plain');
    $cls->declare_method('noop', params => []);

    my $pass = Chalk::Bootstrap::Optimizer::StructPromotion->new;
    my $out = $pass->run($mop);
    ok(defined $out && $out isa Chalk::MOP,
        'run($mop) with class returns a MOP');
}

done_testing();

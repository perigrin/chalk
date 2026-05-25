# ABOUTME: Tests that Chalk::MOP is threaded through the parse pipeline.
# ABOUTME: Verifies $ctx->mop() is defined and is a Chalk::MOP instance after parsing.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Context;

# Test 1: set_mop stores the MOP and current_mop() returns it
{
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    is(
        refaddr(Chalk::Bootstrap::Semiring::SemanticAction::current_mop()),
        refaddr($mop),
        'set_mop stores the MOP'
    );
}

# Test 2: set_mop invalidates the singleton so one() rebuilds with new MOP
{
    my $mop1 = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop1);
    my $sa1 = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => undef);
    my $one1 = $sa1->one();
    is(refaddr($one1->mop()), refaddr($mop1), 'first one() carries first MOP');

    my $mop2 = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop2);
    my $sa2 = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => undef);
    my $one2 = $sa2->one();
    is(refaddr($one2->mop()), refaddr($mop2), 'after set_mop, one() carries new MOP');
    isnt(refaddr($mop1), refaddr($mop2), 'two MOPs are distinct objects');
}

# Test 3: one() Context has mop field when MOP is set
{
    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => undef);
    my $one = $sa->one();
    isa_ok($one, 'Chalk::Bootstrap::Context');
    ok(defined $one->mop(), 'one() Context has defined mop');
    isa_ok($one->mop(), 'Chalk::MOP');
    is(refaddr($one->mop()), refaddr($mop), 'one() Context carries the MOP');
}

# Test 4: mop defaults to undef when no set_mop called (reset first)
{
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop(undef);
    my $sa = Chalk::Bootstrap::Semiring::SemanticAction->new(actions => undef);
    my $one = $sa->one();
    ok(!defined $one->mop(), 'one() mop is undef when no MOP set');
}

# Test 5: After a real parse, $ctx->mop returns the installed MOP.
# This is the canonical contract that motivated the propagation fix.
{
    use lib 't/bootstrap/lib';
    use TestPipeline qw(parse_perl_source);

    my $mop = Chalk::MOP->new;
    Chalk::Bootstrap::Semiring::SemanticAction::set_mop($mop);

    my $src = "class A { method f { 1 } }\nclass B { method g { 2 } }\n";
    my ($ir, $sa, $ctx) = parse_perl_source($src);
    ok(defined $ctx, 'parse succeeds');
    is(refaddr($ctx->mop), refaddr($mop),
       'parse root $ctx->mop is the installed MOP (post-propagation-fix)');
}

done_testing();

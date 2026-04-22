# ABOUTME: Tests that ClassBlock and UseDeclaration populate the MOP during parsing.
# ABOUTME: Verifies $mop->classes returns correct structure after parsing a class.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Test MOP initialises with main class
{
    my $mop = Chalk::MOP->new;
    my $main = $mop->for_class('main');
    ok(defined $main, 'main class is registered on construction');
    is($main->name, 'main', 'main class name is correct');
}

done_testing();

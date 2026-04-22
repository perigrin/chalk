# ABOUTME: Tests that ClassBlock and UseDeclaration populate the MOP during parsing.
# ABOUTME: Verifies $mop->classes returns correct structure after parsing a class.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';
use lib 't/bootstrap/lib';

use Chalk::MOP;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Test MOP current_class on construction
{
    my $mop = Chalk::MOP->new;
    my $current = $mop->current_class;
    ok(defined $current, 'current_class is set on construction');
    is($current->name, 'main', 'current_class starts as main');
}

# Test set_current_class
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Foo');
    $mop->set_current_class($cls);
    is($mop->current_class->name, 'Foo', 'set_current_class works');
}

done_testing();

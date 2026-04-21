# ABOUTME: Tests for Chalk::MOP top-level compilation-unit owner.
# ABOUTME: Verifies declare_class, classes(), for_class(), and implicit main seeding.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Implicit main class seeded on construction
{
    my $mop = Chalk::MOP->new;
    isa_ok($mop, 'Chalk::MOP');

    my @classes = $mop->classes;
    is(scalar @classes, 1, 'new MOP has exactly one class (implicit main)');

    my $main = $classes[0];
    isa_ok($main, 'Chalk::MOP::Class');
    is($main->name, 'main', 'implicit class is named main');
}

# for_class('main') returns the implicit main class
{
    my $mop = Chalk::MOP->new;
    my $main = $mop->for_class('main');
    ok(defined $main, 'for_class(main) returns a defined value');
    isa_ok($main, 'Chalk::MOP::Class');
    is($main->name, 'main', 'for_class(main) returns the main class');
}

# for_class on nonexistent class returns undef
{
    my $mop = Chalk::MOP->new;
    my $result = $mop->for_class('Nonexistent');
    ok(!defined $result, 'for_class on unknown class returns undef');
}

# declare_class creates a new class
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Point');
    isa_ok($cls, 'Chalk::MOP::Class');
    is($cls->name, 'Point', 'declared class has correct name');
    ok(!defined $cls->superclass, 'no superclass by default');

    my @classes = $mop->classes;
    is(scalar @classes, 2, 'MOP now has 2 classes (main + Point)');
}

# declare_class with superclass
{
    my $mop = Chalk::MOP->new;
    my $base = $mop->declare_class('Shape');
    my $derived = $mop->declare_class('Circle', superclass => $base);
    is($derived->name, 'Circle', 'derived class name');
    is($derived->superclass->name, 'Shape', 'superclass is Shape');
}

# for_class retrieves declared class
{
    my $mop = Chalk::MOP->new;
    $mop->declare_class('Foo');
    my $foo = $mop->for_class('Foo');
    ok(defined $foo, 'for_class retrieves declared class');
    is($foo->name, 'Foo', 'retrieved class has correct name');
}

# for_class returns same object as declare_class returned
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Bar');
    my $retrieved = $mop->for_class('Bar');
    is(refaddr($cls), refaddr($retrieved), 'for_class returns same object as declare_class');
}

# classes() returns all declared classes
{
    my $mop = Chalk::MOP->new;
    $mop->declare_class('A');
    $mop->declare_class('B');
    $mop->declare_class('C');

    my @classes = $mop->classes;
    is(scalar @classes, 4, '4 classes total (main + A + B + C)');

    my @names = sort map { $_->name } @classes;
    is_deeply(\@names, [qw(A B C main)], 'all class names present');
}

# mop() accessor on class points back to owning MOP
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Widget');
    is(refaddr($cls->mop), refaddr($mop), 'class mop() points back to owning MOP');

    my $main = $mop->for_class('main');
    is(refaddr($main->mop), refaddr($mop), 'main class mop() points back too');
}

done_testing();

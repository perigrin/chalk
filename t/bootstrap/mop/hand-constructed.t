# ABOUTME: Smoke test for frontend-agnostic MOP construction.
# ABOUTME: Constructs a complete MOP without any parser involvement to validate the API surface.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Build a realistic Chalk program's MOP entirely by hand:
#   package main: use strict; use utf8; sub run(@args) { ... }
#   class Point :isa(Shape) {
#       field $x :param :reader;
#       field $y :param :reader;
#       ADJUST { validate }
#       method distance($other) { ... }
#       method to_string() { ... }
#       my sub _helper($val) { ... }
#   }
#   class Shape {
#       method draw() { ... }
#   }

my $mop = Chalk::MOP->new;

# main class (implicit)
my $main = $mop->for_class('main');
ok(defined $main, 'implicit main exists');
$main->declare_import('strict');
$main->declare_import('utf8');
$main->declare_sub('run', params => ['@args']);

# Shape class (base)
my $shape = $mop->declare_class('Shape');
$shape->declare_method('draw');

# Point class (derived)
my $point = $mop->declare_class('Point', superclass => $shape);
$point->declare_field('$x', sigil => '$', param_name => 'x',
    attributes => [':param', ':reader']);
$point->declare_field('$y', sigil => '$', param_name => 'y',
    attributes => [':param', ':reader']);
$point->declare_adjust();
$point->declare_method('distance', params => ['$other']);
$point->declare_method('to_string');
$point->declare_sub('_helper', params => ['$val']);

# Verify overall structure
{
    my @classes = $mop->classes;
    is(scalar @classes, 3, '3 classes: main, Shape, Point');
    my @names = sort map { $_->name } @classes;
    is_deeply(\@names, [qw(Point Shape main)], 'correct class names');
}

# Verify main
{
    my @imports = $main->imports;
    is(scalar @imports, 2, 'main has 2 imports');
    is($imports[0]->module, 'strict', 'first import is strict');
    is($imports[1]->module, 'utf8', 'second import is utf8');

    my @subs = $main->subs;
    is(scalar @subs, 1, 'main has 1 sub');
    is($subs[0]->name, 'run', 'sub is run');
    is_deeply($subs[0]->params, ['@args'], 'run params');
}

# Verify Shape
{
    my @methods = $shape->methods;
    is(scalar @methods, 1, 'Shape has 1 method');
    is($methods[0]->name, 'draw', 'method is draw');
    ok(!defined $shape->superclass, 'Shape has no superclass');
}

# Verify Point
{
    my @fields = $point->fields;
    is(scalar @fields, 2, 'Point has 2 fields');
    is($fields[0]->name, '$x', 'first field is $x');
    is($fields[0]->fieldix, 0, '$x at fieldix 0');
    is($fields[0]->param_name, 'x', '$x param_name');
    is_deeply([$fields[0]->attributes], [':param', ':reader'], '$x attributes');
    is($fields[1]->name, '$y', 'second field is $y');
    is($fields[1]->fieldix, 1, '$y at fieldix 1');

    my @methods = $point->methods;
    is(scalar @methods, 2, 'Point has 2 methods');
    is($methods[0]->name, 'distance', 'first method is distance');
    is_deeply($methods[0]->params, ['$other'], 'distance params');
    is($methods[1]->name, 'to_string', 'second method is to_string');

    my @subs = $point->subs;
    is(scalar @subs, 1, 'Point has 1 sub');
    is($subs[0]->name, '_helper', 'sub is _helper');

    my @adjust = $point->adjust_blocks;
    is(scalar @adjust, 1, 'Point has 1 ADJUST block');

    is($point->superclass->name, 'Shape', 'Point superclass is Shape');
}

# Verify resolution
{
    my $draw = $point->find_method('draw');
    ok(defined $draw, 'Point can find inherited draw method');
    is($draw->name, 'draw', 'found draw by name');
    is(refaddr($draw->class), refaddr($shape), 'draw belongs to Shape');

    my $distance = $point->find_method('distance');
    is(refaddr($distance->class), refaddr($point), 'distance belongs to Point');

    my @ancestors = $point->ancestors;
    is(scalar @ancestors, 1, 'Point has 1 ancestor');
    is($ancestors[0]->name, 'Shape', 'ancestor is Shape');

    my @adjust = $point->resolve_adjust_blocks;
    is(scalar @adjust, 1, 'resolve_adjust_blocks returns 1 block');
    is(refaddr($adjust[0]->class), refaddr($point), 'adjust block belongs to Point');
}

# Verify MOP backrefs
{
    is(refaddr($main->mop), refaddr($mop), 'main backref to MOP');
    is(refaddr($shape->mop), refaddr($mop), 'Shape backref to MOP');
    is(refaddr($point->mop), refaddr($mop), 'Point backref to MOP');

    my @point_fields = $point->fields;
    is(refaddr($point_fields[0]->class), refaddr($point), 'field backref to class');

    my @point_methods = $point->methods;
    is(refaddr($point_methods[0]->class), refaddr($point), 'method backref to class');
}

done_testing();

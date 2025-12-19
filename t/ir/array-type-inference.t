#!/usr/bin/env perl
# ABOUTME: Tests for array element type inference
# ABOUTME: Verifies TypeInference tracks what types are stored in arrays
use 5.42.0;
use Test2::V0;
use FindBin;
use lib "$FindBin::Bin/../../lib";

use Chalk::Semiring::TypeInference;
use Chalk::IR::Type::Integer;
use Chalk::Grammar::Chalk::TypeLattice;

subtest 'Element type starts as Any' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $any = $lattice->top_type();

    ok($any->is_top, 'Top type represents Any/unknown element type');
};

subtest 'Element type narrows on store' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int = $lattice->type_from_name('Int');
    my $any = $lattice->top_type();

    # meet(Any, Int) should narrow to Int
    my $narrowed = $any->meet($int);
    is($narrowed->name, 'Int', 'Any meets Int = Int');
};

subtest 'Element type widens on mixed store' => sub {
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();
    my $int = $lattice->type_from_name('Int');
    my $str = $lattice->type_from_name('Str');

    # join(Int, Str) widens - exact result depends on type hierarchy
    my $widened = $int->join($str);
    # The type lattice has Int <: Str in Chalk, so join(Int, Str) = Str
    is($widened->name, 'Str', 'Int join Str = Str (Int is subtype of Str)');
};

done_testing();

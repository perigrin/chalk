# ABOUTME: Maybe[T] is T|Undef on the lattice: T and Undef are below it, it is below
# ABOUTME: Scalar, a Maybe absorbs Undef in a join, and a meet with T narrows it to T.

use 5.42.0;
use utf8;
use Test2::V0;

use lib 'lib', 't/lib';
use Chalk::Grammar::Perl::TypeLibrary;

my $sub  = \&Chalk::Grammar::Perl::TypeLibrary::is_subtype;
my $join = \&Chalk::Grammar::Perl::TypeLibrary::join_types;
my $meet = \&Chalk::Grammar::Perl::TypeLibrary::meet_types;
my $is   = \&Chalk::Grammar::Perl::TypeLibrary::is_lattice_type;

subtest 'Maybe[T] is a lattice type when T is' => sub {
    ok $is->('Maybe[Boolean]'), 'Maybe[Boolean]';
    ok $is->('Maybe[Int]'),     'Maybe[Int]';
    ok !$is->('Maybe[Slot]'),   'not over a machine encoding';
    ok !$is->('Maybe[]'),       'not over nothing';
};

subtest 'T and Undef are below Maybe[T]; Maybe[T] is below Scalar' => sub {
    ok $sub->('Boolean', 'Maybe[Boolean]'), 'T <: Maybe[T]';
    ok $sub->('Undef',   'Maybe[Boolean]'), 'Undef <: Maybe[T]';
    ok $sub->('Int',     'Maybe[Num]'),     'a subtype of T is below Maybe[T]';
    ok $sub->('Maybe[Int]', 'Maybe[Num]'),  'Maybe is covariant';
    ok $sub->('Maybe[Boolean]', 'Scalar'),  'Maybe[T] <: Scalar';
    ok !$sub->('Maybe[Boolean]', 'Boolean'), 'Maybe[T] is not below T: it may be undef';
    ok !$sub->('Str', 'Maybe[Boolean]'),    'an unrelated type is not below it';
};

subtest 'a join keeps the Maybe' => sub {
    is $join->('Maybe[Boolean]', 'Undef'),   'Maybe[Boolean]', 'absorbs Undef';
    is $join->('Maybe[Boolean]', 'Boolean'), 'Maybe[Boolean]', 'absorbs its T';
    is $join->('Maybe[Int]', 'Num'),         'Maybe[Num]',     'joins the T parts';
    is $join->('Maybe[Int]', 'Maybe[Num]'),  'Maybe[Num]',     'two Maybes';
    is $join->('Maybe[Boolean]', 'Str'),     'Scalar',         'Maybe[Scalar] is Scalar: it already holds undef';
};

subtest 'a meet narrows it' => sub {
    is $meet->('Maybe[Boolean]', 'Boolean'), 'Boolean', 'with T: the defined case';
    is $meet->('Maybe[Boolean]', 'Undef'),   'Undef',   'with Undef: the undef case';
    is $meet->('Maybe[Boolean]', 'Scalar'),  'Maybe[Boolean]', 'with a supertype: itself';
};

done_testing;

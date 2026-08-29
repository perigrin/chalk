# ABOUTME: `Scalar` is the top of the scalar spine, not a commitment -- the
# ABOUTME: fixpoint must be free to refine it when the graph proves narrower.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib', 't/lib';

require Chalk::IR::Analysis;
my $narrowed = \&Chalk::IR::Analysis::_is_narrowed;

subtest 'Unknown and absence are not commitments' => sub {
    ok(!$narrowed->(undef),     'an absent stamp is not narrowed');
    ok(!$narrowed->('Unknown'), 'Unknown is not narrowed -- it answers nothing');
};

subtest 'a concrete type IS a commitment' => sub {
    ok($narrowed->('Int'),      'Int is narrowed');
    ok($narrowed->('Str'),      'Str is narrowed');
    ok($narrowed->('Boolean'),  'Boolean is narrowed');
    ok($narrowed->('Undef'),    'Undef is narrowed -- a unit type, fully known');
};

subtest 'Scalar is NOT a commitment -- it is the top of the spine' => sub {
    # THE POINT. `Scalar` is what the join yields when nothing narrower was
    # proven, and since 8c15e32 the producer ships it for every un-narrowable
    # Subscript. Treating it as committed makes three fixpoint guards
    # (Analysis.pm :1150, :1249, :1826) skip such a node PERMANENTLY, so it can
    # never be refined to Int even where the graph proves it.
    #
    # Phase 3's G5 measured zero instances of this and could not reproduce it,
    # because at that time nothing produced a Scalar stamp. The producer change
    # made the hazard live.
    ok(!$narrowed->('Scalar'),
       'Scalar is refinable -- the fixpoint must revisit it');
};

subtest 'the guard still terminates: refinement only moves DOWN the spine' => sub {
    # _is_narrowed is the fixpoint's termination latch (pinned by
    # ir/propagate-fixpoint-terminates.t). Exempting Scalar is safe because the
    # spine is finite and a refinement is strictly downward: Scalar -> Str ->
    # Num -> Int, at most three steps, and each step lands on a value that IS a
    # commitment and stops being revisited.
    my $is_sub = \&Chalk::Grammar::Perl::TypeLibrary::is_subtype;
    require Chalk::Grammar::Perl::TypeLibrary;
    for my $t (qw(Int Num Str Undef Boolean)) {
        ok($is_sub->($t, 'Scalar'), "$t is below Scalar, so refining to it is downward");
        ok($narrowed->($t), "...and $t IS a commitment, so the fixpoint stops there");
    }
};

done_testing;

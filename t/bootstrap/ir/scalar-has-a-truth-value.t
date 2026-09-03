# ABOUTME: Every inhabitant of Scalar has a boolean reading, so Scalar -> Boolean is a real coercion.
# ABOUTME: T1 had no Scalar row at all, which blocked && and || over a tagged cell.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

use Chalk::IR::Analysis;
use Chalk::Grammar::Perl::TypeLibrary;

# `%_COERCIBLE_TO` states WHICH COERCIONS EXIST IN PERL. Int, Num, Str and
# Undef all list Boolean as a target; `Scalar` had NO ROW AT ALL -- so
# `_coercion_exists('Scalar', 'Boolean')` was false, and the backend's `&&`/`||`
# refused a tagged cell for want of a coercion T1 said did not exist.
#
# It does exist, and this file measures it against perl rather than asserting
# it from the table (which would be the table grading its own homework -- the
# failure mode that kept `Boolean => 'Str'` green for as long as it did).
#
# THE ARGUMENT IS COMPOSITIONAL, and that is why it is safe. `Scalar` is the
# join of the single-value types; every one of them individually has a truth
# value, and perl's truthiness is total -- no value raises, and none is
# undefined-behaviour. So the join has one too, and the coercion is exactly the
# per-tag dispatch the backend already implements for each member.

subtest 'perl gives every inhabitant of Scalar a truth value' => sub {
    # One witness per branch of Scalar, including the pairs that DISAGREE with
    # a naive "nonzero is true" reading -- "0" is false but "00" is true, and
    # an empty string is false where a reference is true. A single witness
    # would prove nothing about the join.
    my @witnesses = (
        ['Int 0',      0,        0],
        ['Int 1',      1,        1],
        ['Num 0.0',    0.0,      0],
        ['Num 3.5',    3.5,      1],
        ['Str ""',     '',       0],
        ['Str "0"',    '0',      0],
        ['Str "00"',   '00',     1],
        ['Str "a"',    'a',      1],
        ['Undef',      undef,    0],
        ['true',       !!1,      1],
        ['false',      !!0,      0],
        ['ArrayRef',   [1,2],    1],
        ['CodeRef',    sub {1},  1],
    );

    my @wrong;
    my @died;
    for my $w (@witnesses) {
        my ($label, $val, $want) = @$w;
        no warnings 'uninitialized';
        my $got = eval { $val ? 1 : 0 };
        if ($@) { push @died, $label; next }
        push @wrong, "$label (got $got, want $want)" if $got != $want;
    }

    is_deeply \@died, [],
        'NO inhabitant of Scalar fails to produce a boolean -- truthiness is total';
    is_deeply \@wrong, [],
        'and every one produces the value perl documents';
};

subtest 'T1 admits the coercion perl performs' => sub {
    ok Chalk::IR::Analysis::_coercion_exists('Scalar', 'Boolean'),
        'Scalar -> Boolean exists at T1'
        or diag("  perl coerces every scalar to a boolean and never dies doing\n"
              . "  it; a table that says otherwise is describing a language\n"
              . "  other than perl");

    # The siblings that already worked, asserted here so a change that adds
    # Scalar by breaking them is visible.
    ok Chalk::IR::Analysis::_coercion_exists($_, 'Boolean'),
        "$_ -> Boolean still exists"
        for qw(Int Num Str Undef);
};

# COERCION-EXISTS IS NOT SUBTYPING, and this is the guard that keeps the new
# row from being read as one. Scalar is the PARENT of Str on the lattice, so
# `Scalar <: Boolean` would inverte the hierarchy -- the coercion says a
# conversion is defined, not that one type contains the other.
subtest 'the coercion does not make Scalar a subtype of Boolean' => sub {
    is +(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Scalar', 'Boolean') ? 1 : 0), 0,
        'Scalar is NOT a subtype of Boolean';
    is +(Chalk::Grammar::Perl::TypeLibrary::is_subtype('Boolean', 'Scalar') ? 1 : 0), 1,
        'Boolean IS a subtype of Scalar -- the relation runs the other way';
};

done_testing;

# ABOUTME: Pins that a join CLIMBS to Unknown only via Code/Glob/IO/Format --
# ABOUTME: the non-arity entities, whose %PARENT is Unknown itself.
use 5.42.0;
use utf8;
use Test::More;
use lib 'lib';

require Chalk::Grammar::Perl::TypeLibrary;
my $join = \&Chalk::Grammar::Perl::TypeLibrary::join_types;

# Every %PARENT member except Unknown itself.
my @MEMBERS = qw(
    Array ArrayRef Boolean Code CodeRef DualVar Format Glob GlobRef Hash
    HashRef Int IO List LValueRef Num Object Ref Regex Scalar ScalarRef Str
    Undef Void VString
);
my @NAMES = qw(Code Glob IO Format);
my %IS_NAME = map { $_ => 1 } @NAMES;

subtest 'a join climbs to Unknown ONLY through a name-like entity' => sub {
    my @offenders;
    for my $a (@MEMBERS) {
        for my $b (@MEMBERS) {
            my $r = $join->($a, $b) // next;
            next unless $r eq 'Unknown';
            push @offenders, "$a + $b" unless $IS_NAME{$a} || $IS_NAME{$b};
        }
    }
    is_deeply(\@offenders, [],
        'no pair of ordinary types joins UP to Unknown')
        or diag "climbed without a name: @offenders";
};

subtest 'the four names DO climb, so the test above is not vacuous' => sub {
    # Without this, the assertion could pass because nothing climbs at all --
    # e.g. if join_types were changed to return undef on incomparable pairs.
    for my $n (@NAMES) {
        is($join->($n, 'Int'), 'Unknown', "join($n, Int) climbs to Unknown");
    }
    is($join->('List', 'Code'), 'Unknown',
        'even List climbs when paired with a name -- List is a victim, not an exception');
};

subtest 'ordinary joins stay put' => sub {
    is($join->('List',  'Int'),      'List',   'join(List, Int) = List');
    is($join->('Array', 'Int'),      'List',   'join(Array, Int) = List');
    is($join->('List',  'Array'),    'List',   'join(List, Array) = List');
    is($join->('Int',   'ArrayRef'), 'Scalar', 'join(Int, ArrayRef) = Scalar');
    is($join->('Int',   'Str'),      'Str',    'join(Int, Str) = Str');
};

subtest 'Glob <: List is PROPOSED, not implemented' => sub {
    # If this ever goes green, the 2026-08-28 proposal has landed and the
    # climb census above must be re-measured -- Glob would stop being a name.
    my $is = \&Chalk::Grammar::Perl::TypeLibrary::is_subtype;
    ok(!$is->('Glob', 'List'), 'is_subtype(Glob, List) is still false');
    ok(!$is->('Code', 'List'), 'is_subtype(Code, List) is still false');
    ok($is->('Array', 'List'), 'is_subtype(Array, List) IS true -- arity-bearing');
};

done_testing;

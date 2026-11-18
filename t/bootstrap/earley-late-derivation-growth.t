# ABOUTME: Semiring work must stay polynomial in input length on an ambiguous grammar.
# ABOUTME: Late derivations of one item are summed and processed once, not once per derivation.
use 5.42.0;
use experimental 'class';
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

# Boolean semiring that counts the work the parser asks of it.
class CountingBoolean {
    field $inner = Chalk::Bootstrap::Semiring::Boolean->new();
    field $multiplies  :reader = 0;
    field $completions :reader = 0;
    field %seen;

    method zero() { return $inner->zero() }
    method one() { return $inner->one() }
    method one_with_control($node) { return $inner->one_with_control($node) }
    method is_zero($value) { return $inner->is_zero($value) }
    method add($left, $right) { return $inner->add($left, $right) }

    method multiply($left, $right) {
        $multiplies++;
        my $ann = $right->annotations();
        if ($ann->{complete}) {
            $completions++;
            $seen{ join ',', $ann->@{qw(rule_name alt_idx pos origin)} } = true;
        }
        return $inner->multiply($left, $right);
    }

    # Number of distinct completed items (rule, alternative, origin, position).
    method distinct_completions() { return scalar keys %seen }
}

sub terminal($value) {
    return Chalk::Grammar::Symbol->new(type => 'terminal', value => $value);
}

sub reference($value) {
    return Chalk::Grammar::Symbol->new(type => 'reference', value => $value);
}

# E ::= B | a ;  B ::= E + E ;
# "a+a+...+a" has Catalan-many parses. The unit rule E ::= B makes a
# completed E reach its parent before the E's other derivations arrive,
# so those derivations are late.
sub ambiguous_grammar() {
    return [
        Chalk::Grammar::Rule->new(
            name        => 'E',
            expressions => [[reference('B')], [terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[reference('E'), terminal('\+'), reference('E')]],
        ),
    ];
}

sub measure($terms) {
    my $semiring = CountingBoolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => ambiguous_grammar(),
        semiring => $semiring,
    );
    my $accepted = $parser->parse(join '+', ('a') x $terms);
    return ($accepted, $semiring);
}

my ($ok_small, $small) = measure(7);
my ($ok_large, $large) = measure(14);

ok($ok_small, 'accepts 7 terms');
ok($ok_large, 'accepts 14 terms');

# A recognizer's chart has one item per (rule, dot, origin, position): the
# number of distinct completions is quadratic here (n^2: 49 and 196).
is($small->distinct_completions(), 49,  '7 terms: 49 distinct completed items');
is($large->distinct_completions(), 196, '14 terms: 196 distinct completed items');

# Doubling the input may multiply cubic work by 8. Processing every
# derivation on its own multiplies it by more than 100.
my $multiply_growth = $large->multiplies() / $small->multiplies();
cmp_ok($multiply_growth, '<', 16,
    'multiply calls grow polynomially when the input doubles')
    or diag sprintf('7 terms: %d, 14 terms: %d',
        $small->multiplies(), $large->multiplies());

my $completion_growth = $large->completions() / $small->completions();
cmp_ok($completion_growth, '<', 16,
    'completion reifications grow polynomially when the input doubles')
    or diag sprintf('7 terms: %d, 14 terms: %d',
        $small->completions(), $large->completions());

# Summing late derivations must not lose or repeat one. A semiring that
# counts derivations gives the Catalan numbers on this grammar.
package CountingDerivations {
    sub new($class) { return bless {}, $class }
    sub zero($self) { return 0 }
    sub one($self) { return 1 }
    sub one_with_control($self, $node) { return 1 }
    sub is_zero($self, $value) { return $value == 0 }
    sub add($self, $left, $right) { return $left + $right }

    # A scan or completion event arrives as a Context: it counts as one.
    sub multiply($self, $left, $right) {
        return $left * (ref $right ? 1 : $right);
    }
}

my @catalan = (1, 1, 2, 5, 14, 42, 132, 429, 1430, 4862);
for my $leo (true, false) {
    my @counts;
    for my $terms (1 .. 10) {
        my $parser = Chalk::Bootstrap::Earley->new(
            grammar     => ambiguous_grammar(),
            semiring    => CountingDerivations->new(),
            leo_enabled => $leo,
        );
        push @counts, $parser->parse_value(join '+', ('a') x $terms);
    }
    is_deeply(\@counts, \@catalan,
        'derivation counts are the Catalan numbers, Leo ' . ($leo ? 'on' : 'off'));
}

# Rejection still works on the same grammar.
my $reject = Chalk::Bootstrap::Earley->new(
    grammar  => ambiguous_grammar(),
    semiring => CountingBoolean->new(),
);
ok(!$reject->parse('a+a+'), 'rejects a dangling operator');
ok(!$reject->parse('a+a+a+a+a+a+a+a+a+a+a+a+a+'),
    'rejects a long input with a dangling operator');

done_testing();

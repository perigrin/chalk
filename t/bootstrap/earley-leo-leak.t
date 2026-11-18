# ABOUTME: A parse must not keep its values alive after the next parse starts.
# ABOUTME: A Leo item that refers to itself is never freed, nor is the value it holds.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;

# A semiring whose values count how many of them are alive.
package TrackedValue {
    our $LIVE = 0;
    sub new($class, $zero = false) {
        $LIVE++;
        return bless { zero => $zero }, $class;
    }
    sub DESTROY($self) { $LIVE-- }
}

package TrackingSemiring {
    sub new($class) { return bless {}, $class }
    sub zero($self) { return TrackedValue->new(true) }
    sub one($self) { return TrackedValue->new() }
    sub one_with_control($self, $node) { return TrackedValue->new() }
    sub is_zero($self, $value) { return $value->{zero} }
    sub multiply($self, $left, $right) { return TrackedValue->new($left->{zero}) }
    sub add($self, $left, $right) { return TrackedValue->new($left->{zero} && $right->{zero}) }
}

sub terminal($value) {
    return Chalk::Grammar::Symbol->new(type => 'terminal', value => $value);
}

sub reference($value) {
    return Chalk::Grammar::Symbol->new(type => 'reference', value => $value);
}

# Right recursion: every completion is deterministic, so Leo items are made.
# List ::= Item List | Item ;  Item ::= x ;
my $grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'List',
        expressions => [[reference('Item'), reference('List')], [reference('Item')]],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'Item',
        expressions => [[terminal('x')]],
    ),
];

my $parser = Chalk::Bootstrap::Earley->new(
    grammar  => $grammar,
    semiring => TrackingSemiring->new(),
);

my @live;
for my $round (1 .. 4) {
    ok($parser->parse('x' x 50), "parse $round accepts");
    push @live, $TrackedValue::LIVE;
}

# The parser may hold the state of its latest parse until the next one
# starts, so the first count is not zero. It must not grow.
cmp_ok($live[0], '>', 0, 'the latest parse holds some values');
is($live[1], $live[0], 'second parse: the first parse was freed');
is($live[3], $live[0], 'fourth parse: no values pile up');

done_testing();

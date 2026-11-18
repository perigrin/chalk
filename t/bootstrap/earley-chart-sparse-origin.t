# ABOUTME: A chart cell stores one entry per item, however far back the item's origin is.
# ABOUTME: A cell indexed densely by distance costs one slot per position back to the origin.
use 5.42.0;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

sub terminal($value)  { Chalk::Grammar::Symbol->new(type => 'terminal',  value => $value) }
sub reference($value) { Chalk::Grammar::Symbol->new(type => 'reference', value => $value) }
sub rule($name, @alts) { Chalk::Grammar::Rule->new(name => $name, expressions => [@alts]) }

# List ::= List Item | Item ;  Item ::= x ; ;
# The last row holds the List items, whose origin is 0: the whole input back.
my $grammar = [
    rule('List', [reference('List'), reference('Item')], [reference('Item')]),
    rule('Item', [terminal('x'), terminal(';')]),
];

# Storage of the last chart row after parsing $items items.
sub last_row($items) {
    local $ENV{CHALK_CHART_PROFILE} = 1;
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    );
    ok($parser->parse('x;' x $items), "accepts $items items");
    return $parser->chart_snapshot()->[-1];
}

my $short = last_row(10);
my $long  = last_row(1000);

cmp_ok($long->{entries}, '>', 0, 'the last row holds items');
is($long->{entries}, $short->{entries}, 'it holds the same items after a long input as after a short one');
is($long->{slots}, $long->{entries}, 'a row stores one slot per item');
is($long->{slots}, $short->{slots}, 'the slots of a row do not grow with the distance to its origins');

# The representation: a cell maps relative distance to value.
is(Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
    )->chart_origin_type(), 'HASH', 'the origin dimension of a cell is a hash');

done_testing();

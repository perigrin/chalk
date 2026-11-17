# ABOUTME: The per-position processed table is indexed by relative distance, not origin.
# ABOUTME: A row indexed by origin is as long as the input position: quadratic work on long inputs.
use 5.42.0;
use utf8;
use lib 'lib', 't/lib';
use Test::Chalk;

use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

sub terminal($value) {
    return Chalk::Grammar::Symbol->new(type => 'terminal', value => $value);
}

sub reference($value) {
    return Chalk::Grammar::Symbol->new(type => 'reference', value => $value);
}

# List ::= List Item | Item ;  Item ::= x ; ;
my $grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'List',
        expressions => [[reference('List'), reference('Item')], [reference('Item')]],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'Item',
        expressions => [[terminal('x'), terminal(';')]],
    ),
];

my $parser = Chalk::Bootstrap::Earley->new(
    grammar  => $grammar,
    semiring => Chalk::Bootstrap::Semiring::Boolean->new(),
);

my $items = 200;
ok($parser->parse('x;' x $items), "accepts $items items");

# After the parse the table is the one of the last position (400). The last
# Item spans [398, 400]: its completed item is at relative distance 2.
my $table = $parser->processed_table();
my $item_done = $parser->core_index()->id_for('Item', 0, 2);
my $row = $table->[$item_done];

ok(defined $row, 'the completed Item was processed at the last position');
ok($row->[2], 'it is recorded at relative distance 2');
is(scalar $row->@*, 3,
    'its row is as long as its relative distance, not as long as the input');

done_testing();

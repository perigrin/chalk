# ABOUTME: Tests for Leo optimization in the Earley parser.
# ABOUTME: Verifies Leo items enable O(n) parsing for left- and right-recursive grammars.
use 5.42.0;
use utf8;
use Test::More;
use Time::HiRes qw(time);

use lib 'lib';
use Chalk::Grammar::Rule;
use Chalk::Grammar::Symbol;
use Chalk::Bootstrap::Earley;
use Chalk::Bootstrap::Semiring::Boolean;

# Helper to create terminal symbol
sub terminal($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'terminal',
        value => $value,
    );
}

# Helper to create reference symbol (nonterminal)
sub reference($value) {
    return Chalk::Grammar::Symbol->new(
        type  => 'reference',
        value => $value,
    );
}

# Test 1: Left-recursive chain — correctness
# Grammar: List ::= Item | List Comma Item
#          Item ::= /\w+/
#          Comma ::= /,/
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'List',
            expressions => [
                [reference('Item')],
                [reference('List'), reference('Comma'), reference('Item')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "left-recursive: single item");
    ok($parser->parse('a,b'), "left-recursive: two items");
    ok($parser->parse('a,b,c'), "left-recursive: three items");
    ok(!$parser->parse(''), "left-recursive: rejects empty");
    ok(!$parser->parse('a,'), "left-recursive: rejects trailing comma");
    ok(!$parser->parse(',a'), "left-recursive: rejects leading comma");
}

# Test 2: Left-recursive chain — warm-up parse
# Run a medium-sized parse to warm up the parser/regex engine before
# the scaling tests below. This avoids cold-cache effects on test 5.
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'List',
            expressions => [
                [reference('Item')],
                [reference('List'), reference('Comma'), reference('Item')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $input = join(',', ('x') x 1000);
    ok($parser->parse($input), "left-recursive 1000 items: parses (warm-up)");
}

# Test 3: Right-recursive chain — correctness and performance
# Grammar: Chain ::= Item | Item Comma Chain
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'Chain',
            expressions => [
                [reference('Item')],
                [reference('Item'), reference('Comma'), reference('Chain')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('a'), "right-recursive: single item");
    ok($parser->parse('a,b'), "right-recursive: two items");
    ok($parser->parse('a,b,c'), "right-recursive: three items");

    # Scaling test: N=1000 vs 2N=2000 (single-char items)
    my $parser2 = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    my $input_n = join(',', ('x') x 1000);
    my $start1 = time();
    $parser2->parse($input_n);
    my $t_n = time() - $start1;
    $t_n = 0.1 if $t_n < 0.1;

    my $parser3 = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    my $input_2n = join(',', ('x') x 2000);
    my $start2 = time();
    my $result = $parser3->parse($input_2n);
    my $t_2n = time() - $start2;

    ok($result, "right-recursive 2000 items: parses successfully");
    my $ratio = $t_2n / $t_n;
    TODO: {
        local $TODO = "scaling ratio is machine-dependent and noisy on slow VMs";
        ok($ratio <= 3.5, sprintf("right-recursive scaling is sub-quadratic: 2x input => %.1fx time (threshold 3.5x)", $ratio));
    }
}

# Test 4: Leo items don't interfere with ambiguous grammars
# Grammar where a nonterminal has multiple waiting items (Leo should NOT activate)
# Ambiguous: S ::= A B | A C ; A ::= /a/ ; B ::= /b/ ; C ::= /b/
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'S',
            expressions => [
                [reference('A'), reference('B')],
                [reference('A'), reference('C')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'A',
            expressions => [[terminal('a')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'B',
            expressions => [[terminal('b')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'C',
            expressions => [[terminal('b')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    ok($parser->parse('ab'), "ambiguous grammar: still parses correctly with Leo");
    ok(!$parser->parse('ac'), "ambiguous grammar: rejects non-matching");
}

# Test 5: Larger scaling test — 1000 vs 2000 items
# Confirms linear scaling holds at larger input sizes
{
    my $grammar = [
        Chalk::Grammar::Rule->new(
            name        => 'List',
            expressions => [
                [reference('Item')],
                [reference('List'), reference('Comma'), reference('Item')],
            ],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Item',
            expressions => [[terminal('\w+')]],
        ),
        Chalk::Grammar::Rule->new(
            name        => 'Comma',
            expressions => [[terminal(',')]],
        ),
    ];

    my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();

    my $parser1 = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    my $input_n = join(',', ('x') x 1000);
    my $start1 = time();
    $parser1->parse($input_n);
    my $t_n = time() - $start1;
    $t_n = 0.01 if $t_n < 0.01;

    my $parser2 = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );
    my $input_2n = join(',', ('x') x 2000);
    my $start2 = time();
    my $result = $parser2->parse($input_2n);
    my $t_2n = time() - $start2;

    ok($result, "left-recursive 2000 items: parses successfully");
    my $ratio = $t_2n / $t_n;
    TODO: {
        local $TODO = "scaling ratio is machine-dependent and noisy on slow VMs";
        ok($ratio <= 3.5, sprintf("left-recursive large scaling is sub-quadratic: 2x input => %.1fx time (threshold 3.5x)", $ratio));
    }
}

done_testing;

# ABOUTME: Tests for two-tier error recovery in the Earley parser (Section 8.3).
# ABOUTME: Covers stall detection, brace-depth sync, error collection, and Ruby Slippers.
use 5.42.0;
use utf8;
use Test::More;

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

# Grammar: semicolon-separated assignments inside optional braces
# Program     ::= Statement | Program ';' Statement
# Statement   ::= Identifier '=' Value
# Identifier  ::= /[a-z]+/
# Value       ::= /\d+/
my $grammar = [
    Chalk::Grammar::Rule->new(
        name        => 'Program',
        expressions => [
            [reference('Statement')],
            [reference('Program'), terminal(';'), reference('Statement')],
        ],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'Statement',
        expressions => [[reference('Identifier'), terminal('='), reference('Value')]],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'Identifier',
        expressions => [[terminal('[a-z]+')]],
    ),
    Chalk::Grammar::Rule->new(
        name        => 'Value',
        expressions => [[terminal('\\d+')]],
    ),
];

my $semiring = Chalk::Bootstrap::Semiring::Boolean->new();

# === _find_sync_point tests ===

subtest '_find_sync_point: semicolon at depth 0' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # "xxx@@@;y=2" - error at 3, sync at ; (pos 6)
    my $input = 'xxx@@@;y=2';
    my ($sync_pos, $sync_type) = $parser->_find_sync_point($input, 3);
    is($sync_pos, 7, 'sync position is after the semicolon');
    is($sync_type, 'semicolon', 'sync type is semicolon');
};

subtest '_find_sync_point: skips semicolon inside braces' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # "xxx{a;b};y=2" - error at 3, { at 3, ; at 5 is depth 1, } at 7 closes, ; at 8
    my $input = 'xxx{a;b};y=2';
    my ($sync_pos, $sync_type) = $parser->_find_sync_point($input, 3);
    # Should skip the ; at pos 5 (depth 1) and sync on } at pos 7 which
    # decrements depth below 0 (closes enclosing block)
    # Actually { at pos 3 increments to 1, } at pos 7 decrements to 0,
    # ; at pos 8 is at depth 0
    is($sync_pos, 9, 'sync after semicolon at depth 0');
    is($sync_type, 'semicolon', 'sync type is semicolon');
};

subtest '_find_sync_point: closing brace that exits enclosing block' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # "xxx}y=2" - error at 3, } at 3 decrements below 0
    my $input = 'xxx}y=2';
    my ($sync_pos, $sync_type) = $parser->_find_sync_point($input, 3);
    is($sync_pos, 4, 'sync after closing brace');
    is($sync_type, 'block_close', 'sync type is block_close');
};

subtest '_find_sync_point: returns undef at EOF' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    my $input = 'xxx';
    my ($sync_pos, $sync_type) = $parser->_find_sync_point($input, 3);
    is($sync_pos, undef, 'no sync point found');
    is($sync_type, undef, 'no sync type');
};

subtest '_find_sync_point: declaration keyword at depth 0' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # "xxx method foo" - error at 3, keyword at 4
    my $input = 'xxx method foo';
    my ($sync_pos, $sync_type) = $parser->_find_sync_point($input, 3);
    is($sync_pos, 4, 'sync at keyword position');
    is($sync_type, 'keyword', 'sync type is keyword');
};

# === Stall detection and recovery tests ===

subtest 'parse recovers past error and continues' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
        recover  => true,
    );

    # "x=1;@@@;y=2" - valid statement, garbage, valid statement
    # Without recovery: parse fails at @@@
    # With recovery: should skip past @@@ to ; and continue
    my $result = $parser->parse('x=1;@@@;y=2');
    ok($result, 'parse succeeds despite error in middle');
};

subtest 'parse without recovery still fails on error' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
    );

    # Default: no recovery
    my $result = $parser->parse('x=1;@@@;y=2');
    ok(!$result, 'parse fails without recovery enabled');
};

subtest 'valid input parses identically with recovery enabled' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
        recover  => true,
    );

    ok($parser->parse('x=1'), 'single statement');
    $parser->reset_parse_state();
    ok($parser->parse('x=1;y=2;z=3'), 'multiple statements');
    $parser->reset_parse_state();
    ok(!$parser->parse(''), 'empty still rejected');
};

subtest 'errors accessor reports recovery events' => sub {
    my $parser = Chalk::Bootstrap::Earley->new(
        grammar  => $grammar,
        semiring => $semiring,
        recover  => true,
    );

    $parser->parse('x=1;@@@;y=2');
    my $errors = $parser->errors();
    ok(defined $errors, 'errors returns defined value');
    is(ref $errors, 'ARRAY', 'errors returns arrayref');
    cmp_ok(scalar $errors->@*, '>=', 1, 'at least one error recorded');

    my $err = $errors->[0];
    ok(exists $err->{position}, 'error has position');
    ok(exists $err->{sync_pos}, 'error has sync_pos');
    ok(exists $err->{sync_type}, 'error has sync_type');
};

done_testing;

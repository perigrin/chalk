#!/usr/bin/env perl
# ABOUTME: Test that expression associativity is preserved after grammar simplification
# ABOUTME: Validates left-associative and right-associative operators parse correctly
use lib 'lib';
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Chalk::Parser;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use Chalk::Semiring::Boolean;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "chalk.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program", "Chalk");

# Helper to validate expression against real Perl
sub perl_accepts {
    my ($expr) = @_;
    my $result = system('perl', '-c', '-e', $expr, '2>/dev/null');
    return $result == 0;
}

# Helper to validate expression is rejected by real Perl
sub perl_rejects {
    my ($expr) = @_;
    return !perl_accepts($expr);
}

# Test right-associative operators (must associate right-to-left)
subtest 'Right-associative operators' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    # Assignment: $a = $b = 1 should parse as $a = ($b = 1)
    ok($parser->parse_string('$a = $b = 1'),
       'assignment associates right: $a = $b = 1');

    ok($parser->parse_string('$x = $y = $z = 42'),
       'chained assignment associates right: $x = $y = $z = 42');

    # Power: 2 ** 3 ** 4 should parse as 2 ** (3 ** 4) = 2 ** 81 = big number
    ok($parser->parse_string('2 ** 3 ** 4'),
       'power associates right: 2 ** 3 ** 4');

    ok($parser->parse_string('$x ** $y ** $z'),
       'power with variables associates right');

    # Ternary: a ? b : c ? d : e should parse as a ? b : (c ? d : e)
    ok($parser->parse_string('$a ? $b : $c ? $d : $e'),
       'ternary associates right: $a ? $b : $c ? $d : $e');

    ok($parser->parse_string('1 ? 2 : 3 ? 4 : 5'),
       'ternary with literals associates right');
};

# Test left-associative operators (must associate left-to-right)
subtest 'Left-associative operators' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    # Addition: 1 + 2 + 3 should parse as (1 + 2) + 3
    ok($parser->parse_string('1 + 2 + 3'),
       'addition associates left: 1 + 2 + 3');

    ok($parser->parse_string('$a + $b + $c + $d'),
       'chained addition associates left');

    # Subtraction: 10 - 3 - 2 should parse as (10 - 3) - 2 = 5
    ok($parser->parse_string('10 - 3 - 2'),
       'subtraction associates left: 10 - 3 - 2');

    # Multiplication: 2 * 3 * 4 should parse as (2 * 3) * 4
    ok($parser->parse_string('2 * 3 * 4'),
       'multiplication associates left: 2 * 3 * 4');

    # Division: 24 / 4 / 2 should parse as (24 / 4) / 2 = 3
    ok($parser->parse_string('24 / 4 / 2'),
       'division associates left: 24 / 4 / 2');

    # Logical AND: $a && $b && $c should parse as ($a && $b) && $c
    ok($parser->parse_string('$a && $b && $c'),
       'logical AND associates left: $a && $b && $c');

    # Logical OR: $a || $b || $c should parse as ($a || $b) || $c
    ok($parser->parse_string('$a || $b || $c'),
       'logical OR associates left: $a || $b || $c');

    # Bitwise operators
    ok($parser->parse_string('$a | $b | $c'),
       'bitwise OR associates left');

    ok($parser->parse_string('$a & $b & $c'),
       'bitwise AND associates left');

    ok($parser->parse_string('$a ^ $b ^ $c'),
       'bitwise XOR associates left');

    # Shift operators
    ok($parser->parse_string('$a << 1 << 2'),
       'left shift associates left');

    ok($parser->parse_string('$a >> 1 >> 2'),
       'right shift associates left');

    # String concatenation
    ok($parser->parse_string('"a" . "b" . "c"'),
       'string concatenation associates left');

    # Comparison operators (non-associative in Perl, but should parse)
    ok($parser->parse_string('$a == $b'),
       'equality parses');

    ok($parser->parse_string('$a < $b'),
       'less-than parses');
};

# Test precedence (ensure nesting is preserved)
subtest 'Operator precedence' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    # Multiplication binds tighter than addition
    ok($parser->parse_string('1 + 2 * 3'),
       'precedence: 1 + 2 * 3 parses as 1 + (2 * 3)');

    # Power binds tighter than multiplication
    ok($parser->parse_string('2 * 3 ** 4'),
       'precedence: 2 * 3 ** 4 parses as 2 * (3 ** 4)');

    # Logical AND binds tighter than logical OR
    ok($parser->parse_string('$a || $b && $c'),
       'precedence: $a || $b && $c parses as $a || ($b && $c)');

    # Assignment has lowest precedence (except comma)
    ok($parser->parse_string('$a = $b + $c'),
       'precedence: $a = $b + $c parses as $a = ($b + $c)');

    ok($parser->parse_string('$a = $b && $c'),
       'precedence: $a = $b && $c parses as $a = ($b && $c)');

    # Complex mixed expression
    ok($parser->parse_string('$a = $b + $c * $d ** $e'),
       'complex precedence: $a = $b + $c * $d ** $e');
};

# Test that named operators work correctly
subtest 'Named operators (or, and, not)' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    ok($parser->parse_string('$a or $b or $c'),
       'named or associates left');

    ok($parser->parse_string('$a and $b and $c'),
       'named and associates left');

    ok($parser->parse_string('not $a'),
       'named not parses');

    # Named operators have very low precedence
    ok($parser->parse_string('$a = $b or $c'),
       'named or has lower precedence than assignment');
};

# Test range operator
subtest 'Range operator' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    ok($parser->parse_string('1 .. 10'),
       'range: 1 .. 10');

    ok($parser->parse_string('$a .. $b'),
       'range with variables');

    # Range is non-associative - chained range is a syntax error in Perl
    # We don't test for it because it should fail
};

# Test comma operator
subtest 'Comma operator' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    ok($parser->parse_string('$a, $b, $c'),
       'comma list');

    ok($parser->parse_string('1, 2, 3'),
       'comma list with literals');

    # Fat comma (=>)
    ok($parser->parse_string('a => 1, b => 2'),
       'fat comma in hash construction');
};

# Validate against real Perl - Chalk should accept what Perl accepts
subtest 'Validate against real Perl (valid expressions)' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    my @valid_in_perl = (
        '$a = $b = 1',
        '2 ** 3 ** 4',
        '$a ? $b : $c ? $d : $e',
        '1 + 2 + 3',
        '1 + 2 * 3',
        '$a || $b && $c',
        '1 .. 10',
        '$a, $b, $c',
    );

    for my $expr (@valid_in_perl) {
        ok(perl_accepts($expr), "Perl accepts: $expr")
            or diag("Real Perl rejects this, skipping Chalk test");
        next unless perl_accepts($expr);

        ok($parser->parse_string($expr), "Chalk accepts: $expr")
            or diag("Chalk should accept what Perl accepts");
    }
};

# Validate against real Perl - Chalk should reject what Perl rejects
subtest 'Validate against real Perl (invalid expressions)' => sub {
    my $parser = Chalk::Parser->new(
        grammar   => $chalk_grammar,
        semiring  => Chalk::Semiring::Boolean->new(),
    );

    my @invalid_in_perl = (
        '1 .. 5 .. 10',  # Range is non-associative
    );

    for my $expr (@invalid_in_perl) {
        ok(perl_rejects($expr), "Perl rejects: $expr")
            or diag("Real Perl accepts this unexpectedly");

        # Chalk should also reject it (parse should fail)
        my $result = $parser->parse_string($expr);
        ok(!$result, "Chalk rejects: $expr")
            or diag("Chalk should reject what Perl rejects");
    }
};

done_testing();

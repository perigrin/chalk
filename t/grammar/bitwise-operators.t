# ABOUTME: Tests for bitwise operator parsing in Chalk grammar
# ABOUTME: Verifies &, |, ^, ~, <<, >> operators parse correctly
use 5.42.0;
use Test::More;
use lib 'lib';
use utf8;

use Chalk::Grammar;
use Chalk::Grammar::BNF;
use Chalk::Semiring::ChalkSyntax;
use Chalk::Parser;

# Load grammar
my $grammar_file = 'grammar/chalk.bnf';
open my $fh, '<:utf8', $grammar_file or die "Cannot open $grammar_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program", "Chalk");
my $semiring = Chalk::Semiring::ChalkSyntax->new(grammar => $grammar);

sub parses_ok {
    my ($code, $name) = @_;
    my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
    my $result = $parser->parse_string($code);
    ok($result, $name);
}

# Test bitwise AND
parses_ok('$a & $b;', 'Bitwise AND: $a & $b');
parses_ok('$x & 0xFF;', 'Bitwise AND with hex literal');
parses_ok('1 & 2 & 3;', 'Chained bitwise AND');

# Test bitwise OR
parses_ok('$a | $b;', 'Bitwise OR: $a | $b');
parses_ok('$x | 0x0F;', 'Bitwise OR with hex literal');

# Test bitwise XOR
parses_ok('$a ^ $b;', 'Bitwise XOR: $a ^ $b');
parses_ok('$x ^ 1;', 'Bitwise XOR with constant');

# Test bitwise NOT (unary ~)
parses_ok('~$a;', 'Bitwise NOT: ~$a');
parses_ok('~0;', 'Bitwise NOT of zero');
parses_ok('~~$x;', 'Double bitwise NOT');

# Test left shift
parses_ok('$a << $b;', 'Left shift: $a << $b');
parses_ok('1 << 8;', 'Left shift constant');
parses_ok('$x << 2;', 'Left shift by 2');

# Test right shift
parses_ok('$a >> $b;', 'Right shift: $a >> $b');
parses_ok('256 >> 4;', 'Right shift constant');
parses_ok('$x >> 1;', 'Right shift by 1');

# Test mixed expressions
parses_ok('($a & $b) | $c;', 'Mixed AND/OR with parens');
parses_ok('$x << 2 | $y;', 'Shift with OR');
parses_ok('~$a & $b;', 'NOT with AND');

# Test with arithmetic
parses_ok('$a + $b & $c;', 'Addition and AND');
parses_ok('1 << ($n - 1);', 'Shift with arithmetic in parens');

done_testing();

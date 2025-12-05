#!/usr/bin/env perl
# ABOUTME: Test parser support for float arithmetic and type widening
# ABOUTME: Validates float literal parsing and automatic int-to-float conversion

use lib 'lib';
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use File::Spec;

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkSyntax;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::AddF;
use Chalk::IR::Node::SubF;
use Chalk::IR::Node::MulF;
use Chalk::IR::Node::DivF;
use Chalk::IR::Node::ToFloat;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Expression');

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::ChalkSyntax->new(),
);

subtest 'Float literal parsing' => sub {
    my $result = $parser->parse_string('3.14');
    ok $result, 'Parsed float literal 3.14';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Result is Constant node';
    is $result->value, 3.14, 'Value is 3.14';
};

subtest 'Float addition: both floats' => sub {
    my $result = $parser->parse_string('1.5 + 2.5');
    ok $result, 'Parsed 1.5 + 2.5';
    ok $result->isa('Chalk::IR::Node::AddF'), 'Result is AddF node';

    # Should be optimized to constant 4.0
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded to Constant';
    is $result->value, 4.0, 'Result is 4.0';
};

subtest 'Float subtraction: both floats' => sub {
    my $result = $parser->parse_string('5.5 - 2.5');
    ok $result, 'Parsed 5.5 - 2.5';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    is $result->value, 3.0, 'Result is 3.0';
};

subtest 'Float multiplication: both floats' => sub {
    my $result = $parser->parse_string('2.5 * 4.0');
    ok $result, 'Parsed 2.5 * 4.0';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    is $result->value, 10.0, 'Result is 10.0';
};

subtest 'Float division: both floats' => sub {
    my $result = $parser->parse_string('10.0 / 4.0');
    ok $result, 'Parsed 10.0 / 4.0';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    is $result->value, 2.5, 'Result is 2.5';
};

subtest 'Type widening: int + float' => sub {
    my $result = $parser->parse_string('2 + 3.14');
    ok $result, 'Parsed 2 + 3.14';

    # Should be AddF with left operand wrapped in ToFloat
    # After constant folding, should be 5.14
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    ok abs($result->value - 5.14) < 0.001, 'Result is approximately 5.14';
};

subtest 'Type widening: float + int' => sub {
    my $result = $parser->parse_string('3.14 + 2');
    ok $result, 'Parsed 3.14 + 2';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    ok abs($result->value - 5.14) < 0.001, 'Result is approximately 5.14';
};

subtest 'Type widening: int * float' => sub {
    my $result = $parser->parse_string('5 * 2.0');
    ok $result, 'Parsed 5 * 2.0';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    is $result->value, 10.0, 'Result is 10.0';
};

subtest 'Type widening: float / int' => sub {
    my $result = $parser->parse_string('10.0 / 4');
    ok $result, 'Parsed 10.0 / 4';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    is $result->value, 2.5, 'Result is 2.5 (float division)';
};

subtest 'Integer division remains integer' => sub {
    my $result = $parser->parse_string('10 / 4');
    ok $result, 'Parsed 10 / 4';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Result is Constant (integer)';
    is $result->value, 2, 'Result is 2 (integer division)';
};

subtest 'Complex mixed expression' => sub {
    # (1 + 2.5) * 3 should be:
    # 1. AddF(ToFloat(1), 2.5) → Constant(3.5)
    # 2. MulF(3.5, ToFloat(3)) → Constant(10.5)
    my $result = $parser->parse_string('(1 + 2.5) * 3');
    ok $result, 'Parsed (1 + 2.5) * 3';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    is $result->value, 10.5, 'Result is 10.5';
};

subtest 'Newton\'s method expression' => sub {
    # (guess + 2.0/guess) / 2.0 with guess as variable would be complex
    # For now, test constant version: (1.5 + 2.0/1.5) / 2.0
    my $result = $parser->parse_string('(1.5 + 2.0/1.5) / 2.0');
    ok $result, 'Parsed Newton iteration formula';
    ok $result->isa('Chalk::IR::Node::Constant'), 'Constant folded';
    ok abs($result->value - 1.41666666666) < 0.00001,
        'Result ≈ 1.4167';
};

done_testing();

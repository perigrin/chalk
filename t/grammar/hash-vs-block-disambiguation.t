# ABOUTME: Tests that {...} is correctly disambiguated as hash subscript vs hashref/block
# ABOUTME: Critical regression test for the R variant context system in the grammar
use 5.42.0;
use Test2::V0;
use Chalk::Parser;
use Chalk::Grammar::BNF;
use FindBin qw($RealBin);
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");


my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    preprocess => ['Chalk::Preprocessor::Heredoc']
);

# These tests verify that the parser correctly distinguishes between:
# 1. Hash subscripts: $foo{key} in operator context
# 2. Hash refs: { key => value } as values
# 3. Blocks: { statements } as code blocks

subtest 'Hash subscript in arithmetic context' => sub {
    # The critical cases from lex.t that were failing
    ok($parser->parse_string('$foo{1} / 1;'),
       'hash subscript followed by division');

    ok($parser->parse_string('$foo{$bar} + 2;'),
       'hash subscript with variable key in addition');

    ok($parser->parse_string('$h{x} * 3;'),
       'hash subscript in multiplication');

    ok($parser->parse_string('$hash{key} - 1;'),
       'hash subscript in subtraction');
};

subtest 'Hash subscript vs hashref assignment' => sub {
    ok($parser->parse_string('$foo{$bar} = BAZ;'),
       'assign to hash subscript');

    ok($parser->parse_string('$x = { a => 1 };'),
       'assign hashref to variable');

    ok($parser->parse_string('$hash{$key} = { nested => 1 };'),
       'assign hashref to hash subscript');
};

subtest 'Hash subscript in interpolation and printing' => sub {
    ok($parser->parse_string('print "$foo{$bar}";'),
       'hash subscript in string interpolation');

    ok($parser->parse_string('print $h{key};'),
       'print hash subscript value');

    ok($parser->parse_string('say $data{field};'),
       'say hash subscript value');
};

subtest 'Hash subscript with operators requiring NonBrace context' => sub {
    # These specifically test the R (NonBrace) variant chain
    ok($parser->parse_string('$a{x} / $b{y};'),
       'division between two hash subscripts');

    ok($parser->parse_string('$h{a} + $h{b} * $h{c};'),
       'complex arithmetic with multiple hash subscripts');

    ok($parser->parse_string('$result = $data{x} / $data{y} + 1;'),
       'hash subscripts in compound expression');
};

subtest 'Hashref construction (should still work)' => sub {
    ok($parser->parse_string('my $ref = { key => "value" };'),
       'simple hashref assignment');

    ok($parser->parse_string('foo({ arg => 1 });'),
       'hashref as function argument');

    ok($parser->parse_string('return { status => "ok" };'),
       'hashref in return statement');
};

subtest 'Array subscript (similar disambiguation issue)' => sub {
    ok($parser->parse_string('$arr[0] / 2;'),
       'array subscript in division');

    ok($parser->parse_string('$data[1] + $data[2];'),
       'array subscripts in addition');
};

subtest 'Real examples from lex.t that failed' => sub {
    # Line 28 from lex.t
    ok($parser->parse_string(q{eval '$foo{1} / 1;';}),
       'eval with hash subscript and division (line 28)');

    # Line 94-97 pattern from lex.t
    ok($parser->parse_string(q{$foo{$bar} = BAZ;}),
       'hash assignment pattern (line 94)');

    ok($parser->parse_string(q{print "$foo{$bar}" eq "BAZ" ? "ok\n" : "not ok\n";}),
       'hash interpolation in conditional (line 95)');
};

done_testing();

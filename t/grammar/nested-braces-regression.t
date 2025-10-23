# ABOUTME: Minimal test case for lex.t position 13215 regression
# ABOUTME: Tests parsing of complex nested brace expressions
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

# The actual failing expression from line 540
my $failing_expr_540 = 'eval q|qq{@{[{}}*sub{]]}}}=u|;';

# Expression from line 551 (originally thought to be the failure)
my $failing_expr_551 = 'eval (\'qq{@{[0}*sub{]]}}}=sub{0\' . "\c[");';

subtest 'Line 540: eval q|qq{@{[{}}*sub{]]}}}=u|;' => sub {
    ok($parser->parse_string($failing_expr_540),
       'should parse line 540');
};

subtest 'Line 551: eval (\'qq{@{[0}*sub{]]}}}=sub{0\' . "\c[");' => sub {
    ok($parser->parse_string($failing_expr_551),
       'should parse line 551');
};

# Break it down into simpler components to isolate the issue
subtest 'Simplified nested brace cases' => sub {
    ok($parser->parse_string(q{qq{@{[0]}}}),
       'should parse: qq{@{[0]}}');

    ok($parser->parse_string(q{qq{@{[0}*sub{]]}}}),
       'should parse: qq{@{[0}*sub{]]}}');

    ok($parser->parse_string(q{eval('qq{test}')}),
       'should parse: eval(\'qq{test}\')');
};

done_testing();

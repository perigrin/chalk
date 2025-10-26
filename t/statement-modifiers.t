# ABOUTME: Test for issue #107 - statement modifiers (postfix if/unless/while/until/for)
# ABOUTME: Verifies that the parser can handle statement modifiers like 'print $x if $y'
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test cases for conditional statement modifiers (if/unless)
# NOTE: Loop modifiers (while/until/for) require grammar additions
my @test_cases = (
    # Basic conditional modifiers
    { code => 'print("yes") if $x;', desc => 'print if (basic)' },
    { code => 'print("no") unless $flag;', desc => 'print unless (basic)' },
    { code => 'die("error") if $error;', desc => 'die if (error handling)' },

    # Assignment with modifiers
    { code => '$count = $count + 1 if $condition;', desc => 'assignment if' },
    { code => '$x = 5 unless $x;', desc => 'assignment unless' },

    # Complex expressions
    { code => '$result = $a + $b if $a > 0;', desc => 'expression if with comparison' },
    { code => 'print("debug") if $debug && $verbose;', desc => 'if with logical and' },

    # Loop control with conditional modifiers
    { code => 'next if $skip;', desc => 'next if (loop control)' },
    { code => 'last unless $continue;', desc => 'last unless (loop exit)' },
);

plan tests => scalar(@test_cases);

for my $test (@test_cases) {
    my $result = $parser->parse_string($test->{code});

    ok($result, $test->{desc}) or diag("Failed to parse: $test->{code}");
}

done_testing();

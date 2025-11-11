# ABOUTME: Tests for the range operator (..) in list context
# ABOUTME: Validates numeric and string ranges, edge cases
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
my $bnf_file = File::Spec->catfile($RealBin, '..', '..', 'grammar', 'chalk.bnf');
open my $grammar_fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program');

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test 1: Basic numeric range
my $numeric_range = <<'PERL';
@numbers = (1..10);
PERL

my $result = $parser->parse_string($numeric_range);
ok($result, 'basic numeric range (1..10) parses successfully');

# Test 2: String range
my $string_range = <<'PERL';
@letters = ('a'..'z');
PERL

$result = $parser->parse_string($string_range);
ok($result, 'string range (a..z) parses successfully');

# Test 3: Dynamic range with variables
my $dynamic_range = <<'PERL';
$start = 1;
$end = 5;
@range = ($start..$end);
PERL

$result = $parser->parse_string($dynamic_range);
ok($result, 'dynamic range with variables parses successfully');

# Test 4: Empty range (reverse)
my $empty_range = <<'PERL';
@empty = (10..1);
PERL

$result = $parser->parse_string($empty_range);
ok($result, 'empty/reverse range (10..1) parses successfully');

# Test 5: Single element range
my $single_range = <<'PERL';
@single = (5..5);
PERL

$result = $parser->parse_string($single_range);
ok($result, 'single element range (5..5) parses successfully');

# Test 6: Range in list context
my $list_context = <<'PERL';
@list = (0, 1..5, 10);
PERL

$result = $parser->parse_string($list_context);
ok($result, 'range in list context with other elements parses successfully');

# Test 7: Negative numbers
my $negative_range = <<'PERL';
@neg = (-5..5);
PERL

$result = $parser->parse_string($negative_range);
ok($result, 'range with negative numbers (-5..5) parses successfully');

done_testing();

#!/usr/bin/env perl
# ABOUTME: Test that true/false parse correctly as literals in all contexts
# ABOUTME: Regression test for bareword literal parsing (Perl 5.36+ builtins)
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use Chalk::Grammar::BNF;

# Load grammar
open my $grammar_fh, "<:utf8", "$RealBin/../../grammar/chalk.bnf" or die $!;
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;

my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program", "Chalk");

sub parses_ok {
    my ($code, $description) = @_;
    my $parser = Chalk::Parser->new(grammar => $chalk_grammar);
    my $result = $parser->parse_string($code);
    ok($result, $description) or diag("Failed to parse: $code");
}

# Basic assignment
parses_ok('my $x = true;', 'true in assignment');
parses_ok('my $y = false;', 'false in assignment');

# Return statements
parses_ok('method foo() { return true; }', 'return true from method');
parses_ok('method bar() { return false; }', 'return false from method');

# Named arguments (fat-comma)
parses_ok('Chalk::IR::Type::Bool->constant(true)', 'true as named argument without quotes');
parses_ok('Chalk::IR::Type::Bool->constant(false)', 'false as named argument without quotes');
parses_ok('my $x = Foo->new(enabled => true);', 'true as hash value with fat-comma');
parses_ok('my $y = Bar->new(disabled => false);', 'false as hash value with fat-comma');

# Positional parameters (the user's specific request)
parses_ok('$object->method(false)', 'false as single positional parameter');
parses_ok('$object->method(true)', 'true as single positional parameter');
parses_ok('$object->foo(true, false)', 'true and false as positional parameters');
parses_ok('$object->bar(false, 1, "string")', 'false mixed with other types');
parses_ok('function(true)', 'true in function call');
parses_ok('function(false)', 'false in function call');
parses_ok('process(true, false, true)', 'multiple booleans as parameters');
parses_ok('my $x = calculate(false, 42);', 'false with number parameter');

# Hash construction
parses_ok('my %hash = (enabled => true, disabled => false);', 'true/false in hash literal');
parses_ok('use overload "bool" => sub { return true; };', 'true in overload definition');

# Conditionals
parses_ok('if (true) { }', 'true in if condition');
parses_ok('unless (false) { }', 'false in unless condition');

# Boolean expressions
parses_ok('my $x = true && false;', 'true and false with &&');
parses_ok('my $y = true || false;', 'true or false with ||');
parses_ok('my $z = not true;', 'not true');

# Standalone
parses_ok('true;', 'true as statement');
parses_ok('false;', 'false as statement');

# List context
parses_ok('my ($a, $b) = (true, false);', 'true/false in list assignment');

# Method chaining
parses_ok('my $x = Some::Class->new(active => true)->process();', 'true in chained method call');

done_testing;

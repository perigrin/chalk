#!/usr/bin/env perl
# ABOUTME: Minimal test to debug issue #195 with disambiguation logging
# ABOUTME: Parses the failing test case and shows disambiguation decisions

use 5.42.0;
use experimental qw(class);
use lib 'lib';

use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Semiring::Semantic;
use Chalk::IR::Builder;
use Chalk::IR::Node::Scope;

# Enable debug output
$ENV{DEBUG_STMTLIST_DISAMBIG} = 1;

# Load grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die $!;
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Failing test case
my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';

# Parse
my $builder = Chalk::IR::Builder->new();
my $scope = Chalk::IR::Node::Scope->new();
my $semiring = Chalk::Semiring::Semantic->new(
    grammar => $grammar,
    env => { ir_builder => $builder, scope => $scope }
);

my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
print "Parsing: $code\n\n";
my $result = $parser->parse_string($code);

print "\nParse " . ($result ? "succeeded" : "failed") . "\n";

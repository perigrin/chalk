#!/usr/bin/env perl
# ABOUTME: Debug script to trace why ComparisonOp doesn't return IR nodes
# ABOUTME: Tests parsing of comparison expressions to see what's returned

use 5.42.0;
use lib 'lib';
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Parser;
use Chalk::Semiring::Semantic;
use Chalk::ParseForest;
use Chalk::IR::Node::Scope;
use Chalk::IR::Node::Constant;
use Data::Dumper;

# Load grammar from BNF
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($content, 'Expression', 'Chalk');

my %env = (
    patterns => {},
    grammar_name => 'Chalk'
);

# Add a variable to scope so $x resolves
$env{scope} = Chalk::IR::Node::Scope->new();
my $x_const = Chalk::IR::Node::Constant->new(type => 'Int', value => 10);
$env{scope}->declare('$x', $x_const);

my %shared_context = (
    forest => Chalk::ParseForest->new()
);

my $semiring = Chalk::Semiring::Semantic->new(
    env => \%env,
    grammar => $grammar,
    shared_context => \%shared_context
);

my $parser = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $semiring
);

# Simple comparison expression
my $code = '$x > 5';

say "=== Parsing: $code ===";
say "";

my $result = $parser->parse_string($code);

if ($result) {
    my $ctx = $result->context;
    my $focus = $ctx->focus;

    say "Result type: " . (ref($focus) || 'scalar');
    say "Result value: " . (defined($focus) ? $focus : 'undef');

    if (ref($focus) && $focus->can('id')) {
        say "Has id() method: YES";
        say "ID: " . $focus->id;
        say "Op: " . ($focus->can('op') ? $focus->op : 'N/A');
    } else {
        say "Has id() method: NO";
        if (ref($focus) eq 'HASH') {
            say "Hash contents: " . Dumper($focus);
        }
    }
} else {
    say "Parse failed!";
}

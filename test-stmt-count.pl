#!/usr/bin/env perl
use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::IR::Builder;

# Load grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die $!;
my $bnf = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf, 'Program', 'Chalk');

# Parse test 53 code
my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';
my $builder = Chalk::IR::Builder->new();
my $scope = Chalk::IR::Node::Scope->new();
my $semiring = Chalk::Semiring::Semantic->new(
    grammar => $grammar,
    env => { ir_builder => $builder, scope => $scope }
);

my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
my $result = $parser->parse_string($code);

if ($result && $result->can('context')) {
    my $ctx = $result->context;
    if ($ctx->can('focus')) {
        my $program = $ctx->focus;
        if ($program && $program->can('statements')) {
            my @stmts = @{$program->statements // []};
            print "Statement count: " . scalar(@stmts) . "\n";
        } else {
            print "No statements method\n";
        }
    } else {
        print "No focus\n";
    }
} else {
    print "No result or context\n";
}

#!/usr/bin/env perl
# ABOUTME: Count statements in each parse alternative for issue #195
# ABOUTME: Shows how many Statement nodes each top-level StatementList alternative contains

use 5.42.0;
use experimental qw(class);
use lib 'lib';

use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Semiring::Semantic;
use Chalk::IR::Builder;
use Chalk::IR::Node::Scope;

# Load Chalk grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Test case from issue #195
my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';

# Parse with Semantic semiring + ir_builder to get statement arrays
my $builder = Chalk::IR::Builder->new();
my $scope = Chalk::IR::Node::Scope->new();

my $semiring = Chalk::Semiring::Semantic->new(
    grammar => $grammar,
    env => { ir_builder => $builder, scope => $scope }
);

# Enable debug mode
$ENV{DEBUG_SEMANTIC_ADD} = 1;

my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $semiring);
my $result = $parser->parse_string($code);

if (!$result) {
    die "Parse failed\n";
}

# Get the Program result
my $ctx = $result->context;
my $focus = $ctx->focus;

print "Program focus: " . (ref($focus) || 'scalar') . "\n";

# Try to find StatementList in children
my @children = $ctx->children->@*;
print "Program has " . scalar(@children) . " children\n";

for my $i (0..$#children) {
    my $child = $children[$i];
    next unless $child && $child->can('focus');

    my $child_focus = $child->focus;
    next unless ref($child_focus) eq 'ARRAY';

    print "\nChild $i (StatementList) has " . scalar(@$child_focus) . " statements:\n";
    for my $j (0..$#{$child_focus}) {
        my $stmt = $child_focus->[$j];
        print "  Statement $j: " . (ref($stmt) || 'scalar');
        if (ref($stmt) && $stmt->can('op')) {
            print " (op: " . $stmt->op . ")";
        }
        print "\n";
    }
}

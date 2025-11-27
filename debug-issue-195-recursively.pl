#!/usr/bin/env perl
# ABOUTME: Recursively trace parse tree for issue #195
# ABOUTME: Shows full parse structure with all nested alternatives

use 5.42.0;
use experimental qw(class);
use lib 'lib';

use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Semiring::SPPF;

# Load Chalk grammar
open my $fh, '<:utf8', 'grammar/chalk.bnf' or die "Cannot open chalk.bnf: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Test case from issue #195
my $code = 'my $x = -5; if ($x > 0) { return 42; } return -42;';

# Parse with SPPF semiring to get forest
my $sppf_semiring = Chalk::Semiring::SPPF->new();
my $parser = Chalk::Parser->new(grammar => $grammar, semiring => $sppf_semiring);
my $result = $parser->parse_string($code);

die "Parse failed\n" unless $result;

my $forest = $sppf_semiring->forest;

# Recursive function to print parse tree
sub print_tree {
    my ($node, $indent, $visited) = @_;
    $indent //= "";
    $visited //= {};

    my $key = refaddr($node);
    if ($visited->{$key}) {
        print "${indent}(already visited: $node)\n";
        return;
    }
    $visited->{$key} = 1;

    if ($node->isa('Chalk::ParseForest::SymbolNode')) {
        print "${indent}SymbolNode: " . $node->symbol . " at " . $node->start_pos . ".." . $node->end_pos . "\n";
        my @packed = $node->packed_nodes;
        if (@packed > 1) {
            print "${indent}  (has " . scalar(@packed) . " alternatives)\n";
        }
        for my $i (0..$#packed) {
            if (@packed > 1) {
                print "${indent}  Alternative $i:\n";
            }
            my $packed_node = $packed[$i];
            print "${indent}    Rule: " . ($packed_node->rule ? $packed_node->rule->to_string : "no rule") . "\n";
            for my $child ($packed_node->children) {
                print_tree($child, "$indent    ", $visited);
            }
        }
    } elsif ($node->isa('Chalk::ParseForest::IntermediateNode')) {
        print "${indent}IntermediateNode: " . $node->rule_label . " at " . $node->start_pos . ".." . $node->end_pos . "\n";
        my @packed = $node->packed_nodes;
        for my $i (0..$#packed) {
            my $packed_node = $packed[$i];
            for my $child ($packed_node->children) {
                print_tree($child, "$indent  ", $visited);
            }
        }
    } elsif ($node->isa('Chalk::ParseForest::TerminalNode')) {
        my $text = substr($code, $node->start_pos, $node->end_pos - $node->start_pos);
        print "${indent}Terminal: '$text'\n";
    }
}

# Find top-level StatementList
my $nodes = $forest->nodes;
for my $node (values %$nodes) {
    next unless $node->isa('Chalk::ParseForest::SymbolNode');
    next unless $node->symbol eq 'StatementList';
    next unless $node->start_pos == 0 && $node->end_pos == length($code);

    print "=== Top-Level StatementList ===\n";
    print_tree($node);
    last;
}

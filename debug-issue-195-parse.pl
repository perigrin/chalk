#!/usr/bin/env perl
# ABOUTME: Debug script to trace parse tree for issue #195
# ABOUTME: Shows how StatementList parses the early return test case

use 5.42.0;
use experimental qw(class);
use lib 'lib';
use Data::Dumper;

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

if (!$result) {
    die "Parse failed\n";
}

my $forest = $sppf_semiring->forest;

# Find all StatementList nodes
my $nodes = $forest->nodes;
my @stmtlist_nodes;

for my $node (values %$nodes) {
    next unless $node->isa('Chalk::ParseForest::SymbolNode');
    next unless $node->symbol eq 'StatementList';
    push @stmtlist_nodes, $node;
}

# Sort by position
@stmtlist_nodes = sort { $a->start_pos <=> $b->start_pos || $a->end_pos <=> $b->end_pos } @stmtlist_nodes;

print "Found " . scalar(@stmtlist_nodes) . " StatementList nodes\n\n";

# Focus on the top-level StatementList (covers entire input)
for my $node (@stmtlist_nodes) {
    next unless $node->start_pos == 0 && $node->end_pos == length($code);

    print "=== Top-Level StatementList (0.." . $node->end_pos . ") ===\n";
    my @packed = $node->packed_nodes;
    print "Alternatives: " . scalar(@packed) . "\n\n";

    for my $i (0..$#packed) {
        my $packed_node = $packed[$i];
        print "Alternative $i:\n";
        print "  Rule: " . ($packed_node->rule ? $packed_node->rule->to_string : "no rule") . "\n";

        # Get children from the packed node
        my @children = $packed_node->children;
        print "  Children (" . scalar(@children) . "):\n";

        for my $child (@children) {
            if (!defined $child) {
                print "    - undef\n";
            } elsif ($child->isa('Chalk::ParseForest::SymbolNode')) {
                print "    - SymbolNode: " . $child->symbol . " at " . $child->start_pos . ".." . $child->end_pos;
                if ($child->symbol eq 'StatementList') {
                    my @sub_packed = $child->packed_nodes;
                    print " (has " . scalar(@sub_packed) . " alternatives)";
                } elsif ($child->symbol eq 'Statement') {
                    my @sub_packed = $child->packed_nodes;
                    my $text = substr($code, $child->start_pos, $child->end_pos - $child->start_pos);
                    print " [$text]";
                }
                print "\n";
            } elsif ($child->isa('Chalk::ParseForest::TerminalNode')) {
                my $text = substr($code, $child->start_pos, $child->end_pos - $child->start_pos);
                print "    - Terminal: '$text' at " . $child->start_pos . ".." . $child->end_pos . "\n";
            } elsif ($child->isa('Chalk::ParseForest::IntermediateNode')) {
                print "    - IntermediateNode: " . $child->rule_label . " at " . $child->start_pos . ".." . $child->end_pos . "\n";
            } else {
                print "    - " . ref($child) . "\n";
            }
        }
        print "\n";
    }
}

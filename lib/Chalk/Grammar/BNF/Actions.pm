# ABOUTME: Semantic actions for BNF meta-grammar that build IR nodes from parse results.
# ABOUTME: One method per BNF rule, plus helpers for desugared rules, constructing IR via NodeFactory.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::Bootstrap::IR::NodeFactory;

class Chalk::Grammar::BNF::Actions {
    field $factory;

    ADJUST {
        $factory = Chalk::Bootstrap::IR::NodeFactory->instance();
    }

    # Shared implementation for Rule_plus and Rule_star
    my sub _collect_rule_list {
        my ($ctx) = @_;

        my @leaves = $ctx->leaves();
        my @rules;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY') {
                # Nested Rule_star result — flatten
                push @rules, $focus->@*;
            } elsif ($focus isa 'Chalk::Bootstrap::IR::Node::Constructor' && $focus->class() eq 'Rule') {
                push @rules, $focus;
            }
        }

        return \@rules;
    }

    # Grammar ::= /(?:\s|#[^\n]*)*/ Rule+
    # Returns arrayref of Constructor:Rule IR nodes
    method Grammar($ctx) {
        # Collect all Constructor:Rule nodes from the binary Context tree
        # Rule+ desugars to Rule_plus which returns an arrayref
        my @leaves = $ctx->leaves();
        my @rules;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY') {
                # Rule_plus/Rule_star returns arrayref of Constructor:Rule nodes
                push @rules, $focus->@*;
            } elsif ($focus isa 'Chalk::Bootstrap::IR::Node::Constructor' && $focus->class() eq 'Rule') {
                push @rules, $focus;
            }
        }

        # Return arrayref of all rules
        return \@rules;
    }

    # Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/
    # Returns Constructor:Rule IR node
    method Rule($ctx) {
        # Collect all leaves from the binary tree
        my @leaves = $ctx->leaves();

        # Find name (Constant from Identifier) and alternatives (arrayref from Alternatives)
        my $name_node;
        my $alts_node;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY') {
                # Alternatives returns an arrayref of Constructor:Expression nodes
                $alts_node = $focus;
            } elsif ($focus isa 'Chalk::Bootstrap::IR::Node::Constant' && !defined $name_node) {
                # First Constant is the identifier name
                $name_node = $focus;
            }
        }

        return $factory->make('Constructor',
            class => 'Rule',
            name => $name_node,
            expressions => $alts_node,
        );
    }

    # Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence
    # Returns arrayref of Constructor:Expression nodes (one per alternative)
    method Alternatives($ctx) {
        # Collect all leaves and extract Constructor:Expression nodes
        # Nested Alternatives produce arrayrefs of Expressions, not single Expressions
        my @leaves = $ctx->leaves();
        my @expressions;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY') {
                # Nested Alternatives result — flatten the arrayrefs
                push @expressions, $focus->@*;
            } elsif ($focus isa 'Chalk::Bootstrap::IR::Node::Constructor' && $focus->class() eq 'Expression') {
                push @expressions, $focus;
            }
        }

        # Return arrayref of all expressions
        return \@expressions;
    }

    # Sequence ::= Element /(?:\s|#[^\n]*)+/ Sequence | Element
    # Returns Constructor:Expression with list of symbols
    method Sequence($ctx) {
        # Collect all leaves and extract Constructor:Symbol nodes
        # Nested Sequence matches produce Constructor:Expression nodes containing Symbol arrays
        my @leaves = $ctx->leaves();
        my @elements;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa 'Chalk::Bootstrap::IR::Node::Constructor' && $focus->class() eq 'Symbol') {
                push @elements, $focus;
            } elsif ($focus isa 'Chalk::Bootstrap::IR::Node::Constructor' && $focus->class() eq 'Expression') {
                # Nested Sequence result — extract its elements
                my $inner_elements = $focus->inputs()->[0];
                push @elements, $inner_elements->@* if $inner_elements;
            }
        }

        return $factory->make('Constructor',
            class => 'Expression',
            elements => \@elements,
        );
    }

    # Element ::= Atom Quantifier?
    # Returns Constructor:Symbol with optional quantifier
    method Element($ctx) {
        # Collect all leaves from the binary tree
        my @leaves = $ctx->leaves();

        # Find the Constructor:Symbol (from Atom) and optional Constant (from Quantifier)
        my $symbol;
        my $quantifier;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa 'Chalk::Bootstrap::IR::Node::Constructor' && $focus->class() eq 'Symbol') {
                $symbol = $focus;
            } elsif ($focus isa 'Chalk::Bootstrap::IR::Node::Constant' && defined $focus->value()
                     && $focus->value() =~ /^[*+?]$/) {
                $quantifier = $focus;
            }
        }

        # If quantifier exists, create new symbol with quantifier
        if (defined $quantifier) {
            return $factory->make('Constructor',
                class => 'Symbol',
                type => $symbol->inputs()->[0],
                value => $symbol->inputs()->[1],
                quantifier => $quantifier,
            );
        }

        # No quantifier, return symbol as-is
        return $symbol;
    }

    # Atom ::= Identifier | InlineRegex
    # Returns Constructor:Symbol (reference for Identifier, terminal for InlineRegex)
    method Atom($ctx) {
        # Find the child with a Constant focus (from Identifier or InlineRegex)
        my @leaves = $ctx->leaves();
        my $value_leaf;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa 'Chalk::Bootstrap::IR::Node::Constant') {
                $value_leaf = $leaf;
                last;
            }
        }

        my $value_node = $value_leaf->extract();

        # Determine type using rule field if available, fall back to value format
        my $type;
        my $rule = $value_leaf->rule();
        if (defined $rule && $rule eq 'InlineRegex') {
            $type = $factory->make('Constant', const_type => 'enum', value => 'terminal');
        } elsif (defined $rule && $rule eq 'Identifier') {
            $type = $factory->make('Constant', const_type => 'enum', value => 'reference');
        } elsif ($value_node->value() =~ m{^/}) {
            # Fallback for pre-wired contexts: regex on value
            $type = $factory->make('Constant', const_type => 'enum', value => 'terminal');
        } else {
            $type = $factory->make('Constant', const_type => 'enum', value => 'reference');
        }

        my $quant = $factory->make('Constant', const_type => 'string', value => undef);

        return $factory->make('Constructor',
            class => 'Symbol',
            type => $type,
            value => $value_node,
            quantifier => $quant,
        );
    }

    # Quantifier ::= /\*/ | /\+/ | /\?/
    # Returns Constant with quantifier string
    method Quantifier($ctx) {
        # Use extract() for pre-wired contexts, fall back to scanning tree
        my $quantifier = $ctx->extract();
        $quantifier = $ctx->scanned_text() unless defined $quantifier;

        return $factory->make('Constant', const_type => 'string', value => $quantifier);
    }

    # Comment ::= /#[^\n]*/
    # Returns nothing (comments ignored)
    method Comment($ctx) {
        return undef;
    }

    # Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
    # Returns Constant with identifier string
    method Identifier($ctx) {
        # Use extract() for pre-wired contexts, fall back to scanning tree
        my $identifier = $ctx->extract();
        $identifier = $ctx->scanned_text() unless defined $identifier;

        return $factory->make('Constant', const_type => 'string', value => $identifier);
    }

    # InlineRegex ::= /\/(?:[^\/\\]|\\.)*\//
    # Returns Constant with regex string
    method InlineRegex($ctx) {
        # Use extract() for pre-wired contexts, fall back to scanning tree
        my $regex = $ctx->extract();
        $regex = $ctx->scanned_text() unless defined $regex;

        return $factory->make('Constant', const_type => 'string', value => $regex);
    }

    # Rule_plus ::= Rule Rule_star (desugared from Rule+)
    # Collects all Constructor:Rule nodes from the recursive structure
    method Rule_plus($ctx) {
        return _collect_rule_list($ctx);
    }

    # Rule_star ::= Rule Rule_star | epsilon (desugared from Rule+)
    # Collects all Constructor:Rule nodes from the recursive structure
    method Rule_star($ctx) {
        return _collect_rule_list($ctx);
    }

    # Quantifier_opt ::= Quantifier | epsilon (desugared from Quantifier?)
    # Returns the Quantifier's Constant value or undef (epsilon case)
    method Quantifier_opt($ctx) {
        my @leaves = $ctx->leaves();
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa 'Chalk::Bootstrap::IR::Node::Constant') {
                return $focus;
            }
        }

        # Epsilon case - no quantifier found
        return undef;
    }
}

1;

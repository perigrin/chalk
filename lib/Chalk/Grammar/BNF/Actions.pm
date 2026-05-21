# ABOUTME: Semantic actions for BNF meta-grammar that build grammar data model objects from parse results.
# ABOUTME: One method per BNF rule, plus helpers for desugared rules, constructing Grammar::Symbol/Rule directly.
use 5.42.0;
use utf8;
use experimental 'class';

use Chalk::IR::NodeFactory;
use Chalk::Grammar::Symbol;
use Chalk::Grammar::Rule;

class Chalk::Grammar::BNF::Actions {
    field $factory;

    ADJUST {
        $factory = Chalk::IR::NodeFactory->new();
    }

    # Shared implementation for Rule_plus and Rule_star
    my sub _collect_rule_list {
        my ($ctx) = @_;

        my @leaves = $ctx->leaves();
        my @rules;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY' && scalar($focus->@*) > 0 && $focus->[0] isa 'Chalk::Grammar::Rule') {
                # Nested Rule_star result — flatten
                push @rules, $focus->@*;
            } elsif ($focus isa 'Chalk::Grammar::Rule') {
                push @rules, $focus;
            }
        }

        return \@rules;
    }

    # Grammar ::= /(?:\s|#[^\n]*)*/ Rule+
    # Returns arrayref of Chalk::Grammar::Rule objects
    method Grammar($ctx) {
        # Collect all Chalk::Grammar::Rule objects from the binary Context tree
        # Rule+ desugars to Rule_plus which returns an arrayref
        my @leaves = $ctx->leaves();
        my @rules;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY' && scalar($focus->@*) > 0 && $focus->[0] isa 'Chalk::Grammar::Rule') {
                # Rule_plus/Rule_star returns arrayref of Chalk::Grammar::Rule objects
                push @rules, $focus->@*;
            } elsif ($focus isa 'Chalk::Grammar::Rule') {
                push @rules, $focus;
            }
        }

        # Return arrayref of all rules
        return \@rules;
    }

    # Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/
    # Returns Chalk::Grammar::Rule object
    method Rule($ctx) {
        # Collect all leaves from the binary tree
        my @leaves = $ctx->leaves();

        # Find name (string from Identifier) and alternatives (arrayref from Alternatives)
        my $name_str;
        my $alts_node;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY' && !defined $alts_node) {
                # Alternatives returns an arrayref of arrayrefs of Symbol objects
                $alts_node = $focus;
            } elsif ($focus isa Chalk::IR::Node::Constant && !defined $name_str) {
                # First Constant is the identifier name
                $name_str = $focus->value();
            }
        }

        return Chalk::Grammar::Rule->new(
            name        => $name_str,
            expressions => $alts_node,
        );
    }

    # Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence
    # Returns arrayref of arrayrefs of Symbol objects (one arrayref per alternative)
    method Alternatives($ctx) {
        # Collect all leaves and extract expression arrayrefs (each is an arrayref of Symbol)
        # Nested Alternatives produce arrayrefs of arrayrefs, not single arrayrefs
        my @leaves = $ctx->leaves();
        my @expressions;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if (ref($focus) eq 'ARRAY') {
                # Distinguish: an arrayref of Symbol objects (one expression)
                # vs an arrayref of arrayrefs (nested Alternatives result)
                if (scalar($focus->@*) == 0 || $focus->[0] isa 'Chalk::Grammar::Symbol') {
                    # Single expression (arrayref of Symbols)
                    push @expressions, $focus;
                } else {
                    # Nested Alternatives result — each element is an arrayref of Symbols
                    push @expressions, $focus->@*;
                }
            }
        }

        # Return arrayref of all expressions (each is an arrayref of Symbol objects)
        return \@expressions;
    }

    # Sequence ::= Element /(?:\s|#[^\n]*)+/ Sequence | Element
    # Returns arrayref of Chalk::Grammar::Symbol objects
    method Sequence($ctx) {
        # Collect all leaves and extract Symbol objects
        # Nested Sequence matches produce arrayrefs of Symbols
        my @leaves = $ctx->leaves();
        my @elements;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa 'Chalk::Grammar::Symbol') {
                push @elements, $focus;
            } elsif (ref($focus) eq 'ARRAY' && scalar($focus->@*) > 0
                     && $focus->[0] isa 'Chalk::Grammar::Symbol') {
                # Nested Sequence result — flatten
                push @elements, $focus->@*;
            }
        }

        return \@elements;
    }

    # Element ::= Atom Quantifier?
    # Returns Chalk::Grammar::Symbol with optional quantifier applied
    method Element($ctx) {
        # Collect all leaves from the binary tree
        my @leaves = $ctx->leaves();

        # Find the Symbol (from Atom) and optional quantifier string (from Quantifier)
        my $symbol;
        my $quantifier;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa 'Chalk::Grammar::Symbol') {
                $symbol = $focus;
            } elsif ($focus isa Chalk::IR::Node::Constant && defined $focus->value()
                     && $focus->value() =~ /^[*+?]$/) {
                $quantifier = $focus->value();
            }
        }

        # If quantifier exists, create new symbol with quantifier applied
        if (defined $quantifier) {
            return Chalk::Grammar::Symbol->new(
                type       => $symbol->type(),
                value      => $symbol->value(),
                quantifier => $quantifier,
            );
        }

        # No quantifier, return symbol as-is
        return $symbol;
    }

    # Atom ::= Identifier | InlineRegex
    # Returns Chalk::Grammar::Symbol (reference for Identifier, terminal for InlineRegex)
    method Atom($ctx) {
        # Find the child with a Constant focus (from Identifier or InlineRegex)
        my @leaves = $ctx->leaves();
        my $value_leaf;
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::IR::Node::Constant) {
                $value_leaf = $leaf;
                last;
            }
        }

        my $value_node = $value_leaf->extract();
        my $raw_value = $value_node->value();

        # Determine type using rule field if available, fall back to value format
        my $type;
        my $rule = $value_leaf->rule();
        if (defined $rule && $rule eq 'InlineRegex') {
            $type = 'terminal';
        } elsif (defined $rule && $rule eq 'Identifier') {
            $type = 'reference';
        } elsif ($raw_value =~ m{^/}) {
            # Fallback for pre-wired contexts: regex on value
            $type = 'terminal';
        } else {
            $type = 'reference';
        }

        return Chalk::Grammar::Symbol->new(
            type  => $type,
            value => $raw_value,
        );
    }

    # Quantifier ::= /\*/ | /\+/ | /\?/
    # Returns Constant with quantifier string (still used by Element to read quantifier value)
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
    # Collects all Chalk::Grammar::Rule objects from the recursive structure
    method Rule_plus($ctx) {
        return _collect_rule_list($ctx);
    }

    # Rule_star ::= Rule Rule_star | epsilon (desugared from Rule+)
    # Collects all Chalk::Grammar::Rule objects from the recursive structure
    method Rule_star($ctx) {
        return _collect_rule_list($ctx);
    }

    # Quantifier_opt ::= Quantifier | epsilon (desugared from Quantifier?)
    # Returns the Quantifier's Constant value or undef (epsilon case)
    method Quantifier_opt($ctx) {
        my @leaves = $ctx->leaves();
        for my $leaf (@leaves) {
            my $focus = $leaf->extract();
            if ($focus isa Chalk::IR::Node::Constant) {
                return $focus;
            }
        }

        # Epsilon case - no quantifier found
        return undef;
    }
}

1;

# ABOUTME: Semantic actions for BNF meta-grammar that build IR nodes from parse results.
# ABOUTME: Provides 10 action functions, one per BNF rule, that construct IR using NodeFactory.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::Actions;

use Chalk::Bootstrap::IR::NodeFactory;
use Exporter 'import';
our @EXPORT_OK = qw(_collect_children action_registry);

# Get singleton factory
sub _factory {
    return Chalk::Bootstrap::IR::NodeFactory->instance();
}

# Recursively collect leaf contexts from a binary Context tree
# A "leaf" is a context that has a defined focus (from complete_value).
# Optional $node_class parameter filters to only contexts whose focus isa $node_class.
sub _collect_children {
    my ($ctx, $node_class) = @_;
    my @results;

    my $focus = $ctx->extract();
    if (defined $focus) {
        # This context has a focus — it's a "leaf" produced by complete_value
        if (!$node_class || (ref($focus) && $focus->isa($node_class))) {
            push @results, $ctx;
        }
        return @results;
    }

    # No focus — this is an intermediate multiply() node. Recurse into children.
    for my $child ($ctx->children()->@*) {
        push @results, _collect_children($child, $node_class);
    }

    return @results;
}

# Grammar ::= /(?:\s|#[^\n]*)*/ Rule+
# Returns arrayref of MakeRule IR nodes
sub action_Grammar {
    my ($ctx) = @_;

    # Collect all MakeRule nodes from the binary Context tree
    # Rule+ desugars to Rule_plus which returns an arrayref
    my @leaves = _collect_children($ctx);
    my @rules;
    for my $leaf (@leaves) {
        my $focus = $leaf->extract();
        if (ref($focus) eq 'ARRAY') {
            # Rule_plus/Rule_star returns arrayref of MakeRule nodes
            push @rules, $focus->@*;
        } elsif (defined $focus && ref($focus) && $focus->isa('Chalk::Bootstrap::IR::Node::MakeRule')) {
            push @rules, $focus;
        }
    }

    # Return arrayref of all rules
    return \@rules;
}

# Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/
# Returns MakeRule IR node
sub action_Rule {
    my ($ctx) = @_;

    # Collect all leaves from the binary tree
    my @leaves = _collect_children($ctx);

    # Find name (Constant from Identifier) and alternatives (arrayref from Alternatives)
    my $name_node;
    my $alts_node;
    for my $leaf (@leaves) {
        my $focus = $leaf->extract();
        if (!defined $focus) {
            next;
        } elsif (ref($focus) eq 'ARRAY') {
            # action_Alternatives returns an arrayref of MakeExpression nodes
            $alts_node = $focus;
        } elsif ($focus->isa('Chalk::Bootstrap::IR::Node::Constant') && !defined $name_node) {
            # First Constant is the identifier name
            $name_node = $focus;
        }
    }

    return _factory()->make('MakeRule',
        name => $name_node,
        expressions => $alts_node,
    );
}

# Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence
# Returns arrayref of MakeExpression nodes (one per alternative)
sub action_Alternatives {
    my ($ctx) = @_;

    # Recursively collect all MakeExpression nodes from the binary tree
    my @leaves = _collect_children($ctx, 'Chalk::Bootstrap::IR::Node::MakeExpression');

    my @expressions = map { $_->extract() } @leaves;

    # Return arrayref of all expressions
    return \@expressions;
}

# Sequence ::= Element /(?:\s|#[^\n]*)+/ Sequence | Element
# Returns MakeExpression with list of symbols
sub action_Sequence {
    my ($ctx) = @_;

    # Recursively collect all MakeSymbol nodes from the binary tree
    my @leaves = _collect_children($ctx, 'Chalk::Bootstrap::IR::Node::MakeSymbol');

    my @elements = map { $_->extract() } @leaves;

    return _factory()->make('MakeExpression',
        elements => \@elements,
    );
}

# Element ::= Atom Quantifier?
# Returns MakeSymbol with optional quantifier
sub action_Element {
    my ($ctx) = @_;

    # Collect all leaves from the binary tree
    my @leaves = _collect_children($ctx);

    # Find the MakeSymbol (from Atom) and optional Constant (from Quantifier)
    my $symbol;
    my $quantifier;
    for my $leaf (@leaves) {
        my $focus = $leaf->extract();
        next unless defined $focus && ref($focus);
        if ($focus->isa('Chalk::Bootstrap::IR::Node::MakeSymbol')) {
            $symbol = $focus;
        } elsif ($focus->isa('Chalk::Bootstrap::IR::Node::Constant') && defined $focus->value()
                 && $focus->value() =~ /^[*+?]$/) {
            $quantifier = $focus;
        }
    }

    # If quantifier exists, create new symbol with quantifier
    if (defined $quantifier) {
        return _factory()->make('MakeSymbol',
            type => $symbol->inputs()->[0],
            value => $symbol->inputs()->[1],
            quantifier => $quantifier,
        );
    }

    # No quantifier, return symbol as-is
    return $symbol;
}

# Atom ::= Identifier | InlineRegex
# Returns MakeSymbol (reference for Identifier, terminal for InlineRegex)
sub action_Atom {
    my ($ctx) = @_;

    # Find the child with a Constant focus (from Identifier or InlineRegex)
    my @leaves = _collect_children($ctx);
    my $value_leaf;
    for my $leaf (@leaves) {
        my $focus = $leaf->extract();
        if (defined $focus && ref($focus) && $focus->isa('Chalk::Bootstrap::IR::Node::Constant')) {
            $value_leaf = $leaf;
            last;
        }
    }

    my $value_node = $value_leaf->extract();

    # Determine type using rule field if available, fall back to value format
    my $type;
    my $rule = $value_leaf->rule();
    if (defined $rule && $rule eq 'InlineRegex') {
        $type = _factory()->make('Constant', const_type => 'enum', value => 'terminal');
    } elsif (defined $rule && $rule eq 'Identifier') {
        $type = _factory()->make('Constant', const_type => 'enum', value => 'reference');
    } elsif ($value_node->value() =~ m{^/}) {
        # Fallback for pre-wired contexts: regex on value
        $type = _factory()->make('Constant', const_type => 'enum', value => 'terminal');
    } else {
        $type = _factory()->make('Constant', const_type => 'enum', value => 'reference');
    }

    my $quant = _factory()->make('Constant', const_type => 'string', value => undef);

    return _factory()->make('MakeSymbol',
        type => $type,
        value => $value_node,
        quantifier => $quant,
    );
}

# Quantifier ::= /\*/ | /\+/ | /\?/
# Returns Constant with quantifier string
sub action_Quantifier {
    my ($ctx) = @_;
    my $quantifier = $ctx->extract();

    return _factory()->make('Constant', const_type => 'string', value => $quantifier);
}

# Comment ::= /#[^\n]*/
# Returns nothing (comments ignored)
sub action_Comment {
    my ($ctx) = @_;
    return undef;
}

# Identifier ::= /[A-Za-z_][A-Za-z_0-9]*/
# Returns Constant with identifier string
sub action_Identifier {
    my ($ctx) = @_;
    my $identifier = $ctx->extract();

    return _factory()->make('Constant', const_type => 'string', value => $identifier);
}

# InlineRegex ::= /\/(?:[^\/\\]|\\.)*\//
# Returns Constant with regex string
sub action_InlineRegex {
    my ($ctx) = @_;
    my $regex = $ctx->extract();

    return _factory()->make('Constant', const_type => 'string', value => $regex);
}

# Rule_plus ::= Rule Rule_star (desugared from Rule+)
# Collects all MakeRule nodes from the recursive structure
sub action_Rule_plus {
    my ($ctx) = @_;
    return _collect_rule_list($ctx);
}

# Rule_star ::= Rule Rule_star | epsilon (desugared from Rule+)
# Collects all MakeRule nodes from the recursive structure
sub action_Rule_star {
    my ($ctx) = @_;
    return _collect_rule_list($ctx);
}

# Shared implementation for Rule_plus and Rule_star
sub _collect_rule_list {
    my ($ctx) = @_;

    my @leaves = _collect_children($ctx, 'Chalk::Bootstrap::IR::Node::MakeRule');
    my @rules = map { $_->extract() } @leaves;

    return \@rules;
}

# Quantifier_opt ::= Quantifier | epsilon (desugared from Quantifier?)
# Returns the Quantifier's Constant value or undef (epsilon case)
sub action_Quantifier_opt {
    my ($ctx) = @_;

    my @leaves = _collect_children($ctx);
    for my $leaf (@leaves) {
        my $focus = $leaf->extract();
        if (defined $focus && ref($focus) && $focus->isa('Chalk::Bootstrap::IR::Node::Constant')) {
            return $focus;
        }
    }

    # Epsilon case - no quantifier found
    return undef;
}

# Returns a hash mapping rule names to action coderefs
# Used by SemanticAction semiring to register actions for complete_value
sub action_registry {
    return {
        Grammar        => \&action_Grammar,
        Rule           => \&action_Rule,
        Alternatives   => \&action_Alternatives,
        Sequence       => \&action_Sequence,
        Element        => \&action_Element,
        Atom           => \&action_Atom,
        Quantifier     => \&action_Quantifier,
        Comment        => \&action_Comment,
        Identifier     => \&action_Identifier,
        InlineRegex    => \&action_InlineRegex,
        Rule_plus      => \&action_Rule_plus,
        Rule_star      => \&action_Rule_star,
        Quantifier_opt => \&action_Quantifier_opt,
    };
}

1;

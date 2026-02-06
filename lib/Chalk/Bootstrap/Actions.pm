# ABOUTME: Semantic actions for BNF meta-grammar that build IR nodes from parse results.
# ABOUTME: Provides 10 action functions, one per BNF rule, that construct IR using NodeFactory.
use 5.42.0;
use utf8;

package Chalk::Bootstrap::Actions;

use Chalk::Bootstrap::IR::NodeFactory;

# Get singleton factory
sub _factory {
    return Chalk::Bootstrap::IR::NodeFactory->instance();
}

# Grammar ::= /(?:\s|#[^\n]*)*/ Rule+
# Returns list of MakeRule IR nodes
sub action_Grammar {
    my ($ctx) = @_;

    # Skip whitespace child, collect all Rule children
    my @children = $ctx->children()->@*;
    my @rules;

    for my $child (@children) {
        my $focus = $child->extract();
        if (defined $focus && $focus->isa('Chalk::Bootstrap::IR::Node::MakeRule')) {
            push @rules, $focus;
        }
    }

    # For now, return first rule or undef
    # Later, this might wrap in a Grammar node
    return $rules[0] if @rules;
    return undef;
}

# Rule ::= Identifier /(?:\s|#[^\n]*)*/ /::=/ /(?:\s|#[^\n]*)*/ Alternatives /(?:\s|#[^\n]*)*/ /;/ /(?:\s|#[^\n]*)*/
# Returns MakeRule IR node
sub action_Rule {
    my ($ctx) = @_;
    my @children = $ctx->children()->@*;

    # Extract rule name from first child (Identifier)
    my $name_node = $children[0]->extract();

    # Extract alternatives from Alternatives child (skip whitespace/punctuation)
    my $alts_node;
    for my $child (@children) {
        my $focus = $child->extract();
        if (defined $focus && $focus->isa('Chalk::Bootstrap::IR::Node::MakeExpression')) {
            $alts_node = $focus;
            last;
        }
    }

    return _factory()->make('MakeRule',
        name => $name_node,
        expressions => $alts_node,
    );
}

# Alternatives ::= Sequence /(?:\s|#[^\n]*)*/ /\|/ /(?:\s|#[^\n]*)*/ Alternatives | Sequence
# Returns MakeExpression (for single alternative) or list of MakeExpression nodes
sub action_Alternatives {
    my ($ctx) = @_;
    my @children = $ctx->children()->@*;

    # Collect all Sequence children (MakeExpression nodes)
    my @expressions;
    for my $child (@children) {
        my $focus = $child->extract();
        if (defined $focus && $focus->isa('Chalk::Bootstrap::IR::Node::MakeExpression')) {
            push @expressions, $focus;
        }
    }

    # Return first expression (simplification)
    # TODO: Handle multiple alternatives properly
    return $expressions[0] if @expressions;
    return undef;
}

# Sequence ::= Sequence_Element /(?:\s|#[^\n]*)+/ Sequence | Sequence_Element
# Returns MakeExpression with list of symbols
sub action_Sequence {
    my ($ctx) = @_;
    my @children = $ctx->children()->@*;

    # Collect all Element children (MakeSymbol nodes)
    my @elements;
    for my $child (@children) {
        my $focus = $child->extract();
        if (defined $focus && $focus->isa('Chalk::Bootstrap::IR::Node::MakeSymbol')) {
            push @elements, $focus;
        }
    }

    return _factory()->make('MakeExpression',
        elements => \@elements,
    );
}

# Element ::= Atom Quantifier?
# Returns MakeSymbol with optional quantifier
sub action_Element {
    my ($ctx) = @_;
    my @children = $ctx->children()->@*;

    # First child is Atom (MakeSymbol)
    my $symbol = $children[0]->extract();

    # Second child might be Quantifier (Constant with quantifier string)
    my $quantifier = undef;
    if (@children > 1) {
        $quantifier = $children[1]->extract();
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
    my @children = $ctx->children()->@*;

    # Child is Constant with identifier or regex value
    my $value_node = $children[0]->extract();
    my $value = $value_node->value();

    # Determine type based on value format
    my $type;
    if ($value =~ m{^/}) {
        # InlineRegex
        $type = _factory()->make('Constant', const_type => 'enum', value => 'terminal');
    } else {
        # Identifier
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

1;

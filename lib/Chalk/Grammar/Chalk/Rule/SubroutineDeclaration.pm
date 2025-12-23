# ABOUTME: Semantic action for SubroutineDeclaration - creates FunctionDef IR nodes
# ABOUTME: Extracts function name, parameters, and body to create function definition
use 5.42.0;
use experimental 'class';
use Scalar::Util 'blessed';

class Chalk::Grammar::Chalk::Rule::SubroutineDeclaration :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::FunctionDef;

        # SubroutineDeclaration has two forms:
        # 1. 'sub' WS_OPT QualifiedIdentifier WS_OPT '(' WS_OPT ParameterList WS_OPT ')' WS_OPT Block
        # 2. 'sub' WS_OPT QualifiedIdentifier WS_OPT Block
        my @children = $context->children->@*;
        my $num_children = scalar @children;

        # Find function name - it's the first non-keyword, non-whitespace child
        # Child 0 is 'sub', child 1 is WS_OPT, child 2 is QualifiedIdentifier
        my $func_name = $self->_extract_name($context->child(2));

        # Find parameters and body by detecting which form we have
        my @parameters;
        my $body_node;

        # Check if we have parentheses (look for '(' in children)
        my $has_parens = 0;
        for my $i (0 .. $#children) {
            my $child = $context->child($i);
            next unless defined $child;
            if (!ref($child) && $child eq '(') {
                $has_parens = 1;
                last;
            }
        }

        if ($has_parens) {
            # Form 1: sub name(params) block
            # Find ParameterList child (between '(' and ')')
            my $paren_open_idx;
            my $paren_close_idx;
            for my $i (0 .. $#children) {
                my $child = $context->child($i);
                next unless defined $child;
                if (!ref($child) && $child eq '(') {
                    $paren_open_idx = $i;
                } elsif (!ref($child) && $child eq ')') {
                    $paren_close_idx = $i;
                }
            }

            # Extract parameters from children between parentheses
            if (defined $paren_open_idx && defined $paren_close_idx) {
                for my $i ($paren_open_idx + 1 .. $paren_close_idx - 1) {
                    my $child = $context->child($i);
                    $self->_collect_parameters($child, \@parameters);
                }
            }

            # Body is the last child (Block)
            $body_node = $context->child($#children);
        } else {
            # Form 2: sub name block
            # No parameters, body is last child
            $body_node = $context->child($#children);
        }

        # Create FunctionDef node
        my $func_def = Chalk::IR::Node::FunctionDef->new(
            name       => $func_name,
            parameters => \@parameters,
            body_graph => undef,  # Will be set up during execution
        );

        # Store the body node for execution
        # We attach it as an attribute since body_graph expects a Graph
        $func_def->{_body_node} = $body_node;

        # Register function in context if function registry is available
        my $registry = $context->env->{function_registry};
        if ($registry) {
            $registry->register($func_name, $func_def);
        }

        return $func_def;
    }

    # Extract function name from QualifiedIdentifier result
    method _extract_name($name_node) {
        return '' unless defined $name_node;

        # QualifiedIdentifier returns a string (possibly joined with '::')
        if (!ref($name_node)) {
            return "$name_node";
        }

        # If it's an array of characters (from Identifier)
        if (ref($name_node) eq 'ARRAY') {
            return join('', $name_node->@*);
        }

        # Fallback
        return "$name_node";
    }

    # Recursively collect parameter names from ParameterList children
    method _collect_parameters($node, $params) {
        return unless defined $node;

        # Skip non-ref nodes (tokens like ',')
        return if !ref($node);

        # Variable metadata hash: { type => 'scalar_var', name => 'x', sigil => '$' }
        if (ref($node) eq 'HASH' && $node->{type}) {
            my $sigil = $node->{sigil} // '';
            my $name = $node->{name} // '';
            push $params->@*, $sigil . $name if $name;
            return;
        }

        # IR nodes (skip - these are from evaluated expressions)
        if (blessed($node) && $node->can('id')) {
            return;
        }

        # Arrays (from Identifier which returns array of chars)
        if (ref($node) eq 'ARRAY') {
            return;
        }
    }
}

1;

# ABOUTME: Semantic action for SubroutineDeclaration - creates FunctionDef IR nodes
# ABOUTME: Extracts function name, parameters, and body to create function definition
use 5.42.0;
use experimental 'class';
use Chalk::IR::Node::Parm;
use Chalk::IR::Node::Return;
use Chalk::IR::Node::Call;

class Chalk::Grammar::Chalk::Rule::SubroutineDeclaration :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::FunctionDef;

        # SubroutineDeclaration has two forms:
        # 1. 'sub' WS_OPT QualifiedIdentifier WS_OPT '(' WS_OPT ParameterList WS_OPT ')' WS_OPT Block
        # 2. 'sub' WS_OPT QualifiedIdentifier WS_OPT Block
        my @children = $context->children->@*;

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

            # Extract token value if it's a Token object
            my $value = $child;
            if (blessed($child) && $child->can('value')) {
                $value = $child->value;
            }

            if (defined($value) && !ref($value) && $value eq '(') {
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

                # Extract token value if it's a Token object
                my $value = $child;
                if (blessed($child) && $child->can('value')) {
                    $value = $child->value;
                }

                if (defined($value) && !ref($value) && $value eq '(') {
                    $paren_open_idx = $i;
                } elsif (defined($value) && !ref($value) && $value eq ')') {
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

        # Create Parm nodes for each parameter and replace UnboundVariable refs in body
        my %param_map;
        for my $i (0 .. $#parameters) {
            my $param_name = $parameters[$i];
            $param_map{$param_name} = Chalk::IR::Node::Parm->new(
                name  => $param_name,
                index => $i,
            );
        }

        # Replace UnboundVariable nodes in body with corresponding Parm nodes
        if (%param_map && defined $body_node) {
            $body_node = $self->_replace_unbound_variables($body_node, \%param_map);
        }

        # Create FunctionDef node
        # inputs => [] required by Base; actual inputs computed from body_node
        my $func_def = Chalk::IR::Node::FunctionDef->new(
            inputs     => [],
            name       => $func_name,
            parameters => \@parameters,
            body_graph => undef,  # Will be set up during execution
        );

        # Store the body node for execution using the setter method
        # (hash dereference doesn't work with new Perl class syntax)
        $func_def->set_body_node($body_node);

        # Register function in context if function registry is available
        my $env = $context->env;
        my $registry = $env ? $env->{function_registry} : undef;
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

        # ParameterList returns an array of Variable metadata hashes
        if (ref($node) eq 'ARRAY') {
            for my $item ($node->@*) {
                $self->_collect_parameters($item, $params);
            }
            return;
        }

        # Variable metadata hash: { type => 'scalar_var', name => 'x', sigil => '$' }
        if (ref($node) eq 'HASH' && $node->{type}) {
            my $sigil = $node->{sigil} // '';
            my $name = $node->{name} // '';
            push $params->@*, $sigil . $name if $name;
            return;
        }

        # Handle UnboundVariable nodes (parameters parsed as variable references)
        if (blessed($node) && $node->can('op') && $node->op eq 'UnboundVariable') {
            push $params->@*, $node->name if $node->name;
            return;
        }

        # Other IR nodes (skip - these are from evaluated expressions that aren't parameters)
        if (blessed($node) && $node->can('id')) {
            return;
        }
    }

    # Replace UnboundVariable nodes with Parm nodes for matching parameter names
    # Walks the IR tree recursively, rebuilding nodes when children change
    method _replace_unbound_variables($node, $param_map) {
        return $node unless defined $node;

        # Handle UnboundVariable directly - this is our target
        if (blessed($node) && $node->can('op') && $node->op eq 'UnboundVariable') {
            my $name = $node->name;
            if (exists $param_map->{$name}) {
                return $param_map->{$name};
            }
            return $node;  # Not a parameter, keep as unbound
        }

        # Handle block structure: { type => 'block', statements => [...] }
        if (ref($node) eq 'HASH' && $node->{statements}) {
            my @new_stmts;
            my $changed = 0;
            for my $stmt ($node->{statements}->@*) {
                my $new_stmt = $self->_replace_unbound_variables($stmt, $param_map);
                push @new_stmts, $new_stmt;
                $changed = 1 if refaddr($new_stmt) != refaddr($stmt);
            }
            if ($changed) {
                return { %$node, statements => \@new_stmts };
            }
            return $node;
        }

        # Handle arrays
        if (ref($node) eq 'ARRAY') {
            my @new_items;
            my $changed = 0;
            for my $item ($node->@*) {
                my $new_item = $self->_replace_unbound_variables($item, $param_map);
                push @new_items, $new_item;
                $changed = 1 if defined($new_item) && defined($item) && refaddr($new_item) != refaddr($item);
            }
            return $changed ? \@new_items : $node;
        }

        # Handle IR nodes - need to rebuild if children change
        if (blessed($node) && $node->can('op')) {
            return $self->_rebuild_node_with_replacements($node, $param_map);
        }

        return $node;
    }

    # Rebuild an IR node if any of its child nodes need replacement
    method _rebuild_node_with_replacements($node, $param_map) {
        my $op = $node->op;

        # Handle binary operators (left/right pattern)
        if ($node->can('left') && $node->can('right')) {
            my $left = $node->left;
            my $right = $node->right;
            my $new_left = $self->_replace_unbound_variables($left, $param_map);
            my $new_right = $self->_replace_unbound_variables($right, $param_map);

            if (refaddr($new_left) != refaddr($left) || refaddr($new_right) != refaddr($right)) {
                # Rebuild using the node's class
                my $class = ref($node);
                my %attrs = (left => $new_left, right => $new_right);
                $attrs{source_info} = $node->source_info if $node->can('source_info');
                return $class->new(%attrs);
            }
            return $node;
        }

        # Handle Return nodes (control/value pattern)
        if ($op eq 'Return') {
            my $control = $node->control;
            my $value = $node->value;
            my $new_control = defined($control) ? $self->_replace_unbound_variables($control, $param_map) : $control;
            my $new_value = defined($value) ? $self->_replace_unbound_variables($value, $param_map) : $value;

            my $ctrl_changed = defined($control) && defined($new_control) && refaddr($new_control) != refaddr($control);
            my $val_changed = defined($value) && defined($new_value) && refaddr($new_value) != refaddr($value);

            if ($ctrl_changed || $val_changed) {
                return Chalk::IR::Node::Return->new(
                    control     => $new_control,
                    value       => $new_value,
                    source_info => $node->can('source_info') ? $node->source_info : undef,
                );
            }
            return $node;
        }

        # Handle unary operators (value pattern for Negate, Not, etc.)
        if ($node->can('value') && !$node->can('control')) {
            my $value = $node->value;
            my $new_value = $self->_replace_unbound_variables($value, $param_map);

            # Compare by refaddr only if both are references
            my $changed = 0;
            if (defined($value) && defined($new_value) && ref($value) && ref($new_value)) {
                $changed = refaddr($new_value) != refaddr($value);
            }
            if ($changed) {
                my $class = ref($node);
                my %attrs = (value => $new_value);
                $attrs{source_info} = $node->source_info if $node->can('source_info');
                return $class->new(%attrs);
            }
            return $node;
        }

        # Handle Call nodes (callee + args)
        if ($op eq 'Call' && $node->can('args')) {
            my $call_args = $node->args // [];
            my @new_args;
            my $changed = 0;
            for my $arg ($call_args->@*) {
                my $new_arg = $self->_replace_unbound_variables($arg, $param_map);
                push @new_args, $new_arg;
                $changed = 1 if defined($arg) && defined($new_arg) && refaddr($new_arg) != refaddr($arg);
            }
            if ($changed) {
                return Chalk::IR::Node::Call->new(
                    callee      => $node->callee,
                    args        => \@new_args,
                    receiver    => $node->can('receiver') ? $node->receiver : undef,
                    source_info => $node->can('source_info') ? $node->source_info : undef,
                );
            }
            return $node;
        }

        # Handle CallEnd nodes (wrap inner Call)
        if ($op eq 'CallEnd' && $node->can('call')) {
            my $inner_call = $node->call;
            my $new_call = $self->_replace_unbound_variables($inner_call, $param_map);
            if (defined($inner_call) && defined($new_call) && refaddr($new_call) != refaddr($inner_call)) {
                use Chalk::IR::Node::CallEnd;
                return Chalk::IR::Node::CallEnd->new(
                    call        => $new_call,
                    source_info => $node->can('source_info') ? $node->source_info : undef,
                );
            }
            return $node;
        }

        # Nodes without children or unhandled patterns - return unchanged
        return $node;
    }
}

1;

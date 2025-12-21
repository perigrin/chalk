# ABOUTME: Semantic action for MethodCall - instance and class method invocations
# ABOUTME: Generates Constructor for ClassName->new() or Call/CallEnd for other methods

use 5.42.0;
use experimental 'class';

class Chalk::Grammar::Chalk::Rule::MethodCall :isa(Chalk::GrammarRule) {
    method evaluate($context) {
        use Chalk::IR::Node::Call;
        use Chalk::IR::Node::CallEnd;
        use Chalk::IR::Node::Constant;
        use Chalk::IR::Node::Constructor;
        use Chalk::Grammar::Chalk::Type::Str;
        use Chalk::Grammar::Chalk::TypeRegistry;

        # MethodCall -> Variable '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # MethodCall -> Variable '->' Identifier  # Without parens
        # MethodCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ExpressionList WS_OPT ')'
        # MethodCall -> QualifiedIdentifier '->' Identifier '(' WS_OPT ')'

        my @children = $context->children->@*;
        my $num_children = scalar(@children);

        # Get receiver (first child - object or class)
        my $receiver = $context->child(0);

        # If receiver is not an IR node, wrap it as Constant
        unless (blessed($receiver) && $receiver->can('id')) {
            my $name = defined($receiver) ? "$receiver" : 'unknown';
            $receiver = Chalk::IR::Node::Constant->new(
                value => $name,
                type => Chalk::Grammar::Chalk::Type::Str->new(),
            );
        }

        # Find method name (after '->')
        # Pattern: receiver '->' method_name [( args )]
        my $callee;
        my $found_arrow = 0;
        for my $i (0 .. $num_children - 1) {
            my $child = $context->child($i);

            # Skip until we find '->'
            if (!$found_arrow) {
                my $focus = $children[$i]->focus if $children[$i]->can('focus');
                if (defined($focus) && "$focus" eq '->') {
                    $found_arrow = 1;
                }
                next;
            }

            # First IR node after '->' is the method name
            if (blessed($child) && $child->can('id')) {
                $callee = $child;
                last;
            }
        }

        # If callee is still not found, try to extract from children directly
        if (!defined($callee)) {
            # Method name is typically child(2) in: receiver '->' method_name
            my $candidate = $context->child(2);
            if (blessed($candidate) && $candidate->can('id')) {
                $callee = $candidate;
            } else {
                # Wrap as constant if needed
                my $name = defined($candidate) ? "$candidate" : 'method';
                $callee = Chalk::IR::Node::Constant->new(
                    value => $name,
                    type => Chalk::Grammar::Chalk::Type::Str->new(),
                );
            }
        }

        # Collect arguments - scan for IR nodes after '('
        my @args;
        my $seen_open_paren = 0;
        for my $i (0 .. $num_children - 1) {
            my $focus = $children[$i]->focus if $children[$i] && $children[$i]->can('focus');

            if (!$seen_open_paren && defined($focus) && "$focus" eq '(') {
                $seen_open_paren = 1;
                next;
            }

            if ($seen_open_paren) {
                my $child = $context->child($i);
                next unless blessed($child) && $child->can('id');
                # Skip callee and receiver which we already have
                next if defined($callee) && $child->id eq $callee->id;
                next if defined($receiver) && $child->id eq $receiver->id;
                push @args, $child;
            }
        }

        # Check if this is a constructor call (ClassName->new())
        # Conditions: receiver is a string constant containing a registered class name,
        # and method name is 'new'
        my $is_constructor = 0;
        my $class_name;

        if (blessed($receiver) && $receiver isa Chalk::IR::Node::Constant) {
            my $potential_class = $receiver->value;
            if (defined($potential_class) && !ref($potential_class)) {
                my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
                if ($registry->has_class($potential_class)) {
                    # Check if method is 'new'
                    my $method_name;
                    if (blessed($callee) && $callee isa Chalk::IR::Node::Constant) {
                        $method_name = $callee->value;
                    }
                    if (defined($method_name) && $method_name eq 'new') {
                        $is_constructor = 1;
                        $class_name = $potential_class;
                    }
                }
            }
        }

        if ($is_constructor) {
            # Parse args as named pairs (key => value)
            my %ctor_args;
            my $i = 0;
            while ($i < @args) {
                my $key_node = $args[$i];
                last unless defined $args[$i + 1];
                my $value_node = $args[$i + 1];

                # Key should be a constant (bareword or string)
                my $key;
                if (blessed($key_node) && $key_node isa Chalk::IR::Node::Constant) {
                    $key = $key_node->value;
                }

                if (defined($key)) {
                    # Prepend $ to make it a field name
                    my $field_name = '$' . $key;
                    $ctor_args{$field_name} = $value_node;
                }

                $i += 2;
            }

            return Chalk::IR::Node::Constructor->new(
                class_name => $class_name,
                args => \%ctor_args,
            );
        }

        # Create Call node with receiver
        my $call = Chalk::IR::Node::Call->new(
            callee   => $callee,
            args     => \@args,
            receiver => $receiver,
        );

        # Create CallEnd node (return this as the expression value)
        my $call_end = Chalk::IR::Node::CallEnd->new(
            call => $call,
        );

        return $call_end;
    }

    # TypeInference semiring: infer type from method/constructor calls
    # Constructors (Class->new()) return Object type
    # Other method calls also return Object type (conservative estimate)
    method infer_type($semiring, $element) {
        use Chalk::Grammar::Chalk::Type::Object;
        use Chalk::Grammar::Chalk::TypeRegistry;

        # Detect if this is a constructor call by examining children
        # Look for pattern: ClassName (Constant) -> 'new' (Constant)
        my @children = $element->children->@*;
        my ($receiver_elem, $method_elem);

        for my $child (@children) {
            next unless $child->can('token');
            my $token = $child->token;
            next unless defined $token;

            # Try to identify receiver and method
            if (!defined $receiver_elem && $token->can('value')) {
                my $val = $token->value;
                # Check if this looks like a class name (registered class)
                if (defined $val && !ref($val)) {
                    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
                    if ($registry->has_class($val)) {
                        $receiver_elem = $child;
                        next;
                    }
                }
            }

            # Look for method name token
            if (!defined $method_elem && $token->can('value')) {
                my $val = $token->value;
                if (defined $val && $val eq 'new') {
                    $method_elem = $child;
                }
            }
        }

        # If this is a constructor call (Class->new()), return Object type
        # For all other method calls, also return Object (methods typically return objects)
        my $type_obj = Chalk::Grammar::Chalk::Type::Object->new();

        return Chalk::Semiring::TypeInferenceElement->new(
            type_obj  => $type_obj,
            type_env  => $element->type_env,
            children  => $element->children,
            token     => $element->token,
            errors    => $element->errors,
            start_pos => $element->start_pos,
            end_pos   => $element->end_pos
        );
    }
}

1;

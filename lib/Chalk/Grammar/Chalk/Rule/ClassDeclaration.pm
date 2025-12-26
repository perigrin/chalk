# ABOUTME: Semantic action for ClassDeclaration rule in Chalk grammar
# ABOUTME: Extracts class name and fields, registers Class type in TypeRegistry
use 5.42.0;
use experimental 'class';
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class
use Chalk::Grammar::Chalk::Type::Class;
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::Grammar::Chalk::TypeRegistry;

class Chalk::Grammar::Chalk::Rule::ClassDeclaration :isa(Chalk::GrammarRule) {

    # Helper to extract field name and attributes from VariableDeclaration context
    # Returns: { name => $field_name, attributes => \@attr_list } or undef
    sub _extract_field_from_vardecl($ctx) {

        # Get the children to find LexicalDeclarator and Variable
        my @children = $ctx->children->@*;

        # First child should be LexicalDeclarator
        return undef unless @children > 0;

        my $declarator_ctx = $children[0];
        my $declarator_val = $declarator_ctx->extract();

        # Check if it's 'field'
        return undef unless (defined $declarator_val && "$declarator_val" eq 'field');

        # Find the Variable child (should be at index 2: LexicalDeclarator WS_OPT Variable)
        return undef unless @children > 2;

        my $var_ctx = $children[2];
        my $field_name;

        # Get Variable rule and extract the variable name
        if ($var_ctx->can('rule') && $var_ctx->rule &&
            $var_ctx->rule isa Chalk::Grammar::Chalk::Rule::Variable) {
            # Variable returns UnboundVariable with name() method
            my $var_val = $var_ctx->extract();
            if ($var_val && $var_val->can('name')) {
                # name() returns full name with sigil (e.g., '$x')
                $field_name = $var_val->name;
            }
        }

        return undef unless defined $field_name;

        # Extract attributes if present (index 4 or later: Variable WS_OPT AttributeList)
        my @attributes;
        for my $i (3 .. $#children) {
            my $child = $children[$i];
            next unless $child->can('rule') && $child->rule;

            # Check for AttributeList
            if ($child->rule isa Chalk::Grammar::Chalk::Rule::AttributeList) {
                push @attributes, _extract_attributes_from_list($child);
            }
            # Check for single Attribute
            elsif ($child->rule isa Chalk::Grammar::Chalk::Rule::Attribute) {
                my $attr = $child->extract();
                push @attributes, "$attr" if defined $attr;
            }
        }

        return { name => $field_name, attributes => \@attributes };
    }

    # Helper to extract attribute names from AttributeList context
    sub _extract_attributes_from_list($ctx) {
        my @attrs;

        return @attrs unless defined $ctx;

        # AttributeList -> Attribute | Attribute WS_OPT AttributeList
        my @children = $ctx->children->@*;

        for my $child (@children) {
            next unless $child->can('rule') && $child->rule;

            if ($child->rule isa Chalk::Grammar::Chalk::Rule::Attribute) {
                my $attr = $child->extract();
                push @attrs, "$attr" if defined $attr;
            }
            elsif ($child->rule isa Chalk::Grammar::Chalk::Rule::AttributeList) {
                push @attrs, _extract_attributes_from_list($child);
            }
        }

        # Also check if this context itself is an Attribute
        if ($ctx->can('rule') && $ctx->rule &&
            $ctx->rule isa Chalk::Grammar::Chalk::Rule::Attribute) {
            my $attr = $ctx->extract();
            push @attrs, "$attr" if defined $attr;
        }

        return @attrs;
    }

    # Helper to recursively extract field declarations from parse tree contexts
    # Returns array of hashrefs: { name => $field_name, type => $type_obj, attributes => \@attrs, has_default => bool }
    sub _extract_fields_from_context($ctx) {
        my @fields;

        return @fields unless defined $ctx;
        return @fields unless blessed($ctx);

        my $skip_children = 0;

        # Check if this context's rule is a VariableDeclaration or Assignment
        if ($ctx->can('rule') && $ctx->rule) {
            my $rule = $ctx->rule;

            # Pattern 2: Assignment where LHS is VariableDeclaration with 'field'
            # Example: field $count = 0;
            # Check this FIRST to avoid double-counting the nested VariableDeclaration
            if ($rule isa Chalk::Grammar::Chalk::Rule::Assignment) {
                # Get the LHS (first child, before '=')
                my @children = $ctx->children->@*;
                if (@children > 0) {
                    my $lhs_ctx = $children[0];

                    # Check if LHS is a VariableDeclaration
                    if ($lhs_ctx->can('rule') && $lhs_ctx->rule &&
                        $lhs_ctx->rule isa Chalk::Grammar::Chalk::Rule::VariableDeclaration) {
                        my $field_info = _extract_field_from_vardecl($lhs_ctx);
                        if (defined $field_info) {
                            # Type inference deferred to issue #332 (Chalk type system integration)
                            # For now, all field types default to Any
                            push @fields, {
                                name => $field_info->{name},
                                type => undef,
                                attributes => $field_info->{attributes},
                                has_default => 1,
                            };
                            # Don't recurse into this Assignment's children to avoid double-counting
                            $skip_children = 1;
                        }
                    }
                }
            }
            # Pattern 1: Standalone VariableDeclaration with 'field' declarator
            # Example: field $x;
            elsif ($rule isa Chalk::Grammar::Chalk::Rule::VariableDeclaration) {
                my $field_info = _extract_field_from_vardecl($ctx);
                if (defined $field_info) {
                    # No initializer, type is Any
                    push @fields, {
                        name => $field_info->{name},
                        type => undef,
                        attributes => $field_info->{attributes},
                        has_default => 0,
                    };
                }
            }
        }

        # Recursively check all children (unless we found a field in an Assignment)
        unless ($skip_children) {
            if ($ctx->can('children')) {
                for my $child ($ctx->children->@*) {
                    push @fields, _extract_fields_from_context($child);
                }
            }
        }

        return @fields;
    }

    # Helper to find children matching a condition
    sub _find_child_matching($context, $predicate) {
        my @children = $context->children->@*;

        for my $i (0..$#children) {
            my $child = $context->child($i);
            return ($child, $i) if $predicate->($child, $i);
        }

        return (undef, -1);
    }

    # Helper to extract ADJUST blocks from parse tree context
    # Returns array of hashrefs: { statements => [...], assigns => { '$field' => node } }
    sub _extract_adjust_blocks_from_context($ctx) {
        my @adjusts;

        return @adjusts unless defined $ctx;
        return @adjusts unless blessed($ctx);

        # Check if this context is an AdjustBlock
        if ($ctx->can('rule') && $ctx->rule) {
            my $rule = $ctx->rule;

            if ($rule isa Chalk::Grammar::Chalk::Rule::AdjustBlock) {
                # Evaluate the ADJUST block to get its statements
                my $adjust_result = $ctx->extract();
                if (ref($adjust_result) eq 'HASH' && $adjust_result->{type} eq 'adjust') {
                    push @adjusts, {
                        statements => $adjust_result->{statements} // [],
                        assigns => {},  # Will be populated by later analysis
                    };
                }
            }
        }

        # Recursively check all children
        if ($ctx->can('children')) {
            for my $child ($ctx->children->@*) {
                push @adjusts, _extract_adjust_blocks_from_context($child);
            }
        }

        return @adjusts;
    }

    method evaluate($context) {
        # ClassDeclaration -> 'class' WS_OPT QualifiedIdentifier WS_OPT Block
        # ClassDeclaration -> 'class' WS_OPT QualifiedIdentifier WS_OPT AttributeList WS_OPT Block

        # Get child contexts (not extracted values)
        my @child_contexts = $context->children->@*;

        # Extract class name from child 2: 'class' WS_OPT QualifiedIdentifier
        # QualifiedIdentifier returns a Token, so we need to stringify it
        my $class_name_token = $child_contexts[2]->extract();
        my $class_name = "$class_name_token";  # Stringify Token

        unless (defined $class_name && $class_name ne '') {
            die "ClassDeclaration: expected class name as child 2, got: " .
                (ref($class_name_token) || (defined $class_name_token ? "'$class_name_token'" : 'undef'));
        }

        # Check if TypeInference already registered this class (Composite mode)
        # In Composite mode, TypeInference runs first and registers with proper field types
        # We skip re-registration to avoid conflict and preserve the inferred types
        my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
        if ($registry->is_complete($class_name)) {
            return undef;
        }

        # Find the Block context (last child)
        my $block_ctx = $child_contexts[$#child_contexts];

        # Extract field declarations from the block context (not the evaluated block)
        # Returns array of hashrefs: { name => $field_name, type => $type_obj, attributes => \@attrs, has_default => bool }
        my @field_info = _extract_fields_from_context($block_ctx);

        # Get type_env from context (set by TypeInference via Composite integration)
        # This allows us to use inferred field types instead of defaulting to Any
        my $type_env = $context->env->{type_env} // {};

        # Build field hash: field_name => Type (use type_env or default to Any)
        # Also build param_fields array for :param fields
        my %fields;
        my @param_fields;
        my $any_type = Chalk::Grammar::Chalk::Type::Any->new();
        for my $info (@field_info) {
            my $field_name = $info->{name};
            # First try type_env (from TypeInference), then field info, then Any
            my $field_type = $type_env->{$field_name} // $info->{type} // $any_type;
            # Field names come as scalars like '$x', '$y', etc.
            $fields{$field_name} = $field_type;

            # Check if field has :param attribute
            my @attrs = ($info->{attributes} // [])->@*;
            if (grep { $_ eq ':param' } @attrs) {
                push @param_fields, {
                    name => $field_name,
                    required => !$info->{has_default},
                };
            }
        }

        # Extract ADJUST blocks from the class body
        my @adjust_blocks = _extract_adjust_blocks_from_context($block_ctx);

        # Create Class type object
        my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
            class_name => $class_name,
            fields     => \%fields,
            param_fields => \@param_fields,
            adjust_blocks => \@adjust_blocks,
        );

        # Register in TypeRegistry
        $registry->register($class_name, $class_type);

        # Return undef for now (we don't need IR generation for type registration)
        # This is called during type analysis phase, not IR generation
        return undef;
    }

    # Type inference for TypeInference semiring
    # Extracts class name and field types from TypeInferenceElement tree
    # Registers class with inferred field types in TypeRegistry
    method infer_type($semiring, $element) {
        # ClassDeclaration -> 'class' WS_OPT QualifiedIdentifier WS_OPT Block
        # ClassDeclaration -> 'class' WS_OPT QualifiedIdentifier WS_OPT AttributeList WS_OPT Block
        #
        # TypeInference element structure differs from Semantic context:
        # - Root element has token='class' from first scan
        # - Children are: [WS_OPT, QualifiedIdentifier, WS_OPT, Block] (for basic form)
        # So QualifiedIdentifier is at index 1, not 2

        my @children = $element->children->@*;

        # Extract class name from QualifiedIdentifier (child 1 in TypeInference elements)
        # The token might be stored in the element or we need to traverse
        my $class_name = _extract_class_name_from_element($children[1]);
        return $element unless defined $class_name && $class_name ne '';

        # Find the Block element (last child)
        my $block_element = $children[$#children];

        # Extract field declarations with types from the Block element tree
        my @field_info = _extract_fields_from_element($block_element);

        # Build field hash: field_name => Type (use inferred type or default to Any)
        # When a field appears multiple times (e.g., from both assignment and standalone detection),
        # prefer the entry with a specific type over entries with undef (Any)
        my %fields;
        my $any_type = Chalk::Grammar::Chalk::Type::Any->new();
        for my $info (@field_info) {
            my $field_name = $info->{name};
            my $field_type = $info->{type} // $any_type;

            # Skip if we already have a non-Any type for this field
            if (exists $fields{$field_name}) {
                next unless defined $info->{type};  # Skip undef entries if we have anything
                next if $fields{$field_name}->name ne 'Any';  # Keep existing non-Any type
            }
            $fields{$field_name} = $field_type;
        }

        # Create Class type object
        my $class_type = Chalk::Grammar::Chalk::Type::Class->new(
            class_name => $class_name,
            fields     => \%fields
        );

        # Register in TypeRegistry
        my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
        $registry->register($class_name, $class_type);

        # Return element unchanged (type inference doesn't modify the element's type)
        return $element;
    }

    # Helper to extract class name from QualifiedIdentifier element
    sub _extract_class_name_from_element($elem) {
        return undef unless defined $elem;

        # Check if this element has a token with the identifier
        if ($elem->can('token') && defined $elem->token) {
            return $elem->token->value;
        }

        # BFS through children to find a token with IDENTIFIER pattern
        my @queue = defined $elem->children ? ($elem->children->@*) : ();
        while (@queue) {
            my $child = shift @queue;
            next unless defined $child;

            if ($child->can('token') && defined $child->token) {
                my $token = $child->token;
                if ($token->can('pattern_name') && defined $token->pattern_name) {
                    if ($token->pattern_name eq 'IDENTIFIER') {
                        return $token->value;
                    }
                }
                # If no pattern name, try using the token value directly
                return $token->value if defined $token->value;
            }

            # Continue BFS
            push @queue, ($child->children->@*) if $child->can('children') && defined $child->children;
        }

        return undef;
    }

    # Helper to extract field declarations from TypeInferenceElement tree
    # Returns array of hashrefs: { name => $field_name, type => $type_obj }
    sub _extract_fields_from_element($elem) {
        my @fields;

        return @fields unless defined $elem;

        # Get children if available
        my @children = $elem->can('children') && defined $elem->children ? ($elem->children->@*) : ();

        # Check for Assignment pattern: element's own token is '='
        # TypeInference stores the operator as the element's token, children are [LHS, WS*, RHS]
        if ($elem->can('token') && defined $elem->token) {
            my $tok_val = $elem->token->value // '';
            if ($tok_val eq '=') {
                # Check if LHS (first child) contains 'field' declarator
                my $field_name = _extract_field_name_from_lhs($children[0]) if @children > 0;
                if (defined $field_name) {
                    # Get RHS type (last child typically contains the value)
                    my $rhs_elem = $children[$#children] if @children > 0;
                    my $rhs_type = _infer_type_from_element($rhs_elem);
                    push @fields, { name => $field_name, type => $rhs_type };
                }
            }
        }

        # Check for standalone VariableDeclaration (field without initializer)
        # Look for 'field' token followed by variable
        my $field_name = _extract_standalone_field_name($elem);
        if (defined $field_name) {
            # Check if we haven't already added this field with an initializer
            my %existing = map { $_->{name} => 1 } @fields;
            unless ($existing{$field_name}) {
                push @fields, { name => $field_name, type => undef };
            }
        }

        # Recurse through children
        for my $child (@children) {
            push @fields, _extract_fields_from_element($child);
        }

        return @fields;
    }

    # Helper to extract field name from LHS of assignment
    sub _extract_field_name_from_lhs($elem) {
        return undef unless defined $elem;

        # BFS to find 'field' token followed by variable identifier
        my @queue = ($elem);
        my $found_field = 0;
        my $var_name;

        while (@queue) {
            my $child = shift @queue;
            next unless defined $child;

            if ($child->can('token') && defined $child->token) {
                my $val = $child->token->value // '';
                if ($val eq 'field') {
                    $found_field = 1;
                }
                # Look for identifier-like token after finding 'field'
                # Accept IDENTIFIER, BAREWORD, BAREWORD_ANY patterns
                if ($found_field && !defined $var_name && $val ne 'field') {
                    my $pattern = $child->token->can('pattern_name') ? ($child->token->pattern_name // '') : '';
                    if ($pattern =~ /^(?:IDENTIFIER|BAREWORD|BAREWORD_ANY)$/) {
                        $var_name = '$' . $child->token->value;
                    }
                }
            }

            push @queue, ($child->children->@*) if $child->can('children') && defined $child->children;
        }

        return $found_field ? $var_name : undef;
    }

    # Helper to extract standalone field name (field without initializer)
    sub _extract_standalone_field_name($elem) {
        return undef unless defined $elem;

        # Look for pattern: 'field' WS '$' Identifier ';'
        # This is a simplified check
        my @children = $elem->can('children') && defined $elem->children ? ($elem->children->@*) : ();
        return undef if @children < 3;

        # Check first child for 'field'
        my $first = $children[0];
        if ($first && $first->can('token') && defined $first->token) {
            my $val = $first->token->value // '';
            if ($val eq 'field') {
                # BFS to find the variable name
                for my $child (@children[1..$#children]) {
                    my $name = _find_identifier_in_element($child);
                    return '$' . $name if defined $name;
                }
            }
        }

        return undef;
    }

    # Helper to find identifier token in element tree
    sub _find_identifier_in_element($elem) {
        return undef unless defined $elem;

        if ($elem->can('token') && defined $elem->token) {
            my $pattern = $elem->token->can('pattern_name') ? ($elem->token->pattern_name // '') : '';
            # Accept IDENTIFIER, BAREWORD, BAREWORD_ANY patterns
            if ($pattern =~ /^(?:IDENTIFIER|BAREWORD|BAREWORD_ANY)$/) {
                return $elem->token->value;
            }
        }

        my @children = $elem->can('children') && defined $elem->children ? ($elem->children->@*) : ();
        for my $child (@children) {
            my $found = _find_identifier_in_element($child);
            return $found if defined $found;
        }

        return undef;
    }

    # Helper to infer type from element
    sub _infer_type_from_element($elem) {
        return Chalk::Grammar::Chalk::Type::Any->new() unless defined $elem;

        # First check if the element has a type_obj
        if ($elem->can('type_obj') && defined $elem->type_obj) {
            my $type = $elem->type_obj;
            # Map type names to Grammar types if needed
            my $name = $type->can('name') ? $type->name : '';

            return Chalk::Grammar::Chalk::Type::Int->new() if $name eq 'Int';
            return Chalk::Grammar::Chalk::Type::Num->new() if $name eq 'Num';
            return Chalk::Grammar::Chalk::Type::Str->new() if $name eq 'Str';

            # Return as-is if it's already a Grammar type
            return $type if $type isa Chalk::Grammar::Chalk::Type::Int;
            return $type if $type isa Chalk::Grammar::Chalk::Type::Num;
            return $type if $type isa Chalk::Grammar::Chalk::Type::Str;
            return $type if $type isa Chalk::Grammar::Chalk::Type::ArrayRef;
            return $type if $type isa Chalk::Grammar::Chalk::Type::HashRef;
        }

        # Recurse through children to find a typed element
        my @children = $elem->can('children') && defined $elem->children ? ($elem->children->@*) : ();
        for my $child (@children) {
            my $type = _infer_type_from_element($child);
            return $type unless $type->name eq 'Any';
        }

        return Chalk::Grammar::Chalk::Type::Any->new();
    }
}

1;

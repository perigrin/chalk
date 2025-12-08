# ABOUTME: Semantic action for ClassDeclaration rule in Chalk grammar
# ABOUTME: Extracts class name and fields, registers Class type in TypeRegistry
use 5.42.0;
use experimental 'class';
use Chalk::Grammar;  # Provides Chalk::GrammarRule base class

class Chalk::Grammar::Chalk::Rule::ClassDeclaration :isa(Chalk::GrammarRule) {
    use Scalar::Util 'blessed';
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Any;

    # Helper to extract field name from VariableDeclaration context
    sub _extract_field_from_vardecl {
        my ($ctx, $indent) = @_;
        $indent //= "";

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

        # Get Variable rule and extract the variable name
        if ($var_ctx->can('rule') && $var_ctx->rule &&
            $var_ctx->rule->isa('Chalk::Grammar::Chalk::Rule::Variable')) {
            # Variable returns a hash with type and name
            my $var_val = $var_ctx->extract();
            if (ref($var_val) eq 'HASH' &&
                $var_val->{type} eq 'scalar_var' &&
                exists $var_val->{name}) {
                # Prepend sigil to name for field storage
                my $field_name = $var_val->{sigil} . $var_val->{name};
                return $field_name;
            }
        }

        return undef;
    }

    # Helper to recursively extract field declarations from parse tree contexts
    # Returns array of hashrefs: { name => $field_name, type => $type_obj }
    sub _extract_fields_from_context {
        my ($ctx, $depth) = @_;
        $depth //= 0;
        my @fields;

        return @fields unless defined $ctx;
        return @fields unless blessed($ctx);

        # Check if this context's rule is a VariableDeclaration or Assignment
        if ($ctx->can('rule') && $ctx->rule) {
            my $rule = $ctx->rule;

            # Pattern 1: Standalone VariableDeclaration with 'field' declarator
            # Example: field $x;
            if ($rule->isa('Chalk::Grammar::Chalk::Rule::VariableDeclaration')) {
                my $field_name = _extract_field_from_vardecl($ctx);
                if (defined $field_name) {
                    # No initializer, type is Any
                    push @fields, { name => $field_name, type => undef };
                }
            }
            # Pattern 2: Assignment where LHS is VariableDeclaration with 'field'
            # Example: field $count = 0;
            elsif ($rule->isa('Chalk::Grammar::Chalk::Rule::Assignment')) {
                # Get the LHS (first child, before '=')
                my @children = $ctx->children->@*;
                if (@children > 0) {
                    my $lhs_ctx = $children[0];

                    # Check if LHS is a VariableDeclaration
                    if ($lhs_ctx->can('rule') && $lhs_ctx->rule &&
                        $lhs_ctx->rule->isa('Chalk::Grammar::Chalk::Rule::VariableDeclaration')) {
                        my $field_name = _extract_field_from_vardecl($lhs_ctx);
                        if (defined $field_name) {
                            # Type inference deferred to issue #332 (Chalk type system integration)
                            # For now, all field types default to Any
                            push @fields, { name => $field_name, type => undef };
                        }
                    }
                }
            }
        }

        # Recursively check all children
        if ($ctx->can('children')) {
            for my $child ($ctx->children->@*) {
                push @fields, _extract_fields_from_context($child, $depth + 1);
            }
        }

        return @fields;
    }

    # Helper to find children matching a condition
    sub _find_child_matching {
        my ($context, $predicate) = @_;
        my @children = $context->children->@*;

        for my $i (0..$#children) {
            my $child = $context->child($i);
            return ($child, $i) if $predicate->($child, $i);
        }

        return (undef, -1);
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

        # Find the Block context (last child)
        my $block_ctx = $child_contexts[$#child_contexts];

        # Extract field declarations from the block context (not the evaluated block)
        # Returns array of hashrefs: { name => $field_name, type => $type_obj }
        my @field_info = _extract_fields_from_context($block_ctx);

        # Build field hash: field_name => Type (use inferred type or default to Any)
        my %fields;
        my $any_type = Chalk::Grammar::Chalk::Type::Any->new();
        for my $info (@field_info) {
            my $field_name = $info->{name};
            my $field_type = $info->{type} // $any_type;
            # Field names come as scalars like '$x', '$y', etc.
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

        # Return undef for now (we don't need IR generation for type registration)
        # This is called during type analysis phase, not IR generation
        return undef;
    }
}

1;

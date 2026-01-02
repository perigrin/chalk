# ABOUTME: Semantic action for UseStatement - categorizes use statements and builds UseStatement IR nodes
# ABOUTME: UseStatement handles version checks, pragmas, modules, and external modules

use 5.42.0;
use experimental 'class';
use Chalk::Grammar;
use Chalk::IR::Node;

class Chalk::Grammar::Chalk::Rule::UseStatement :isa(Chalk::GrammarRule) {

    # Categorize use statement into: version, pragma, module, or external
    sub _categorize_use_statement($module_name) {

        # Version check: use 5.42.0;
        # Check if first char is digit (simple version detection)
        my $first_char = substr( $module_name, 0, 1 );
        if ( $first_char ge '0' && $first_char le '9' ) {
            return 'version';
        }

     # Pragma: use experimental qw(...);
     # Known pragmas that are no-ops for Chalk (Chalk provides these by default)
        if (   $module_name eq 'strict'
            || $module_name eq 'warnings'
            || $module_name eq 'utf8'
            || $module_name eq 'experimental'
            || $module_name eq 'feature' )
        {
            return 'pragma';
        }

        # Chalk module: use Chalk::IR::Node;
        # Check if module starts with 'Chalk::'
        if ( substr( $module_name, 0, 7 ) eq 'Chalk::' ) {
            return 'module';
        }

        # Everything else is external (builtin, Carp, etc.)
        return 'external';
    }

    # Extract import list from QuotedWordList child
    # QuotedWordList is qw(...) or qw/.../
    sub _extract_imports( $context, $start_index ) {
        my @imports = ();

        # Look for QuotedWordList child after the module name
        my $children       = $context->children;
        my @children_array = $children->@*;
        for my $i ( $start_index .. $#children_array ) {
            my $child = $context->child($i);
            next unless defined $child;

            # Check if this is a QuotedWordList
            if ( ref($child) eq 'ARRAY' ) {

                # QuotedWordList semantic value is array ref of import names
                @imports = $child->@*;
                last;
            }
            elsif ( blessed($child)
                && $child->can('type')
                && $child->type eq 'quoted_word_list' )
            {
                # Alternative representation
                @imports = $child->words->@* if $child->can('words');
                last;
            }
        }

        return \@imports;
    }

    method evaluate($context) {

# UseStatement grammar rules:
# UseStatement -> 'use' WS_OPT Number                                    # use 5.42.0
# UseStatement -> 'use' WS_OPT QualifiedIdentifier                       # use Module
# UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT QuotedWordList # use Module qw(...)
# UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT String         # use experimental 'class'
# UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT ExpressionList # use overload ... => ...

        my @children = $context->children->@*;
        my $scope = $context->env->{scope};

        # No scope means we're just parsing without IR generation
        die "UseStatement: scope required for IR generation - grammar bug" unless $scope;

        # Find the module name or version number (after 'use' and optional WS)
        my $module_name;
        my $module_index = -1;

        for my $i ( 0 .. $#children ) {
            my $child = $children[$i]->extract;

            # Skip 'use' keyword and whitespace/empty values
            next if !defined($child) || $child eq 'use' || $child eq '';

            # This should be the module name or version
            if ( defined($child) ) {
                # If child is an IR node (e.g., Constant from Number),
                # extract the value from its attributes
                if ( ref($child) && $child->can('op') && $child->op eq 'Constant' ) {
                    $module_name = $child->value;
                } else {
                    $module_name = $child;
                }
                $module_index = $i;
                last;
            }

           # Alternative: child is already extracted value (QualifiedIdentifier)
            elsif ( ref($child) eq 'HASH'
                && $child->{type} eq 'qualified_identifier' )
            {
                $module_name  = $child->{name};
                $module_index = $i;
                last;
            }
        }

        # If we can't find a module name, that's a grammar bug
        die "UseStatement: could not find module name - grammar bug" unless defined($module_name);

        # Get current control flow from scope
        # For use overload directives in class bodies, current_control may not be set yet
        # since class bodies don't have a control flow context during parsing
        my $current_control = $scope->current_control;

        # Special handling for 'use overload'
        if ($module_name eq 'overload') {
            warn "DEBUG UseStatement: Processing use overload, current_control=" . (defined $current_control ? "defined" : "undef") . "\n" if $ENV{DEBUG_OVERLOAD};
            # Extract operator => method mappings from ExpressionList
            my %mappings;
            my $fallback = 0;

            # Find the ExpressionList child (after WS following the module name)
            # UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT ExpressionList
            my $expression_list;
            for my $i ($module_index + 1 .. $#children) {
                my $child = $children[$i]->extract;
                if (ref($child) && $child->can('op') && $child->op eq 'List') {
                    $expression_list = $child;
                    last;
                }
            }

            unless ($expression_list) {
                # Return empty mappings
                my $attributes = {
                    type     => 'overload_directive',
                    module   => 'overload',
                    mappings => {},
                    fallback => 0,
                };
                my $node_id  = "use_overload_directive";
                my $use_stmt = Chalk::IR::Node->new(
                    id         => $node_id,
                    op         => 'UseStatement',
                    inputs     => $current_control ? [$current_control] : [],
                    attributes => $attributes,
                );
                return $use_stmt;
            }

            # ExpressionList is represented as a List IR node with elements
            my $elements = $expression_list->elements || [];

            my $i = 0;
            while ($i < @$elements) {
                my $left = $elements->[$i];
                my $arrow = $elements->[$i + 1];
                my $right = $elements->[$i + 2];

                # Skip if we don't have a complete triple
                last unless defined($left) && defined($arrow) && defined($right);

                # Check if this is a fat comma pair (left => right)
                if (defined($arrow) && $arrow eq '=>') {
                    # Extract the operator (left side)
                    my $operator = $left;
                    if (ref($left) && $left->can('op') && $left->op eq 'Constant') {
                        $operator = $left->value;
                    }

                    # Extract the method name (right side)
                    my $method = $right;
                    if (ref($right) && $right->can('op') && $right->op eq 'Constant') {
                        $method = $right->value;
                    }

                    # Handle fallback specially
                    if ($operator eq 'fallback') {
                        $fallback = $method;
                    } else {
                        $mappings{$operator} = $method;
                    }

                    # Skip past this pair (operator, =>, method)
                    $i += 3;

                    # Skip comma if present
                    if ($i < @$elements) {
                        my $maybe_comma = $elements->[$i];
                        if (defined($maybe_comma) && $maybe_comma eq ',') {
                            $i++;
                        }
                    }
                } else {
                    # Not a fat comma, skip this element
                    $i++;
                }
            }

            if ($ENV{DEBUG_OVERLOAD}) {
                warn "DEBUG: use overload - extracted " . scalar(keys %mappings) . " mappings: "
                    . join(", ", map { "$_ => $mappings{$_}" } sort keys %mappings)
                    . ", fallback=$fallback\n";
            }

            # Create overload directive node
            my $attributes = {
                type     => 'overload_directive',
                module   => 'overload',
                mappings => \%mappings,
                fallback => $fallback,
            };

            my $node_id  = "use_overload_directive";
            # If we have current_control, create a proper IR node with control flow
            # Otherwise, create a metadata-only node for class-level use overload
            my $use_stmt = Chalk::IR::Node->new(
                id         => $node_id,
                op         => 'UseStatement',
                inputs     => $current_control ? [$current_control] : [],
                attributes => $attributes,
            );


            $use_stmt->record_transform(
                'ir_construction',
                'UseStatement::evaluate',
                context => "type=overload_directive, mappings=" . join(", ", map { "$_ => $mappings{$_}" } keys %mappings)
            );

            # Update scope's control to thread UseStatement into control flow (if we have control)
            if ($current_control) {
                my $new_scope = $scope->with_control($use_stmt);
                $context->env->{scope} = $new_scope;
            }

            return $use_stmt;
        }

        # Regular use statement (not overload)
        # Categorize the use statement
        my $type = _categorize_use_statement($module_name);

        # Extract import list if present
        my $imports = _extract_imports( $context, $module_index + 1 );

        # Create UseStatement IR node directly
        my $attributes = {
            type    => $type,
            module  => $module_name,
            imports => $imports
        };

        # If we don't have current_control, this means we're in a class body or similar context
        # For now, we'll return undef for non-overload use statements in such contexts
        # (they don't affect class structure)
        return undef unless $current_control;

        my $node_id  = "use_${type}_${module_name}";
        my $use_stmt = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'UseStatement',
            inputs     => [$current_control],
            attributes => $attributes,
        );

        # See issue #202 - record_transform mutates node after construction
        my $import_list = join( ", ", $imports->@* );
        $use_stmt->record_transform(
            'ir_construction',
            'UseStatement::evaluate',
            context => "type=$type, module=$module_name, imports=[$import_list]"
        );

        # Update scope's control to thread UseStatement into control flow
        my $new_scope = $scope->with_control($use_stmt);
        $context->env->{scope} = $new_scope;

        return $use_stmt;
    }
}

1;

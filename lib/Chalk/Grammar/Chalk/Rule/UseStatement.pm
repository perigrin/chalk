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
                    # Unwrap nested Constant objects
                    while (ref($module_name) && $module_name->can('value')) {
                        $module_name = $module_name->value;
                    }
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
            if ($ENV{DEBUG_OVERLOAD}) {
                warn "DEBUG UseStatement: module_index=$module_index, children count=" . scalar(@children) . "\n";
                warn "DEBUG UseStatement: Context rule: " . (ref($context->rule) || 'no-rule') . "\n";
                for my $i (0 .. $#children) {
                    my $child = $children[$i]->extract;
                    my $child_ctx = $children[$i];
                    my $child_rule = $child_ctx->can('rule') ? $child_ctx->rule : undef;
                    my $rule_desc = $child_rule ? ref($child_rule) : 'no-rule';
                    my $desc = !defined($child) ? 'undef' :
                               ref($child) ? (blessed($child) ? blessed($child) . " op=" . ($child->can('op') ? $child->op : 'N/A') : ref($child)) :
                               "'$child'";
                    warn "DEBUG UseStatement: child[$i] = $desc (rule=$rule_desc)\n";
                }
            }
            # Extract operator => method mappings from ExpressionList
            my %mappings;
            my $fallback = 0;

            # Find the ExpressionList child (after WS following the module name)
            # UseStatement -> 'use' WS_OPT QualifiedIdentifier WS_OPT ExpressionList
            my $expression_list;
            for my $i ($module_index + 1 .. $#children) {
                my $child = $children[$i]->extract;
                if ($ENV{DEBUG_OVERLOAD}) {
                    my $desc = !defined($child) ? 'undef' :
                               ref($child) ? (blessed($child) ? blessed($child) . " op=" . ($child->can('op') ? $child->op : 'N/A') : ref($child)) :
                               "'$child'";
                    warn "DEBUG UseStatement: Checking child[$i] for ExpressionList: $desc\n";
                    if (ref($child) && blessed($child)) {
                        warn "DEBUG UseStatement:   blessed check: " . (blessed($child) ? "YES" : "NO") . "\n";
                        warn "DEBUG UseStatement:   can('op'): " . ($child->can('op') ? "YES" : "NO") . "\n";
                        if ($child->can('op')) {
                            warn "DEBUG UseStatement:   op value: '" . $child->op . "'\n";
                            warn "DEBUG UseStatement:   op eq 'List': " . ($child->op eq 'List' ? "YES" : "NO") . "\n";
                        }
                    }
                }
                if (ref($child) && $child->can('op') && $child->op eq 'List') {
                    $expression_list = $child;
                    last;
                }
            }

            unless ($expression_list) {
                if ($ENV{DEBUG_OVERLOAD}) {
                    warn "DEBUG UseStatement: No ExpressionList found, returning empty mappings\n";
                }
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
            # Fat comma pairs like '""' => 'value' are represented as pairs of Constant nodes
            # The '=>' token is filtered out by ExpressionList.evaluate()
            my $elements = $expression_list->elements || [];

            if ($ENV{DEBUG_OVERLOAD}) {
                warn "DEBUG UseStatement: ExpressionList has " . scalar(@$elements) . " elements\n";
                for my $i (0 .. $#$elements) {
                    my $elem = $elements->[$i];
                    my $desc = ref($elem) ? (blessed($elem) ? blessed($elem) . " op=" . ($elem->can('op') ? $elem->op : 'N/A') : ref($elem)) : "'$elem'";
                    warn "DEBUG UseStatement:   element[$i]: $desc\n";
                }
            }

            # Iterate through elements in pairs (operator, method)
            for (my $i = 0; $i < @$elements; $i += 2) {
                my $left = $elements->[$i];
                my $right = $elements->[$i + 1];

                if ($ENV{DEBUG_OVERLOAD}) {
                    my $left_desc = !defined($left) ? 'undef' : (ref($left) ? blessed($left) : "'$left'");
                    my $right_desc = !defined($right) ? 'undef' : (ref($right) ? blessed($right) : "'$right'");
                    warn "DEBUG UseStatement: Pair $i: left=$left_desc, right=$right_desc\n";
                }

                # Skip incomplete pairs
                last unless defined($left) && defined($right);

                # Extract the operator (left side) - should be a Constant
                my $operator = $left;
                if (ref($left) && $left->can('op') && $left->op eq 'Constant') {
                    # Access the value field directly from attributes hash
                    # This avoids any stringification that might happen with the value() method
                    my $attrs = $left->attributes;
                    $operator = $attrs->{value};

                    # Handle nested Constant (Constant->value might be another Constant)
                    # Keep unwrapping until we get a non-Constant value
                    my $unwrap_count = 0;
                    while (ref($operator) && $operator->can('value')) {
                        my $old_attrs = $operator->attributes;
                        $operator = $old_attrs->{value};
                        $unwrap_count++;
                        last if $unwrap_count > 10;  # Safety limit
                    }
                }

                # Extract the method name (right side) - should be a Constant
                my $method = $right;
                if (ref($right) && $right->can('op') && $right->op eq 'Constant') {
                    # Access the value field directly from attributes hash
                    my $right_attrs = $right->attributes;
                    $method = $right_attrs->{value};

                    # Handle nested Constant - keep unwrapping until we get a non-Constant value
                    my $method_unwrap_count = 0;
                    while (ref($method) && $method->can('value')) {
                        my $method_attrs = $method->attributes;
                        $method = $method_attrs->{value};
                        $method_unwrap_count++;
                        last if $method_unwrap_count > 10;  # Safety limit
                    }
                }

                # Handle fallback specially
                if ($operator eq 'fallback') {
                    $fallback = $method;
                    if ($ENV{DEBUG_OVERLOAD}) {
                        warn "DEBUG UseStatement: Set fallback=$method\n";
                    }
                } else {
                    $mappings{$operator} = $method;
                    if ($ENV{DEBUG_OVERLOAD}) {
                        warn "DEBUG UseStatement: Added mapping: '$operator' => '$method'\n";
                        warn "DEBUG UseStatement: Total mappings now: " . scalar(keys %mappings) . "\n";
                    }
                }
            }

            # Create overload directive node
            my $attributes = {
                type     => 'overload_directive',
                module   => 'overload',
                mappings => \%mappings,
                fallback => $fallback,
            };

            my $node_id  = "use_overload_directive_" . scalar(keys %mappings) . "_mappings";
            if ($ENV{DEBUG_OVERLOAD}) {
                warn "DEBUG UseStatement: Creating node with id=$node_id\n";
            }
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

    # Type inference: UseStatement is a compile-time directive, not a runtime expression
    # Skip type checking entirely - return element unchanged
    method infer_type($semiring, $element) {
        return $element;
    }

    # Semantic validation: UseStatement must be properly terminated
    # UseStatement is a statement, not an expression, so it must end with:
    # - Semicolon (statement terminator)
    # - Closing brace (end of block)
    # - NOT another expression (which would indicate incomplete ExpressionList)
    method validate($semiring, $element, $input_text) {
        my $end_pos = $element->end_pos;

        # Get remaining input after this UseStatement
        my $remaining = substr($input_text, $end_pos);

        # Skip whitespace
        $remaining =~ s/^\s+//;

        if ($ENV{DEBUG_OVERLOAD}) {
            my $preview = substr($remaining, 0, 20);
            $preview =~ s/\n/\\n/g;
            warn "VALIDATION: UseStatement at $end_pos, next 20 chars: '$preview'\n";
        }

        # Check what comes next
        if ($remaining =~ /^['"]/) {
            # Starts with a string literal - likely another fat-comma pair
            # This means the ExpressionList stopped early (trailing comma)
            # and should have consumed more
            if ($ENV{DEBUG_OVERLOAD}) {
                warn "VALIDATION ERROR: UseStatement at $end_pos followed by string literal - ExpressionList incomplete\n";
            }
            return 0;  # Invalid
        }

        if ($remaining =~ /^=>/) {
            # Starts with fat comma - this is part of an incomplete key => value pair
            # The ExpressionList should have consumed the full pair
            if ($ENV{DEBUG_OVERLOAD}) {
                warn "VALIDATION ERROR: UseStatement at $end_pos followed by '=>' - ExpressionList incomplete\n";
            }
            return 0;  # Invalid
        }

        return 1;  # Valid
    }
}

1;

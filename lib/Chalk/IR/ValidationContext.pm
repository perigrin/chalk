# ABOUTME: Context-aware validation wrapper for IR construction
# ABOUTME: Provides semantic validation using context information to catch errors at build time
use 5.42.0;
use experimental qw(class builtin);
use utf8;

class Chalk::IR::ValidationContext {
    use Chalk::Error::CompilationError;

    # Try to load Levenshtein module, but don't fail if unavailable
    BEGIN {
        eval {
            require Text::LevenshteinXS;
            Text::LevenshteinXS->import('distance');
        };
        if ($@) {
            # Fallback: simple distance function if module unavailable
            *distance = sub {
                my ($s1, $s2) = @_;
                # Simple check: exact match or substring match
                return 0 if $s1 eq $s2;
                return 1 if index($s1, $s2) >= 0 || index($s2, $s1) >= 0;
                return 999;  # Very different
            };
        }
    }

    field $context :param :reader;
    field $graph   :param :reader;

    # Validate that a variable is defined in the context
    # Returns the node if found, dies with CompilationError if not
    method validate_variable_defined($var_name, $source_info = undef) {
        my $label = "lexical:$var_name";
        my $node = $context->($label);

        unless (defined $node) {
            # Try to find similar variable names for "did you mean?" suggestions
            my $similar = $self->find_similar_variables($var_name);

            my @hints = (
                "Declare the variable with 'my \$$var_name = ...' first"
            );

            if ($similar) {
                unshift @hints, "Did you mean '\$$similar'?";
            }

            die Chalk::Error::CompilationError->new(
                message => "Undefined variable '\$$var_name'",
                source_info => $source_info,
                hints => \@hints,
            );
        }

        return $node;
    }

    # Validate that an operation is compatible with the given types
    # Dies with CompilationError if incompatible
    method validate_type_operation($op, $left_type, $right_type, $source_info = undef) {
        # Skip validation if types are unknown
        return unless defined($left_type) && defined($right_type);

        # Arithmetic operations don't work on arrays/hashes
        if ($op =~ /^(Add|Subtract|Multiply|Divide)$/) {
            if ($left_type eq 'Array') {
                die Chalk::Error::CompilationError->new(
                    message => "Cannot use '$op' operator on array",
                    source_info => $source_info,
                    hints => [
                        "Use array concatenation: (\@a, \@b)",
                        "Or access elements: \$a[0] $op \$b"
                    ],
                );
            }

            if ($right_type eq 'Array') {
                die Chalk::Error::CompilationError->new(
                    message => "Cannot use '$op' operator on array",
                    source_info => $source_info,
                    hints => [
                        "Use array concatenation: (\@a, \@b)",
                        "Or access elements: \$a $op \$b[0]"
                    ],
                );
            }

            if ($left_type eq 'Hash') {
                die Chalk::Error::CompilationError->new(
                    message => "Cannot use '$op' operator on hash",
                    source_info => $source_info,
                    hints => [
                        "Access hash values: \$hash{key} $op \$other"
                    ],
                );
            }

            if ($right_type eq 'Hash') {
                die Chalk::Error::CompilationError->new(
                    message => "Cannot use '$op' operator on hash",
                    source_info => $source_info,
                    hints => [
                        "Access hash values: \$left $op \$hash{key}"
                    ],
                );
            }
        }

        return 1;
    }

    # Validate control flow merge points
    method validate_control_merge($incoming_controls, $source_info = undef) {
        return unless defined($incoming_controls);
        return if scalar(@$incoming_controls) == 0;

        # Check that all control inputs are valid nodes
        for my $ctrl_id (@$incoming_controls) {
            next unless defined($ctrl_id);

            my $ctrl_node = $graph->get_node($ctrl_id);
            unless (defined $ctrl_node) {
                die Chalk::Error::CompilationError->new(
                    message => "Region references undefined control node '$ctrl_id'",
                    source_info => $source_info,
                    hints => [
                        "This is an internal IR construction error",
                        "Control flow nodes must be added to graph before Region"
                    ],
                );
            }

            # Start nodes shouldn't be merged with other control flow
            if ($ctrl_node->op eq 'Start' && scalar(@$incoming_controls) > 1) {
                die Chalk::Error::CompilationError->new(
                    message => "Cannot merge Start node with other control flow",
                    source_info => $source_info,
                    hints => [
                        "Region nodes should merge If/Loop branches, not Start",
                        "Start node should be the unique function entry point"
                    ],
                );
            }
        }

        return 1;
    }

    # Validate class field exists in class definition
    method validate_class_field($class_name, $field_name, $source_info = undef) {
        return unless defined($class_name);

        # Look up class definition in context
        my $class_label = "class:$class_name";
        my $class_def = $context->($class_label);

        if (defined $class_def) {
            # Extract field names from class definition
            my @valid_fields;
            if (ref($class_def) eq 'HASH' && exists($class_def->{fields})) {
                @valid_fields = $class_def->{fields}->@*;
            } elsif (ref($class_def) && $class_def->can('fields')) {
                @valid_fields = $class_def->fields->@*;
            } else {
                # Can't validate - unknown class def structure
                return 1;
            }

            # Check if field exists
            my $field_exists = grep { $_ eq $field_name } @valid_fields;

            unless ($field_exists) {
                my $field_list = join(', ', map { "\$$_" } @valid_fields);
                die Chalk::Error::CompilationError->new(
                    message => "Class '$class_name' has no field '\$$field_name'",
                    source_info => $source_info,
                    hints => [
                        "Valid fields: $field_list",
                        "Check for typos in the field name"
                    ],
                );
            }
        }

        return 1;
    }

    # Validate function call arity matches signature
    method validate_call_arity($function_name, $arg_count, $source_info = undef) {
        return unless defined($function_name);

        # Look up function signature in context
        my $func_label = "function:$function_name";
        my $func_def = $context->($func_label);

        if (defined $func_def) {
            # Extract arity from function definition
            my $expected_arity;

            if (ref($func_def) eq 'HASH' && exists($func_def->{arity})) {
                $expected_arity = $func_def->{arity};
            } elsif (ref($func_def) eq 'HASH' && exists($func_def->{params})) {
                $expected_arity = scalar(@{$func_def->{params}});
            } elsif (ref($func_def) && $func_def->can('arity')) {
                $expected_arity = $func_def->arity;
            } else {
                # Can't determine arity - skip validation
                return 1;
            }

            # Check arity
            if ($arg_count != $expected_arity) {
                my $plural_expected = $expected_arity == 1 ? 'argument' : 'arguments';
                my $plural_got = $arg_count == 1 ? 'argument' : 'arguments';

                die Chalk::Error::CompilationError->new(
                    message => "Function '$function_name' expects $expected_arity $plural_expected, got $arg_count",
                    source_info => $source_info,
                    hints => [
                        "Check the function signature",
                        $arg_count < $expected_arity
                            ? "You're missing " . ($expected_arity - $arg_count) . " argument(s)"
                            : "You have " . ($arg_count - $expected_arity) . " too many argument(s)"
                    ],
                );
            }
        }

        return 1;
    }

    # Helper: Find variables similar to the given name (for "did you mean?" suggestions)
    method find_similar_variables($var_name) {
        my @all_vars = $self->list_available_variables();
        return undef unless @all_vars;

        # Find the closest match using Levenshtein distance
        my $best_match = undef;
        my $best_distance = 999;

        for my $candidate (@all_vars) {
            my $dist = distance($var_name, $candidate);
            if ($dist < $best_distance && $dist <= 2) {  # Max distance of 2 for suggestions
                $best_distance = $dist;
                $best_match = $candidate;
            }
        }

        return $best_match;
    }

    # Helper: List all variables available in current context
    method list_available_variables() {
        my @vars;

        # Try common variable names to see what's defined
        # This is a heuristic - the context is a closure, so we can't introspect it directly
        # In practice, semantic actions would need to maintain a separate symbol table
        # For now, return empty list (this is a limitation of the closure-based context)

        # TODO: Consider adding a parallel symbol table in Builder for introspection
        # or modifying Context to track all bindings

        return @vars;
    }
}

1;

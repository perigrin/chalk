# ABOUTME: Main XS target visitor class for instruction selection
# ABOUTME: Converts Sea of Nodes IR to XS AST using visitor pattern
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::Target::XS {
    use Chalk::IR::Context;
    use Chalk::IR::Type::Convert;
    use Chalk::Target::XS::AST::Module;
    use Chalk::Target::XS::AST::CompositeNode;

    field $graph :param :reader;
    field $module_name :param :reader;
    field $ctx = Chalk::IR::Context->empty_context();
    field $temp_counter = 0;
    field $current_class_def = undef;  # For field access during method generation

    # Look up field index by name in current class
    # Returns undef if not a field
    method get_field_index($name) {
        return undef unless defined $current_class_def;
        my $fields = $current_class_def->fields // [];
        for my $field ($fields->@*) {
            if ($field->name eq $name) {
                return $field->index;
            }
        }
        return undef;
    }

    # Context management - bind a variable name to a node ID
    method bind_var($node_id, $var_name) {
        my $label = Chalk::IR::Context->make_label('xs_var', $node_id);
        $ctx = Chalk::IR::Context->extend_context($ctx, $label, $var_name);
    }

    # Get the variable bound to a node ID, allocating a temp if unbound
    method get_var($node_id) {
        my $label = Chalk::IR::Context->make_label('xs_var', $node_id);
        my $var = $ctx->($label);
        return $var if defined $var;
        return $self->alloc_temp($node_id);
    }

    # Allocate a new temporary variable for a node
    method alloc_temp($node_id) {
        my $var = "tmp_" . $temp_counter++;
        $self->bind_var($node_id, $var);
        return $var;
    }

    # IR type → C type mapping for Perl API
    my %IR_TO_C = (
        # Numeric
        'Chalk::IR::Type::Integer' => 'IV',
        'Chalk::IR::Type::Float'   => 'NV',
        'Chalk::IR::Type::Bool'    => 'bool',

        # Perl values
        'Chalk::IR::Type::String'  => 'SV*',
        'Chalk::IR::Type::Array'   => 'AV*',
        'Chalk::IR::Type::Hash'    => 'HV*',
        'Chalk::IR::Type::Code'    => 'CV*',
        'Chalk::IR::Type::Ref'     => 'SV*',
        'Chalk::IR::Type::Object'  => 'SV*',
        'Chalk::IR::Type::Scalar'  => 'SV*',

        # Special
        'Chalk::IR::Type::Undef'   => 'SV*',
        'Chalk::IR::Type::Top'     => 'SV*',
        'Chalk::IR::Type::Bottom'  => 'void',
    );

    # Perl built-in function -> C API mapping
    my %BUILTIN_TO_C_API = (
        # Array operations
        'push'    => 'av_push',
        'pop'     => 'av_pop',
        'shift'   => 'av_shift',
        'unshift' => 'av_unshift',

        # Hash operations
        'exists' => 'hv_exists_ent',
        'delete' => 'hv_delete_ent',

        # Scalar operations
        'defined' => 'SvOK',
        'length'  => 'sv_len',
    );

    # Check if a function name is a Perl built-in with C API mapping
    method is_builtin($func_name) {
        return exists $BUILTIN_TO_C_API{$func_name};
    }

    # Get the C API function for a Perl built-in
    method get_builtin_c_api($func_name) {
        return $BUILTIN_TO_C_API{$func_name};
    }

    # Map IR types to C types for Perl API
    # Prefer compute() (peephole type lattice) over compute_type() (semantic types)
    # because peephole inference propagates types through operations correctly
    method get_c_type($node) {
        my $type = $node->can('compute') ? $node->compute()
                 : ($node->can('compute_type') ? $node->compute_type()
                 : ($node->can('type') ? $node->type : undef));
        return 'SV*' unless defined $type;  # Fallback for nodes without type info

        # Ensure we're working with an IR type (convert Grammar types if needed)
        my $ir_type = Chalk::IR::Type::Convert->ensure_ir_type($type);
        my $type_class = blessed($ir_type);

        return $IR_TO_C{$type_class} // 'SV*';
    }

    # Compute return type from function body by finding Return node
    method compute_return_type($func_def) {
        my $body_stmts = $func_def->body_statements // [];

        for my $stmt ($body_stmts->@*) {
            next unless blessed($stmt) && $stmt->can('op');
            if ($stmt->op eq 'Return' && $stmt->can('value') && $stmt->value) {
                return $self->get_c_type($stmt->value);
            }
        }

        return 'SV*';  # Default fallback
    }

    # Visit a node, dispatching to the appropriate visit_* method
    method visit($node) {
        my $type = ref($node);
        $type =~ s/.*:://;  # Extract class name without namespace

        # Explicit dispatch table (Chalk parser doesn't support $self->$method syntax)
        return $self->visit_Start($node) if $type eq 'Start';
        return $self->visit_Stop($node) if $type eq 'Stop';
        return $self->visit_Constant($node) if $type eq 'Constant';
        return $self->visit_Parm($node) if $type eq 'Parm';
        return $self->visit_Return($node) if $type eq 'Return';
        return $self->visit_Add($node) if $type eq 'Add';
        return $self->visit_Subtract($node) if $type eq 'Subtract';
        return $self->visit_Multiply($node) if $type eq 'Multiply';
        return $self->visit_Divide($node) if $type eq 'Divide';

        # Comparison operators
        return $self->visit_LT($node) if $type eq 'LT';
        return $self->visit_LE($node) if $type eq 'LE';
        return $self->visit_GT($node) if $type eq 'GT';
        return $self->visit_GE($node) if $type eq 'GE';
        return $self->visit_EQ($node) if $type eq 'EQ';
        return $self->visit_NE($node) if $type eq 'NE';

        # Control flow nodes
        return $self->visit_If($node) if $type eq 'If';
        return $self->visit_Region($node) if $type eq 'Region';
        return $self->visit_Phi($node) if $type eq 'Phi';

        # Function call nodes
        return $self->visit_Call($node) if $type eq 'Call';
        return $self->visit_CallEnd($node) if $type eq 'CallEnd';

        # Class-related nodes
        return $self->visit_ClassDef($node) if $type eq 'ClassDef';
        return $self->visit_Field($node) if $type eq 'Field';

        # Variable operation nodes
        return $self->visit_Store($node) if $type eq 'Store';
        return $self->visit_Load($node) if $type eq 'Load';

        # Unary operation nodes
        return $self->visit_Negate($node) if $type eq 'Negate';
        return $self->visit_Not($node) if $type eq 'Not';

        # Logical operation nodes
        return $self->visit_And($node) if $type eq 'And';
        return $self->visit_Or($node) if $type eq 'Or';
        return $self->visit_DefinedOr($node) if $type eq 'DefinedOr';

        # Unknown node type - return undef
        return undef;
    }

    # Schedule emission order using topological sort from graph
    # Returns nodes in dependency order (inputs before uses)
    method schedule_emission() {
        # Check if graph is a blessed object with linearize method
        return () unless $graph && ref($graph) && blessed($graph) && $graph->can('linearize');

        # Get all nodes in topological order
        my @ordered = $graph->linearize();

        # Filter to nodes we can actually emit
        # Skip Start/Stop CFG nodes (they don't produce XS output)
        my @emittable;
        for my $node (@ordered) {
            my $type = ref($node);
            $type =~ s/.*:://;

            # Skip nodes that don't produce output
            next if $type eq 'Start';
            next if $type eq 'Stop';

            # Check if we have a visitor for this node type
            # Explicit list since Chalk parser doesn't support dynamic method names
            if ($type eq 'Constant' || $type eq 'Return' ||
                $type eq 'Add' || $type eq 'Subtract' ||
                $type eq 'Multiply' || $type eq 'Divide' ||
                $type eq 'LT' || $type eq 'LE' ||
                $type eq 'GT' || $type eq 'GE' ||
                $type eq 'EQ' || $type eq 'NE' ||
                $type eq 'Call') {
                push @emittable, $node;
            }
        }

        return @emittable;
    }

    # Find the Stop node in the graph (contains function_defs)
    method find_stop_node() {
        return undef unless $graph && ref($graph) && blessed($graph) && $graph->can('nodes');
        # nodes() returns a hashref of id => node
        my $nodes_hash = $graph->nodes;
        for my $node (values $nodes_hash->%*) {
            return $node if blessed($node) && $node->can('op') && $node->op eq 'Stop';
        }
        return undef;
    }

    # Recursively visit a node and all its dependencies
    # Returns list of XS AST nodes in dependency order
    method visit_with_deps($node, $visited, $statements, $params) {
        return unless blessed($node) && $node->can('id');
        return if $visited->{$node->id}++;

        my $op = $node->can('op') ? $node->op : '';

        # Handle parameter and field references
        if ($op eq 'Load' || $op eq 'Phi') {
            # These might reference parameters or fields - check if we have a name
            if ($node->can('name') && $node->name) {
                my $name = $node->name;
                # Check if it's a parameter (remove sigil for comparison)
                my $bare_name = $name;
                $bare_name =~ s/^\$//;
                for my $param ($params->@*) {
                    my $param_bare = $param;
                    $param_bare =~ s/^\$//;
                    if ($bare_name eq $param_bare) {
                        # Bind this node to the parameter variable
                        $self->bind_var($node->id, $param_bare);
                        return;
                    }
                }

                # Not a parameter - check if it's a field reference
                my $field_index = $self->get_field_index($name);
                if (defined $field_index) {
                    # Field access: generate ObjectFIELDS(self)[index]
                    use Chalk::Target::XS::AST::VarDecl;
                    my $tmp = $self->alloc_temp($node->id);
                    push $statements->@*, Chalk::Target::XS::AST::VarDecl->new(
                        type => 'SV*',
                        name => $tmp,
                        init => "ObjectFIELDS(self)[$field_index]",
                    );
                    return;
                }
            }
        }

        # Visit dependencies first (in correct order)
        # Binary ops: left, right
        if ($node->can('left') && $node->left) {
            $self->visit_with_deps($node->left, $visited, $statements, $params);
        }
        if ($node->can('right') && $node->right) {
            $self->visit_with_deps($node->right, $visited, $statements, $params);
        }
        # Return: value
        if ($node->can('value') && $node->value && $op ne 'Constant') {
            $self->visit_with_deps($node->value, $visited, $statements, $params);
        }
        # Unary ops: operand
        if ($node->can('operand') && $node->operand) {
            $self->visit_with_deps($node->operand, $visited, $statements, $params);
        }
        # CallEnd: visit the underlying Call node first
        if ($op eq 'CallEnd' && $node->can('call') && $node->call) {
            $self->visit_with_deps($node->call, $visited, $statements, $params);
        }
        # Call: visit args only (callee is the function name, not a value)
        if ($op eq 'Call') {
            if ($node->can('args') && $node->args) {
                for my $arg ($node->args->@*) {
                    $self->visit_with_deps($arg, $visited, $statements, $params);
                }
            }
        }

        # Now visit this node
        my $xs_node = $self->visit($node);
        push $statements->@*, $xs_node if defined $xs_node;
    }

    # Generate XS code for a single function's body statements
    method generate_function_body($func_def) {
        use Chalk::Target::XS::AST::Return;

        my @statements;
        my $body_stmts = $func_def->body_statements // [];
        my $params = $func_def->parameters // [];
        my %visited;

        # Bind parameters to their names upfront
        # Parameters in XS are available directly by name
        for my $param ($params->@*) {
            my $bare_name = $param;
            $bare_name =~ s/^\$//;
            # We'll bind parameter nodes when we encounter them
        }

        # Check if there's an explicit Return node in the body
        my $has_return = 0;
        my $last_stmt;
        for my $stmt ($body_stmts->@*) {
            $last_stmt = $stmt;
            if (blessed($stmt) && $stmt->can('op') && $stmt->op eq 'Return') {
                $has_return = 1;
            }
        }

        for my $stmt ($body_stmts->@*) {
            $self->visit_with_deps($stmt, \%visited, \@statements, $params);
        }

        # If no explicit return, add implicit return for last expression
        if (!$has_return && defined($last_stmt) && blessed($last_stmt) && $last_stmt->can('id')) {
            my $var = $self->get_var($last_stmt->id);
            push @statements, Chalk::Target::XS::AST::Return->new(expr => $var);
        }

        return @statements;
    }

    # Generate XS AST from IR graph
    method generate() {
        use Chalk::Target::XS::AST::XSUB;

        my @xsubs;

        # Find Stop node which contains function definitions
        my $stop = $self->find_stop_node();

        if ($stop && $stop->can('function_defs')) {
            # Generate one XSUB per function definition
            my $funcs = $stop->function_defs // [];
            for my $func_def ($funcs->@*) {
                # Reset temp counter for each function
                $temp_counter = 0;
                $ctx = Chalk::IR::Context->empty_context();

                my $func_name = $func_def->name // 'anonymous';
                my $params = $func_def->parameters // [];

                # Compute return type from function body
                my $return_type = $self->compute_return_type($func_def);

                # Generate body statements for this function
                my @body_statements = $self->generate_function_body($func_def);

                my $xsub = Chalk::Target::XS::AST::XSUB->new(
                    name => $func_name,
                    params => $params,
                    body => \@body_statements,
                    return_type => $return_type,
                );
                push @xsubs, $xsub;
            }
        }

        # Generate XSUBs for class methods
        if ($stop && $stop->can('class_defs')) {
            my $classes = $stop->class_defs // [];
            for my $class_def ($classes->@*) {
                my $class_xsubs = $self->generate_class_xsubs($class_def);
                push @xsubs, $class_xsubs->@*;
            }
        }

        # Fallback: if no functions found, use legacy behavior with main program flow
        if (!@xsubs) {
            # 1. Build emission order (topological sort)
            my @order = $self->schedule_emission();

            # 2. Visit each node, building XS AST statements
            my @statements;
            for my $node (@order) {
                my $xs_node = $self->visit($node);
                push @statements, $xs_node if defined $xs_node;
            }

            # 3. Create XSUB wrapper if we have statements
            if (@statements) {
                my $xsub = Chalk::Target::XS::AST::XSUB->new(
                    name => 'generated',
                    params => [],
                    body => \@statements,
                );
                push @xsubs, $xsub;
            }
        }

        # 4. Wrap in module structure
        # Note: Module.pm currently only emits MODULE/PACKAGE line
        # The XSUBs are emitted separately after
        my $module = Chalk::Target::XS::AST::Module->new(
            module => $module_name,
            package => $module_name,
        );

        # Return a composite structure that emits both
        return Chalk::Target::XS::AST::CompositeNode->new(
            children => [$module, @xsubs],
        );
    }

    # Generate both .xs and .pmc files for a module
    # Returns hashref: { xs => $xs_content, pmc => $pmc_content }
    method generate_files() {
        # Generate XS content
        my $xs_ast = $self->generate();
        my $xs_content = $xs_ast->emit();

        # Generate PMC stub with XSLoader
        my $pmc_content = $self->generate_pmc();

        return {
            xs  => $xs_content,
            pmc => $pmc_content,
        };
    }

    # Generate PMC stub file content with XSLoader
    method generate_pmc() {
        my $class_name = $module_name;

        # Use string concatenation instead of heredoc (heredocs not in Chalk grammar)
        my $pmc = "# ABOUTME: XSLoader stub for $class_name\n";
        $pmc .= "# ABOUTME: Generated by Chalk compiler - do not edit\n";
        $pmc .= "package $class_name;\n";
        $pmc .= "use v5.40;\n";
        $pmc .= "use XSLoader;\n";
        $pmc .= "our \$VERSION = '0.01';\n";
        $pmc .= "XSLoader::load(__PACKAGE__, \$VERSION);\n";
        $pmc .= "1;\n";
        return $pmc;
    }

    # Generate file path for output file based on module name
    # Converts Foo::Bar to lib/Foo/Bar.$extension
    method file_path($extension) {
        my $path = $module_name;
        $path =~ s/::/\//g;
        return "lib/$path.$extension";
    }

    # Generate Build.PL content for Module::Build::Tiny
    method generate_build_pl() {
        my $build = "# ABOUTME: Module::Build::Tiny build script\n";
        $build .= "# ABOUTME: Generated by Chalk compiler - do not edit\n";
        $build .= "use strict;\n";
        $build .= "use warnings;\n";
        $build .= "use Module::Build::Tiny;\n";
        $build .= "Build_PL();\n";
        return $build;
    }

    # Generate complete CPAN-ready distribution
    # Returns hashref: { 'Build.PL' => ..., 'lib/Foo.pm' => ..., 'lib/Foo.xs' => ... }
    method generate_distribution() {
        # Generate XS and PMC content
        my $files = $self->generate_files();

        # Get file paths
        my $pm_path = $self->file_path('pm');
        my $xs_path = $self->file_path('xs');

        return {
            'Build.PL'  => $self->generate_build_pl(),
            $pm_path    => $files->{pmc},
            $xs_path    => $files->{xs},
        };
    }

    # Generate XSUBs for class methods
    # Each method becomes an XSUB with implicit $self parameter
    method generate_class_xsubs($class_def) {
        use Chalk::Target::XS::AST::XSUB;

        # Store class def for field resolution during method body generation
        $current_class_def = $class_def;

        my @xsubs;
        my $methods = $class_def->methods // [];

        for my $method_def ($methods->@*) {
            # Reset temp counter for each method
            $temp_counter = 0;
            $ctx = Chalk::IR::Context->empty_context();

            my $method_name = $method_def->name // 'anonymous';
            my $params = $method_def->parameters // [];

            # MethodDeclaration already adds $self as first parameter
            # Convert to XS format: $self → SV* self, others → bare names
            my @method_params;
            for my $param ($params->@*) {
                if ($param eq '$self') {
                    # Convert $self to C type declaration
                    push @method_params, 'SV* self';
                } else {
                    # Other params keep sigil (stripped by XSUB emit)
                    push @method_params, $param;
                }
            }

            # Compute return type from method body
            my $return_type = $self->compute_return_type($method_def);

            # Generate body statements for this method
            my @body_statements = $self->generate_function_body($method_def);

            my $xsub = Chalk::Target::XS::AST::XSUB->new(
                name => $method_name,
                params => \@method_params,
                body => \@body_statements,
                return_type => $return_type,
            );
            push @xsubs, $xsub;
        }

        # Generate constructor for class with fields
        my $constructor = $self->generate_constructor($class_def);
        unshift @xsubs, $constructor if $constructor;

        # Reset class context to avoid state leakage to non-method code
        $current_class_def = undef;

        return \@xsubs;
    }

    # Generate new() constructor XSUB for a class
    # Creates SVt_PVOBJ, sets up ObjectFIELDS, initializes defaults
    method generate_constructor($class_def) {
        use Chalk::Target::XS::AST::XSUB;
        use Chalk::Target::XS::AST::VarDecl;
        use Chalk::Target::XS::AST::Statement;
        use Chalk::Target::XS::AST::Return;

        my @fields = $class_def->fields->@*;
        my $field_count = scalar @fields;

        my @body;

        # Allocate object: SV* obj = newSV_type(SVt_PVOBJ);
        push @body, Chalk::Target::XS::AST::VarDecl->new(
            type => 'SV*',
            name => 'obj',
            init => 'newSV_type(SVt_PVOBJ)',
        );

        # Set up field storage if class has fields
        if ($field_count > 0) {
            # ObjectMAXFIELD(obj) = field_count - 1;
            my $max_field = $field_count - 1;
            push @body, Chalk::Target::XS::AST::Statement->new(
                code => "ObjectMAXFIELD(obj) = $max_field",
            );

            # Newxz(ObjectFIELDS(obj), field_count, SV*);
            push @body, Chalk::Target::XS::AST::Statement->new(
                code => "Newxz(ObjectFIELDS(obj), $field_count, SV*)",
            );

            # Initialize fields with default values
            for my $field (@fields) {
                my $idx = $field->index;
                my $default = $field->default;

                if (defined $default) {
                    # Get the default value (constant folding should have resolved it)
                    my $default_val;
                    if ($default->can('value')) {
                        $default_val = $default->value;
                    }

                    if (defined $default_val) {
                        # Determine the right newSV* call based on type
                        my $sv_init;
                        if (!defined $default_val) {
                            $sv_init = '&PL_sv_undef';
                        } elsif ($default_val =~ /^-?\d+$/) {
                            $sv_init = "newSViv($default_val)";
                        } elsif ($default_val =~ /^-?\d+\.?\d*$/) {
                            $sv_init = "newSVnv($default_val)";
                        } else {
                            # String - escape for C
                            my $escaped = $default_val;
                            $escaped =~ s/\\/\\\\/g;
                            $escaped =~ s/"/\\"/g;
                            $sv_init = "newSVpv(\"$escaped\", 0)";
                        }
                        push @body, Chalk::Target::XS::AST::Statement->new(
                            code => "ObjectFIELDS(obj)[$idx] = $sv_init",
                        );
                    }
                } else {
                    # No default - initialize to undef
                    push @body, Chalk::Target::XS::AST::Statement->new(
                        code => "ObjectFIELDS(obj)[$idx] = &PL_sv_undef",
                    );
                }
            }
        }

        # Return the object
        push @body, Chalk::Target::XS::AST::Return->new(
            expr => 'obj',
        );

        return Chalk::Target::XS::AST::XSUB->new(
            name => 'new',
            params => ['SV* class'],
            body => \@body,
            return_type => 'SV*',
        );
    }

    # Visitor methods (added incrementally via TDD)
    # These will be implemented as tests require them

    # Start and Stop nodes produce no XS output
    method visit_Start($node) {
        return undef;
    }

    method visit_Stop($node) {
        return undef;
    }

    # Parm nodes represent function parameters - bind to parameter name
    method visit_Parm($node) {
        my $name = $node->name;
        my $bare_name = $name;
        $bare_name =~ s/^\$//;  # Remove sigil for XS variable name
        $self->bind_var($node->id, $bare_name);
        return undef;  # No XS statement needed
    }

    method visit_Constant($node) {
        use Chalk::Target::XS::AST::VarDecl;
        use Chalk::Target::XS::AST::Literal;

        my $value = $node->value;
        my $var = $self->alloc_temp($node->id);
        my $c_type = $self->get_c_type($node);

        return Chalk::Target::XS::AST::VarDecl->new(
            type => $c_type,
            name => $var,
            init => Chalk::Target::XS::AST::Literal->new(value => $value, c_type => $c_type),
        );
    }

    method visit_Return($node) {
        use Chalk::Target::XS::AST::Return;

        my $input_id = $node->value->id;
        my $var = $self->get_var($input_id);

        return Chalk::Target::XS::AST::Return->new(
            expr => $var,
        );
    }

    # Helper for binary operations - extracts common pattern
    method _visit_binary_op($node, $operator) {
        use Chalk::Target::XS::AST::VarDecl;
        use Chalk::Target::XS::AST::BinaryOp;

        my ($left_id, $right_id) = $node->inputs->@*;
        my $left_var = $self->get_var($left_id);
        my $right_var = $self->get_var($right_id);

        my $result_var = $self->alloc_temp($node->id);
        my $c_type = $self->get_c_type($node);

        return Chalk::Target::XS::AST::VarDecl->new(
            type => $c_type,
            name => $result_var,
            init => Chalk::Target::XS::AST::BinaryOp->new(
                left => $left_var,
                operator => $operator,
                right => $right_var,
            ),
        );
    }

    method visit_Add($node) { $self->_visit_binary_op($node, '+'); }
    method visit_Subtract($node) { $self->_visit_binary_op($node, '-'); }
    method visit_Multiply($node) { $self->_visit_binary_op($node, '*'); }
    method visit_Divide($node) { $self->_visit_binary_op($node, '/'); }

    # Comparison visitors - produce boolean (IV 0 or 1) results
    method visit_LT($node) { $self->_visit_binary_op($node, '<'); }
    method visit_LE($node) { $self->_visit_binary_op($node, '<='); }
    method visit_GT($node) { $self->_visit_binary_op($node, '>'); }
    method visit_GE($node) { $self->_visit_binary_op($node, '>='); }
    method visit_EQ($node) { $self->_visit_binary_op($node, '=='); }
    method visit_NE($node) { $self->_visit_binary_op($node, '!='); }

    # Control flow visitors
    # If nodes require control flow restructuring to generate proper if/else
    # For now, we return undef - full implementation needs graph analysis
    # TODO: Implement control flow restructuring for If/Region/Phi patterns
    method visit_If($node) {
        # Full control flow generation requires analyzing the CFG structure
        # to identify if/then/else patterns and reconstruct structured code.
        # This is non-trivial for Sea of Nodes IR.
        return undef;
    }

    # Region nodes are CFG merge points - they don't emit XS code directly
    method visit_Region($node) {
        return undef;
    }

    # Phi nodes select values based on control flow path
    # In XS, this becomes variable assignment in each branch
    # TODO: Implement when full control flow restructuring is done
    method visit_Phi($node) {
        return undef;
    }

    # Function call visitors
    method visit_Call($node) {
        use Chalk::Target::XS::AST::VarDecl;
        use Chalk::Target::XS::AST::FunctionCall;

        # Get the function name from the callee node
        my $callee = $node->callee;
        my $func_name;
        if ($callee && $callee->can('value')) {
            $func_name = $callee->value;
        } elsif ($callee && $callee->can('name')) {
            $func_name = $callee->name;
        } else {
            $func_name = 'unknown';
        }

        # Get argument variable names
        my @arg_vars;
        my $args = $node->args // [];
        for my $arg ($args->@*) {
            if ($arg && $arg->can('id')) {
                push @arg_vars, $self->get_var($arg->id);
            }
        }

        # Check if this is a Perl built-in with a C API mapping
        my $c_func_name = $func_name;
        my $return_type = 'IV';  # Default return type
        if ($self->is_builtin($func_name)) {
            $c_func_name = $self->get_builtin_c_api($func_name);

            # Set appropriate return type based on the builtin
            if ($func_name eq 'defined') {
                $return_type = 'bool';
            } elsif ($func_name eq 'pop' || $func_name eq 'shift' || $func_name eq 'delete') {
                $return_type = 'SV*';
            } elsif ($func_name eq 'exists') {
                $return_type = 'bool';
            } elsif ($func_name eq 'length') {
                $return_type = 'STRLEN';
            }
            # push/unshift don't return meaningful values (return count)
        }

        # Allocate result variable and create VarDecl with FunctionCall init
        my $result_var = $self->alloc_temp($node->id);

        return Chalk::Target::XS::AST::VarDecl->new(
            type => $return_type,
            name => $result_var,
            init => Chalk::Target::XS::AST::FunctionCall->new(
                name => $c_func_name,
                args => \@arg_vars,
            ),
        );
    }

    # CallEnd is a projection node - bind to the Call's result variable
    method visit_CallEnd($node) {
        # The Call node should have been visited first, allocating a temp
        # Bind this CallEnd to the same variable
        if ($node->can('call') && $node->call) {
            my $call = $node->call;
            my $call_var = $self->get_var($call->id);
            $self->bind_var($node->id, $call_var);
        }
        return undef;  # No XS output, just binding
    }

    # ClassDef nodes are handled by generate_class_xsubs, not visit()
    # This visitor is for cases where ClassDef appears in normal traversal
    method visit_ClassDef($node) {
        # ClassDef is processed separately via class_defs collection
        # No direct XS output from visiting
        return undef;
    }

    # Field nodes define class fields - used for accessor generation
    # XS output handled by constructor generation and FieldLoad/FieldStore
    method visit_Field($node) {
        # Field metadata used by constructor and accessor generation
        # No direct XS output from visiting
        return undef;
    }

    # Variable operation visitors
    # Store: assigns a value to a variable
    method visit_Store($node) {
        use Chalk::Target::XS::AST::VarDecl;

        my $var_name = $node->var;
        $var_name =~ s/^\$//;  # Remove sigil for C variable name

        my $value = $node->value;
        my $value_var = $self->get_var($value->id);

        # Get the type from the value node
        my $c_type = $self->get_c_type($value);

        # Bind the Store node to the variable name for later references
        $self->bind_var($node->id, $var_name);

        return Chalk::Target::XS::AST::VarDecl->new(
            type => $c_type,
            name => $var_name,
            init => $value_var,
        );
    }

    # Load: reads a variable's value
    method visit_Load($node) {
        my $value = $node->value;

        # Bind the Load node to the same temp as its underlying value
        # This way, any node referencing the Load gets the value's temp
        if ($value && $value->can('id')) {
            my $value_var = $self->get_var($value->id);
            $self->bind_var($node->id, $value_var);
        }

        # Load doesn't emit a statement - it's just a binding
        return undef;
    }

    # Unary negation visitor
    method visit_Negate($node) {
        use Chalk::Target::XS::AST::VarDecl;

        my $operand = $node->operand;
        my $operand_var = $self->get_var($operand->id);

        my $result_var = $self->alloc_temp($node->id);
        my $c_type = $self->get_c_type($node);

        return Chalk::Target::XS::AST::VarDecl->new(
            type => $c_type,
            name => $result_var,
            init => "-$operand_var",
        );
    }

    # Logical operator visitors
    # And: $a && $b - short-circuit, returns left if false, right if true
    method visit_And($node) {
        use Chalk::Target::XS::AST::VarDecl;

        my $left = $node->left;
        my $right = $node->right;
        my $left_var = $self->get_var($left->id);
        my $right_var = $self->get_var($right->id);

        my $result_var = $self->alloc_temp($node->id);

        # SvTRUE(left) ? right : left
        return Chalk::Target::XS::AST::VarDecl->new(
            type => 'SV*',
            name => $result_var,
            init => "SvTRUE($left_var) ? $right_var : $left_var",
        );
    }

    # Or: $a || $b - short-circuit, returns left if true, right if false
    method visit_Or($node) {
        use Chalk::Target::XS::AST::VarDecl;

        my $left = $node->left;
        my $right = $node->right;
        my $left_var = $self->get_var($left->id);
        my $right_var = $self->get_var($right->id);

        my $result_var = $self->alloc_temp($node->id);

        # SvTRUE(left) ? left : right
        return Chalk::Target::XS::AST::VarDecl->new(
            type => 'SV*',
            name => $result_var,
            init => "SvTRUE($left_var) ? $left_var : $right_var",
        );
    }

    # Not: !$a - logical negation
    method visit_Not($node) {
        use Chalk::Target::XS::AST::VarDecl;

        my $operand = $node->operand;
        my $operand_var = $self->get_var($operand->id);

        my $result_var = $self->alloc_temp($node->id);

        # SvTRUE(operand) ? &PL_sv_no : &PL_sv_yes
        return Chalk::Target::XS::AST::VarDecl->new(
            type => 'SV*',
            name => $result_var,
            init => "SvTRUE($operand_var) ? &PL_sv_no : &PL_sv_yes",
        );
    }

    # DefinedOr: $a // $b - returns left if defined, right otherwise
    method visit_DefinedOr($node) {
        use Chalk::Target::XS::AST::VarDecl;

        my $left = $node->left;
        my $right = $node->right;
        my $left_var = $self->get_var($left->id);
        my $right_var = $self->get_var($right->id);

        my $result_var = $self->alloc_temp($node->id);

        # SvOK(left) ? left : right
        return Chalk::Target::XS::AST::VarDecl->new(
            type => 'SV*',
            name => $result_var,
            init => "SvOK($left_var) ? $left_var : $right_var",
        );
    }
}

1;

# ABOUTME: Main XS target visitor class for instruction selection
# ABOUTME: Converts Sea of Nodes IR to XS AST using visitor pattern
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::Target::XS {
    use Chalk::IR::Context;
    use Chalk::Target::XS::AST::Module;
    use Chalk::Target::XS::AST::CompositeNode;

    field $graph :param :reader;
    field $module_name :param :reader;
    field $ctx = Chalk::IR::Context->empty_context();
    field $temp_counter = 0;

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

    # Map IR types to C types for Perl API
    # Prefer compute() (peephole type lattice) over compute_type() (semantic types)
    # because peephole inference propagates types through operations correctly
    method get_c_type($node) {
        my $ir_type = $node->can('compute') ? $node->compute()
                    : ($node->can('compute_type') ? $node->compute_type() : $node->type);
        my $type_class = ref($ir_type);

        # Handle IR types
        return 'IV' if $type_class eq 'Chalk::IR::Type::Integer';
        return 'NV' if $type_class eq 'Chalk::IR::Type::Float';

        # Handle Grammar types
        return 'IV' if $type_class eq 'Chalk::Grammar::Chalk::Type::Int';
        return 'NV' if $type_class eq 'Chalk::Grammar::Chalk::Type::Num';
        return 'SV*' if $type_class eq 'Chalk::Grammar::Chalk::Type::Str';
        return 'AV*' if $type_class eq 'Chalk::Grammar::Chalk::Type::Array';
        return 'AV*' if $type_class eq 'Chalk::Grammar::Chalk::Type::ArrayRef';
        return 'HV*' if $type_class eq 'Chalk::Grammar::Chalk::Type::Hash';

        return 'SV*';  # Conservative fallback
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
                $type eq 'Multiply' || $type eq 'Divide') {
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

        # Handle parameter references - bind to parameter name, no XS output
        if ($op eq 'Load' || $op eq 'Phi') {
            # These might reference parameters - check if we have a name
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

        # Now visit this node
        my $xs_node = $self->visit($node);
        push $statements->@*, $xs_node if defined $xs_node;
    }

    # Generate XS code for a single function's body statements
    method generate_function_body($func_def) {
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

        for my $stmt ($body_stmts->@*) {
            $self->visit_with_deps($stmt, \%visited, \@statements, $params);
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
}

1;

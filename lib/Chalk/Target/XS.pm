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
    method get_c_type($node) {
        my $ir_type = $node->can('compute_type') ? $node->compute_type() : $node->type;
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

    # Visit a node, dispatching to the appropriate visit_* method
    method visit($node) {
        my $type = ref($node);
        $type =~ s/.*:://;  # Extract class name without namespace
        my $method = "visit_$type";
        return $self->$method($node);
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
            my $method = "visit_$type";
            if ($self->can($method)) {
                push @emittable, $node;
            }
        }

        return @emittable;
    }

    # Generate XS AST from IR graph
    method generate() {
        use Chalk::Target::XS::AST::XSUB;

        # 1. Build emission order (topological sort)
        my @order = $self->schedule_emission();

        # 2. Visit each node, building XS AST statements
        my @statements;
        for my $node (@order) {
            my $xs_node = $self->visit($node);
            push @statements, $xs_node if defined $xs_node;
        }

        # 3. Create XSUB wrapper if we have statements
        my @xsubs;
        if (@statements) {
            # For now, create a single XSUB named after the module
            # TODO: Extract function name from IR (when we have function boundaries)
            my $xsub = Chalk::Target::XS::AST::XSUB->new(
                name => 'generated',
                params => [],
                body => \@statements,
            );
            push @xsubs, $xsub;
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

    method visit_Constant($node) {
        use Chalk::Target::XS::AST::VarDecl;
        use Chalk::Target::XS::AST::Literal;

        my $value = $node->value;
        my $var = $self->alloc_temp($node->id);
        my $c_type = $self->get_c_type($node);

        return Chalk::Target::XS::AST::VarDecl->new(
            type => $c_type,
            name => $var,
            init => Chalk::Target::XS::AST::Literal->new(value => $value),
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

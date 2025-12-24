# ABOUTME: Main XS target visitor class for instruction selection
# ABOUTME: Converts Sea of Nodes IR to XS AST using visitor pattern
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::Target::XS {
    use Chalk::IR::Context;
    use Chalk::Target::XS::AST::Module;

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
        my $ir_type = $node->type;
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

    # Schedule emission order using reverse postorder from Return nodes
    method schedule_emission() {
        # For now, return empty list - will implement graph traversal
        # when we have actual IR graphs to work with
        return ();
    }

    # Generate XS AST from IR graph
    method generate() {
        # 1. Build emission order (reverse postorder from Return nodes)
        my @order = $self->schedule_emission();

        # 2. Visit each node, building XS AST
        my @statements;
        for my $node (@order) {
            my $xs_node = $self->visit($node);
            push @statements, $xs_node if defined $xs_node;
        }

        # 3. Wrap in module structure
        return Chalk::Target::XS::AST::Module->new(
            module => $module_name,
            package => $module_name,
        );
    }

    # Visitor methods (added incrementally via TDD)
    # These will be implemented as tests require them
    method visit_Constant($node) {
        die "visit_Constant not implemented yet";
    }

    method visit_Return($node) {
        die "visit_Return not implemented yet";
    }
}

1;

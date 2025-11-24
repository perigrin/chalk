# ABOUTME: IR builder for transforming parsed Chalk code into Sea of Nodes IR
# ABOUTME: Provides methods called by semantic actions to build IR nodes during parsing
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Builder {
    use Chalk::IR::Node;
    use Chalk::IR::Graph;
    use Chalk::IR::Context;
    use Chalk::IR::ValidationContext;
    use Chalk::IR::TypeInference;
    use Chalk::Grammar::Chalk::TypeLattice;

    # Phase 1 polymorphic node classes
    use Chalk::IR::Node::Base;
    use Chalk::IR::Node::Constant;
    use Chalk::IR::Node::Start;
    use Chalk::IR::Node::Return;
    use Chalk::IR::Node::Stop;
    use Chalk::IR::Node::Add;
    use Chalk::IR::Node::Subtract;
    use Chalk::IR::Node::Multiply;
    use Chalk::IR::Node::Divide;
    use Chalk::IR::Node::Negate;
    use Chalk::IR::Node::Not;
    use Chalk::IR::Node::PreIncrement;
    use Chalk::IR::Node::PreDecrement;
    use Chalk::IR::Node::PostIncrement;
    use Chalk::IR::Node::PostDecrement;
    use Chalk::IR::Node::Reference;
    use Chalk::IR::Node::ScalarDeref;
    use Chalk::IR::Node::VariableRead;
    use Chalk::IR::Node::GT;
    use Chalk::IR::Node::LT;
    use Chalk::IR::Node::EQ;
    use Chalk::IR::Node::NE;
    use Chalk::IR::Node::LE;
    use Chalk::IR::Node::GE;
    use Chalk::IR::Node::If;
    use Chalk::IR::Node::Proj;
    use Chalk::IR::Node::Region;
    use Chalk::IR::Node::Phi;
    use Chalk::IR::Node::Loop;
    use Chalk::IR::Node::NewArray;
    use Chalk::IR::Node::NewHash;
    use Chalk::IR::Node::StrConcat;

    field $graph           :reader = Chalk::IR::Graph->new();
    field $context         :reader = Chalk::IR::Context->empty_context();
    field $node_counter    :reader = 0;
    field $current_control :reader;    # Current control flow node
    field $loop_depth :reader = 0;    # Current loop nesting depth for label namespacing
    field $loop_modified_vars :reader = [];    # Stack of sets tracking modified vars per loop depth
    field $branch_tracking_stack :reader = [];    # Unified stack for tracking variable modifications in branches (loops, conditionals)
    field $type_lattice   :reader = Chalk::Grammar::Chalk::TypeLattice->new();
    field $type_inference :reader = Chalk::IR::TypeInference->new(context => $context, graph => $graph, type_lattice => $type_lattice);
    field $validator      :reader = Chalk::IR::ValidationContext->new(context => $context, graph => $graph, type_lattice => $type_lattice);

    # Generate unique node ID
    method next_node_id() {
        my $id = "node_$node_counter";
        $node_counter++;
        return $id;
    }

    # Set current control flow node
    method set_control($ctrl) {
        $current_control = $ctrl;
    }

    # Loop depth helpers for external Control.pm
    method _increment_loop_depth() {
        $loop_depth++;
    }

    method _decrement_loop_depth() {
        $loop_depth--;
    }

    # Set context (for testing and manual context updates)
    method set_context($ctx) {
        $context = $ctx;

# Recreate validator and type_inference with new context
# This ensures they see updated function signatures, class definitions, and variables
        $type_inference = Chalk::IR::TypeInference->new(
            context      => $context,
            graph        => $graph,
            type_lattice => $type_lattice
        );
        $validator = Chalk::IR::ValidationContext->new(
            context      => $context,
            graph        => $graph,
            type_lattice => $type_lattice
        );
    }

    # Variable management using Context (Chapter 3)
    # DEPRECATED: Use Chalk::IR::Node::Scope instead
    # These methods will be removed in a future version
    method define_variable($var_name, $node_id) {
        warn "DEPRECATED: IR::Builder::define_variable() is deprecated, use Chalk::IR::Node::Scope->define() instead\n"
            if $ENV{CHALK_WARN_DEPRECATED};

        # Store variable binding in context using "var:name" label
        my $label = Chalk::IR::Context->make_label('var', $var_name);
        $context = Chalk::IR::Context->extend_context($context, $label, $node_id);
        return;
    }

    method lookup_variable($var_name) {
        warn "DEPRECATED: IR::Builder::lookup_variable() is deprecated, use Chalk::IR::Node::Scope->lookup() instead\n"
            if $ENV{CHALK_WARN_DEPRECATED};

        # Look up variable from context using "var:name" label
        my $label = Chalk::IR::Context->make_label('var', $var_name);
        my $node_id = $context->($label);
        return unless defined($node_id);

        # Return the actual IR node object, not just the ID
        return $graph->get_node($node_id);
    }

    # Create Start node for a function/method
    method build_start_node( $function_name = 'main', $params = undef ) {
        $params //= [];
        my $node_id      = $self->next_node_id();
        my $empty_inputs = [];
        my $start        = Chalk::IR::Node::Start->new(
            id            => $node_id,
            inputs        => $empty_inputs,
            function_name => $function_name,
            params        => $params,
        );
        $graph->add_node($start);

        # Record transformation
        $start->record_transform( 'ir_construction',
            'Builder::build_start_node', context => "function=$function_name" );

        $self->set_control( $start->id );

        # Create Proj nodes for each parameter and register in context
        my $param_count = scalar( $params->@* );
        for my $i ( 0 .. ( $param_count - 1 ) ) {
            my $param_name = $params->[$i];
            my $proj       = $self->build_proj_node( $start, $i, $param_name );

            # Register parameter Proj in context with lexical: namespace
            my $label = "lexical:$param_name";
            $context =
              Chalk::IR::Context->extend_context( $context, $label, $proj );
        }

        return $start;
    }

    # Create Constant node
    method build_constant_node( $value, $type = 'Int', $source_info = undef ) {
        # Allow undef for representing Perl's undef constant (needed for implicit returns)

        my $node_id  = $self->next_node_id();
        my $constant = Chalk::IR::Node::Constant->new(
            id          => $node_id,
            inputs      => [$current_control],
            value       => $value,
            type        => $type,
            source_info => $source_info,
        );
        $graph->add_node($constant);

        # Record transformation
        $constant->record_transform(
            'ir_construction',
            'Builder::build_constant_node',
            context => "value="
              . ( defined($value) ? $value : '<undef>' )
              . ", type=$type"
        );

        return $constant;
    }

  # Create Return node
  # If $control is undef, uses current_control. Otherwise uses provided control.
    method build_return_node(
        $value_node,
        $control = undef,
        $source_info = undef
      )
    {
        die "build_return_node: value_node is undefined"
          unless defined($value_node);

        # Check that value_node is an IR node object
        unless ( $value_node isa Chalk::IR::Node::Base ) {
            my $ref_type = ref($value_node);
            die
"build_return_node: value_node is not an IR node object (got $ref_type)";
        }

        # Use provided control, or current_control, or '__CONTROL_PLACEHOLDER__'
        my $ctrl = $control // $current_control // '__CONTROL_PLACEHOLDER__';

        my $node_id = $self->next_node_id();
        my $return  = Chalk::IR::Node::Return->new(
            id          => $node_id,
            inputs      => [ $ctrl, $value_node->id ],
            value_id    => $value_node->id,
            control_id  => $ctrl,
            source_info => $source_info,
        );
        $graph->add_node($return);

        # Record transformation
        $return->record_transform(
            'ir_construction',
            'Builder::build_return_node',
            context => "value_id=" . $value_node->id
        );

        return $return;
    }

    # Set control input for an existing node
    method set_node_control( $node, $control_id ) {
        my $inputs = $node->inputs;
        $inputs->[0] = $control_id;    # Control is always first input

        # Return nodes also have a separate control_id field that needs updating
        if ($node->op eq 'Return') {
            $node->set_control_id($control_id);
        }
    }

    # Create arithmetic operation nodes
    # Arithmetic operations moved to Chalk::IR::Builder::Arithmetic
    method make_variable_label($var_name) {
        if ( $loop_depth > 0 ) {
            return "lexical:loop_" . ( $loop_depth - 1 ) . ":$var_name";
        }
        return "lexical:$var_name";
    }

    # Create Store node (variable assignment)
    # DEPRECATED: Use Chalk::IR::Node::Scope instead
    # This method will be removed in a future version
    method build_store_node(
        $var_name, $value_node,
        $control = undef,
        $source_info = undef
      )
    {
        warn "DEPRECATED: IR::Builder::build_store_node() is deprecated, use Chalk::IR::Node::Scope->define() instead\n"
            if $ENV{CHALK_WARN_DEPRECATED};
        # Validate loop variable has proper initial value if we're in a loop
        if ( defined($source_info) && $loop_depth > 0 ) {
            $validator->validate_loop_variable_phi( $var_name, $loop_depth,
                $source_info );
        }

        # Store variable using lexical: namespace in context
        # Inside loops, use loop depth in label: lexical:loop_0:$var
        # Store the IR node object directly, not the node ID
        my $label = $self->make_variable_label($var_name);
        $context =
          Chalk::IR::Context->extend_context( $context, $label, $value_node );

   # Auto-sync validator and type_inference with updated context
   # This ensures subsequent validation operations see the newly stored variable
        $type_inference = Chalk::IR::TypeInference->new(
            context      => $context,
            graph        => $graph,
            type_lattice => $type_lattice
        );
        $validator = Chalk::IR::ValidationContext->new(
            context      => $context,
            graph        => $graph,
            type_lattice => $type_lattice
        );

        # Track this variable as modified if we're in a loop
        if ( $loop_depth > 0 && scalar( $loop_modified_vars->@* ) > 0 ) {
            my $current_loop_vars = $loop_modified_vars->[-1];
            $current_loop_vars->{$var_name} = 1;
        }

        # Track this variable as modified if we're in a tracked branch (conditional/loop)
        if ( scalar($branch_tracking_stack->@*) > 0 ) {
            my $frame = $branch_tracking_stack->[-1];
            my $current_branch = $frame->{current_branch};
            if (defined($current_branch)) {
                warn "[DEBUG] build_store_node: tracking $var_name in branch $current_branch, node_id=", $value_node->id, "\n" if $ENV{CHALK_DEBUG_TRACKING};
                $frame->{branches}->{$current_branch}->{$var_name} = $value_node;
            }
        }

        return $value_node;
    }

    # Load node (variable read)
    # DEPRECATED: Use Chalk::IR::Node::Scope instead
    # This method will be removed in a future version
    method build_load_node( $var_name, $source_info = undef ) {
        warn "DEPRECATED: IR::Builder::build_load_node() is deprecated, use Chalk::IR::Node::Scope->lookup() instead\n"
            if $ENV{CHALK_WARN_DEPRECATED};

        # Retrieve variable using lexical: namespace from context
        # Try loop-scoped label first, then fall back to outer scope
        # Context now stores IR node objects directly, not node IDs
        my $node;

        # Try current loop depth first (search from innermost to outermost)
        if ( $loop_depth > 0 ) {
            my $depth = $loop_depth - 1;
            while ( $depth >= 0 ) {
                my $label = "lexical:loop_${depth}:$var_name";
                $node = $context->($label);
                last if defined($node);
                $depth--;
            }
        }

        # Fall back to non-loop lexical scope
        $node //= $context->("lexical:$var_name");

        # Validate that variable exists if source_info provided
        if ( defined($source_info) && !defined($node) ) {
            $node =
              $validator->validate_variable_defined( $var_name, $source_info );
        }

        # Return the node directly from context (no graph lookup needed)
        return $node;
    }

    # Create Proj node (projection from MultiNode like Start)
    method build_proj_node( $source_node, $index, $label ) {
        my $node_id = $self->next_node_id();
        my $proj    = Chalk::IR::Node::Proj->new(
            id     => $node_id,
            inputs => [ $source_node->id ],
            index  => $index,
            label  => $label,
        );
        $graph->add_node($proj);

        # Record transformation
        $proj->record_transform( 'ir_construction', 'Builder::build_proj_node',
                context => "source_id="
              . $source_node->id
              . ", index=$index, label=$label" );

        return $proj;
    }

    # Comparison nodes
    # Comparison operations moved to Chalk::IR::Builder::Comparison
    # Unary operation nodes
    # Unary operations moved to Chalk::IR::Builder::Unary
    # Control flow operations moved to Chalk::IR::Builder::Control
    method is_tracking_loop() {
        return $loop_depth > 0;
    }

    method current_loop_depth() {
        return $loop_depth;
    }

    method generate_loop_phi_nodes($loop_node) {

# Generate phi nodes for variables modified within the loop
# With context+labels approach, phi nodes are created for variables
# that exist both as 'lexical:$var' (pre-loop) and 'lexical:loop_N:$var' (in-loop)

        my %phi_nodes;

        # If we're not tracking a loop or have no modified vars, return empty
        return \%phi_nodes unless scalar( $loop_modified_vars->@* ) > 0;

        # Get the current loop's modified variables
        my $modified_vars = $loop_modified_vars->[-1];

        # For each modified variable, create a phi node
        for my $var_name ( keys( $modified_vars->%* ) ) {

            # Get pre-loop value (lexical:$var)
            my $pre_loop_label = "lexical:$var_name";
            my $pre_loop_value = $context->($pre_loop_label);

     # Get loop-modified value (lexical:loop_N:$var where N = current depth - 1)
            my $loop_label =
              "lexical:loop_" . ( $loop_depth - 1 ) . ":$var_name";
            my $loop_value = $context->($loop_label);

            # Only create phi if both values exist
            if ( defined($pre_loop_value) && defined($loop_value) ) {

                # Build phi node with: control (loop), initial value, loop value
                my $phi = $self->build_loop_phi_node(
                    $loop_node,
                    (
                        ref($pre_loop_value)
                        ? $pre_loop_value->id
                        : $pre_loop_value
                    ),
                    ( ref($loop_value) ? $loop_value->id : $loop_value )
                );
                $phi_nodes{$var_name} = $phi;
            }
        }

        return \%phi_nodes;
    }

    # Class and object operations moved to Chalk::IR::Builder::Object
    # Reference operations moved to Chalk::IR::Builder::Reference

    # Helper method for type inference - returns type name as string
    # Used by tests and validation logic
    method _infer_type_from_node($node) {
        my $type = $type_inference->infer_type($node);
        return undef unless defined($type);
        return $type->name();
    }

    # Create array value node (simplified version for testing)
    # Takes array ref of initial values
    method build_array_value_node( $values = [] ) {
        my $node_id = $self->next_node_id();
        my $node    = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'ArrayValue',
            inputs     => [$current_control],
            attributes => { values => $values },
        );
        $graph->add_node($node);
        $node->record_transform(
            operation => 'ir_construction',
            rule_name => 'Builder::build_array_value_node'
        );
        return $node;
    }

    # Create hash value node (simplified version for testing)
    # Takes hash ref of initial key-value pairs
    method build_hash_value_node( $pairs = {} ) {
        my $node_id = $self->next_node_id();
        my $node    = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'HashValue',
            inputs     => [$current_control],
            attributes => { pairs => $pairs },
        );
        $graph->add_node($node);
        $node->record_transform(
            operation => 'ir_construction',
            rule_name => 'Builder::build_hash_value_node'
        );
        return $node;
    }

    # Unified branch tracking for Phi node generation
    # Works for both conditionals (branches named 'true'/'false') and loops (branch named by depth)

    method begin_branch_tracking(@branch_names) {
        # Start tracking variable modifications across named branches
        # @branch_names = ('true', 'false') for conditionals
        # @branch_names = ('loop_0') for loops
        warn "[DEBUG] begin_branch_tracking: branches=[@branch_names]\n" if $ENV{CHALK_DEBUG_TRACKING};

        # Validate we have at least one branch name
        die "begin_branch_tracking() requires at least one branch name"
            unless @branch_names > 0;

        # Validate branch names are non-empty strings
        for my $name (@branch_names) {
            die "Branch names must be non-empty strings"
                unless defined($name) && length($name) > 0;
        }

        my %branches = map { $_ => {} } @branch_names;

        push $branch_tracking_stack->@*, {
            branches => \%branches,           # Hash of branch_name => { var => node }
            current_branch => undef,          # Which branch is currently active
            context_snapshot => $context,     # Save context before branches
        };

        # Return guard object for automatic cleanup on exception
        return Chalk::IR::Builder::BranchTrackingGuard->new(builder => $self);
    }

    method set_branch($branch_name) {
        # Set which branch we're currently evaluating
        warn "[DEBUG] set_branch: $branch_name\n" if $ENV{CHALK_DEBUG_TRACKING};

        # Validate we have an active tracking frame
        die "set_branch() called with no active branch tracking"
            unless scalar($branch_tracking_stack->@*) > 0;

        my $frame = $branch_tracking_stack->[-1];

        # Validate the branch name exists in the current tracking frame
        unless (exists $frame->{branches}->{$branch_name}) {
            my @valid_branches = keys $frame->{branches}->%*;
            die "Invalid branch name '$branch_name'. Valid branches are: " .
                join(', ', @valid_branches);
        }

        $frame->{current_branch} = $branch_name;

        # Restore context snapshot so each branch starts from same state
        warn "[DEBUG] set_branch: restoring context snapshot\n" if $ENV{CHALK_DEBUG_TRACKING};
        $context = $frame->{context_snapshot};
        return;
    }

    method end_branch_tracking() {
        # Stop tracking and return the tracking data
        warn "[DEBUG] end_branch_tracking\n" if $ENV{CHALK_DEBUG_TRACKING};

        # Validate we have an active tracking frame
        die "end_branch_tracking() called with no active branch tracking"
            unless scalar($branch_tracking_stack->@*) > 0;

        my $data = pop $branch_tracking_stack->@*;

        # Validate the data structure
        die "Branch tracking frame missing 'branches' key"
            unless exists $data->{branches};
        die "Branch tracking frame missing 'context_snapshot' key"
            unless exists $data->{context_snapshot};

        if ($ENV{CHALK_DEBUG_TRACKING} && $data) {
            my $branches = $data->{branches};
            for my $branch_name (keys $branches->%*) {
                my $vars = $branches->{$branch_name};
                warn "[DEBUG]   branch $branch_name: ", scalar(keys $vars->%*), " vars modified\n";
            }
        }
        return $data;
    }

    method generate_phi_nodes($merge_node, $tracking_data, @branch_names) {
        # Generate Phi nodes for variables modified across branches
        # For conditionals: @branch_names = ('true', 'false')
        # For loops: @branch_names = ('initial', 'loop')
        warn "[DEBUG] generate_phi_nodes: branches=[@branch_names]\n" if $ENV{CHALK_DEBUG_TRACKING};
        my %phi_nodes;

        return \%phi_nodes unless defined($tracking_data);

        my $branches = $tracking_data->{branches};

        # Find all variables modified in any branch
        my %all_vars;
        for my $branch_name (@branch_names) {
            my $branch_vars = $branches->{$branch_name} // {};
            $all_vars{$_} = 1 for keys $branch_vars->%*;
        }

        for my $var_name (keys %all_vars) {
            # Collect values from each branch
            my @values;
            my $snapshot_ctx = $tracking_data->{context_snapshot};

            for my $branch_name (@branch_names) {
                my $value = $branches->{$branch_name}->{$var_name};
                if (defined($value)) {
                    # Branch modified the variable - use the new value
                    push @values, $value;
                } else {
                    # Branch didn't modify variable - use pre-branch value from snapshot
                    my $label = $self->make_variable_label($var_name);
                    my $pre_value = $snapshot_ctx->($label);
                    if (defined($pre_value)) {
                        push @values, $pre_value;
                    }
                }
            }

            # Create Phi if we have values from different code paths
            # This includes cases where only one branch modified the variable
            next unless @values >= 2;

            # Create Phi node: Phi(merge_node, value1, value2, ...)
            my @value_ids = map { $_->id } @values;
            warn "[DEBUG] generate_phi_nodes: creating Phi for $var_name with values [@value_ids]\n" if $ENV{CHALK_DEBUG_TRACKING};
            my $phi = $self->build_phi_node($merge_node, @value_ids);

            # Update context to bind variable to Phi node
            $self->build_store_node($var_name, $phi);

            $phi_nodes{$var_name} = $phi;
        }

        return \%phi_nodes;
    }

    # Delegation methods for helper classes
    # Arithmetic operations
    method build_add_node(@args) {
        state $helper = Chalk::IR::Builder::Arithmetic->new();
        return $helper->build_add_node($self, @args);
    }
    method build_subtract_node(@args) {
        state $helper = Chalk::IR::Builder::Arithmetic->new();
        return $helper->build_subtract_node($self, @args);
    }
    method build_multiply_node(@args) {
        state $helper = Chalk::IR::Builder::Arithmetic->new();
        return $helper->build_multiply_node($self, @args);
    }
    method build_divide_node(@args) {
        state $helper = Chalk::IR::Builder::Arithmetic->new();
        return $helper->build_divide_node($self, @args);
    }

    # Comparison operations
    method build_greater_node(@args) {
        state $helper = Chalk::IR::Builder::Comparison->new();
        return $helper->build_greater_node($self, @args);
    }
    method build_less_node(@args) {
        state $helper = Chalk::IR::Builder::Comparison->new();
        return $helper->build_less_node($self, @args);
    }
    method build_equal_node(@args) {
        state $helper = Chalk::IR::Builder::Comparison->new();
        return $helper->build_equal_node($self, @args);
    }
    method build_greater_or_equal_node(@args) {
        state $helper = Chalk::IR::Builder::Comparison->new();
        return $helper->build_greater_or_equal_node($self, @args);
    }
    method build_less_or_equal_node(@args) {
        state $helper = Chalk::IR::Builder::Comparison->new();
        return $helper->build_less_or_equal_node($self, @args);
    }
    method build_not_equal_node(@args) {
        state $helper = Chalk::IR::Builder::Comparison->new();
        return $helper->build_not_equal_node($self, @args);
    }

    # Unary operations
    method build_not_node(@args) {
        state $helper = Chalk::IR::Builder::Unary->new();
        return $helper->build_not_node($self, @args);
    }
    method build_negate_node(@args) {
        state $helper = Chalk::IR::Builder::Unary->new();
        return $helper->build_negate_node($self, @args);
    }
    method build_pre_increment_node(@args) {
        state $helper = Chalk::IR::Builder::Unary->new();
        return $helper->build_pre_increment_node($self, @args);
    }
    method build_pre_decrement_node(@args) {
        state $helper = Chalk::IR::Builder::Unary->new();
        return $helper->build_pre_decrement_node($self, @args);
    }
    method build_post_increment_node(@args) {
        state $helper = Chalk::IR::Builder::Unary->new();
        return $helper->build_post_increment_node($self, @args);
    }
    method build_post_decrement_node(@args) {
        state $helper = Chalk::IR::Builder::Unary->new();
        return $helper->build_post_decrement_node($self, @args);
    }

    # Control flow operations
    method build_if_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_if_node($self, @args);
    }
    method build_if_true_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_if_true_node($self, @args);
    }
    method build_if_false_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_if_false_node($self, @args);
    }
    method build_region_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_region_node($self, @args);
    }
    method build_phi_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_phi_node($self, @args);
    }
    method build_stop_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_stop_node($self, @args);
    }
    method build_loop_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_loop_node($self, @args);
    }
    method build_loop_phi_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_loop_phi_node($self, @args);
    }
    method build_call_node(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->build_call_node($self, @args);
    }
    method begin_loop_tracking(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->begin_loop_tracking($self, @args);
    }
    method end_loop_tracking(@args) {
        state $helper = Chalk::IR::Builder::Control->new();
        return $helper->end_loop_tracking($self, @args);
    }

    # Data structure operations
    method build_array_new_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_array_new_node($self, @args);
    }
    method build_array_push_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_array_push_node($self, @args);
    }
    method build_array_get_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_array_get_node($self, @args);
    }
    method build_array_set_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_array_set_node($self, @args);
    }
    method build_array_length_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_array_length_node($self, @args);
    }
    method build_hash_new_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_hash_new_node($self, @args);
    }
    method build_hash_set_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_hash_set_node($self, @args);
    }
    method build_hash_get_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_hash_get_node($self, @args);
    }
    method build_hash_exists_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_hash_exists_node($self, @args);
    }
    method build_hash_keys_node(@args) {
        state $helper = Chalk::IR::Builder::DataStructures->new();
        return $helper->build_hash_keys_node($self, @args);
    }

    # Object operations
    method build_classdef_node(@args) {
        state $helper = Chalk::IR::Builder::Object->new();
        return $helper->build_classdef_node($self, @args);
    }
    method build_new_node(@args) {
        state $helper = Chalk::IR::Builder::Object->new();
        return $helper->build_new_node($self, @args);
    }
    method build_field_access_node(@args) {
        state $helper = Chalk::IR::Builder::Object->new();
        return $helper->build_field_access_node($self, @args);
    }
    method build_field_store_node(@args) {
        state $helper = Chalk::IR::Builder::Object->new();
        return $helper->build_field_store_node($self, @args);
    }

    # String operations
    method build_str_concat_node(@args) {
        state $helper = Chalk::IR::Builder::String->new();
        return $helper->build_str_concat_node($self, @args);
    }
    method build_range_node(@args) {
        state $helper = Chalk::IR::Builder::String->new();
        return $helper->build_range_node($self, @args);
    }
    method build_use_statement_node(@args) {
        state $helper = Chalk::IR::Builder::String->new();
        return $helper->build_use_statement_node($self, @args);
    }
    method build_str_length_node(@args) {
        state $helper = Chalk::IR::Builder::String->new();
        return $helper->build_str_length_node($self, @args);
    }
    method build_str_substr_node(@args) {
        state $helper = Chalk::IR::Builder::String->new();
        return $helper->build_str_substr_node($self, @args);
    }
    # Reference operations
    method build_reference_node(@args) {
        state $helper = Chalk::IR::Builder::Reference->new();
        return $helper->build_reference_node($self, @args);
    }
    method build_scalar_deref_node(@args) {
        state $helper = Chalk::IR::Builder::Reference->new();
        return $helper->build_scalar_deref_node($self, @args);
    }
    method build_scalar_deref_assign_node(@args) {
        state $helper = Chalk::IR::Builder::Reference->new();
        return $helper->build_scalar_deref_assign_node($self, @args);
    }
    method build_element_ref_node(@args) {
        state $helper = Chalk::IR::Builder::Reference->new();
        return $helper->build_element_ref_node($self, @args);
    }
    method build_scalar_ref_node(@args) {
        state $helper = Chalk::IR::Builder::Reference->new();
        return $helper->build_scalar_ref_node($self, @args);
    }
    method build_variable_read_node(@args) {
        state $helper = Chalk::IR::Builder::Reference->new();
        return $helper->build_variable_read_node($self, @args);
    }

}

# ABOUTME: Guard object for automatic cleanup of branch tracking frames
# ABOUTME: Prevents memory leaks if exceptions occur during branch evaluation
class Chalk::IR::Builder::BranchTrackingGuard {
    field $builder :param;
    field $active = 1;

    method DESTROY() {
        # Clean up leaked tracking frame if guard was not explicitly dismissed
        if ($active && scalar($builder->branch_tracking_stack->@*) > 0) {
            warn "[WARN] BranchTrackingGuard: cleaning up leaked tracking frame\n";
            try {
                $builder->end_branch_tracking();
            } catch ($e) {
                warn "[ERROR] BranchTrackingGuard: cleanup failed: $e\n";
            }
        }
    }

    method dismiss() {
        $active = 0;
    }
}

# Load helper classes (split from Builder to reduce parse time)
use Chalk::IR::Builder::Arithmetic;
use Chalk::IR::Builder::Comparison;
use Chalk::IR::Builder::Unary;
use Chalk::IR::Builder::Control;
use Chalk::IR::Builder::DataStructures;
use Chalk::IR::Builder::Object;
use Chalk::IR::Builder::String;
use Chalk::IR::Builder::Reference;

1;

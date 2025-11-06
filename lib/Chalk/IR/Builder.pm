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

    # Phase 1 polymorphic node classes
    use Chalk::IR::Node::Base;
    use Chalk::IR::Node::Constant;
    use Chalk::IR::Node::Start;
    use Chalk::IR::Node::Return;
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

    field $graph :reader;
    field $context :reader;  # Context-as-closure for variable memory
    field $node_counter :reader = 0;
    field $current_control :reader;  # Current control flow node
    field $loop_depth = 0;   # Current loop nesting depth for label namespacing
    field $loop_modified_vars = [];  # Stack of sets tracking modified vars per loop depth
    field $type_inference :reader;   # Type inference instance

    ADJUST {
        $graph = Chalk::IR::Graph->new();
        $context = Chalk::IR::Context->empty_context();
        $type_inference = Chalk::IR::TypeInference->new(
            context => $context,
            graph => $graph
        );
    }

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

    # Set context (for testing and manual context updates)
    method set_context($ctx) {
        $context = $ctx;
    }

    # Create Start node for a function/method
    method build_start_node($function_name = 'main', $params = undef) {
        $params //= [];
        my $node_id = $self->next_node_id();
        my $empty_inputs = [];
        my $start = Chalk::IR::Node::Start->new(
            id            => $node_id,
            inputs        => $empty_inputs,
            function_name => $function_name,
            params        => $params,
        );
        $graph->add_node($start);

        # Record transformation
        $start->record_transform('ir_construction', 'Builder::build_start_node',
            context => "function=$function_name"
        );

        $self->set_control($start->id);

        # Create Proj nodes for each parameter and register in context
        my $param_count = scalar($params->@*);
        for my $i (0..($param_count - 1)) {
            my $param_name = $params->[$i];
            my $proj = $self->build_proj_node($start, $i, $param_name);
            # Register parameter Proj in context with lexical: namespace
            my $label = "lexical:$param_name";
            $context = Chalk::IR::Context->extend_context($context, $label, $proj);
        }

        return $start;
    }

    # Create Constant node
    method build_constant_node($value, $type = 'Int', $source_info = undef) {
        die "build_constant_node: value is undefined" unless defined($value);

        my $node_id = $self->next_node_id();
        my $constant = Chalk::IR::Node::Constant->new(
            id            => $node_id,
            inputs        => [$current_control],
            value         => $value,
            type          => $type,
            source_info   => $source_info,
        );
        $graph->add_node($constant);

        # Record transformation
        $constant->record_transform('ir_construction', 'Builder::build_constant_node',
            context => "value=$value, type=$type"
        );

        return $constant;
    }

    # Create Return node
    # If $control is undef, uses current_control. Otherwise uses provided control.
    method build_return_node($value_node, $control = undef, $source_info = undef) {
        die "build_return_node: value_node is undefined" unless defined($value_node);

        # Check that value_node is an IR node object
        my $ref_type = ref($value_node) || 'SCALAR';
        my $prefix = substr($ref_type, 0, 15);
        my $is_node = ($prefix eq 'Chalk::IR::Node') ? 1 : 0;
        unless ($ref_type && $is_node) {
            die "build_return_node: value_node is not an IR node object (got $ref_type)";
        }

        # Use provided control, or current_control, or '__CONTROL_PLACEHOLDER__'
        my $ctrl = $control // $current_control // '__CONTROL_PLACEHOLDER__';

        my $node_id = $self->next_node_id();
        my $return = Chalk::IR::Node::Return->new(
            id            => $node_id,
            inputs        => [$ctrl, $value_node->id],
            value_id      => $value_node->id,
            control_id    => $ctrl,
            source_info   => $source_info,
        );
        $graph->add_node($return);

        # Record transformation
        $return->record_transform('ir_construction', 'Builder::build_return_node',
            context => "value_id=" . $value_node->id
        );

        return $return;
    }

    # Set control input for an existing node
    method set_node_control($node, $control_id) {
        my $inputs = $node->inputs;
        $inputs->[0] = $control_id;  # Control is always first input
    }

    # Create arithmetic operation nodes
    method build_add_node($left_node, $right_node, $source_info = undef) {
        die "build_add_node: left_node is undefined" unless defined($left_node);
        die "build_add_node: right_node is undefined" unless defined($right_node);
        die "build_add_node: left_node is not an IR node object" unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_add_node: right_node is not an IR node object" unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if (defined $source_info) {
            my $left_type = $type_inference->infer_type($left_node);
            my $right_type = $type_inference->infer_type($right_node);

            if (defined $left_type || defined $right_type) {
                my $validator = Chalk::IR::ValidationContext->new(
                    context => $context,
                    graph => $graph
                );
                $validator->validate_type_operation('Add', $left_type, $right_type, $source_info);
            }
        }

        my $node_id = $self->next_node_id();
        my $add = Chalk::IR::Node::Add->new(
            id => $node_id,
            inputs => [$current_control, $left_node->id, $right_node->id],
            left_id => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $graph->add_node($add);

        # Record transformation
        $add->record_transform('ir_construction', 'Builder::build_add_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $add;
    }

    method build_multiply_node($left_node, $right_node, $source_info = undef) {
        die "build_multiply_node: left_node is undefined" unless defined($left_node);
        die "build_multiply_node: right_node is undefined" unless defined($right_node);
        die "build_multiply_node: left_node is not an IR node object" unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_multiply_node: right_node is not an IR node object" unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if (defined $source_info) {
            my $left_type = $type_inference->infer_type($left_node);
            my $right_type = $type_inference->infer_type($right_node);

            if (defined $left_type || defined $right_type) {
                my $validator = Chalk::IR::ValidationContext->new(
                    context => $context,
                    graph => $graph
                );
                $validator->validate_type_operation('Multiply', $left_type, $right_type, $source_info);
            }
        }

        my $node_id = $self->next_node_id();
        my $mul = Chalk::IR::Node::Multiply->new(
            id => $node_id,
            inputs => [$current_control, $left_node->id, $right_node->id],
            left_id => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $graph->add_node($mul);

        # Record transformation
        $mul->record_transform('ir_construction', 'Builder::build_multiply_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $mul;
    }

    method build_sub_node($left_node, $right_node, $source_info = undef) {
        die "build_sub_node: left_node is undefined" unless defined($left_node);
        die "build_sub_node: right_node is undefined" unless defined($right_node);
        die "build_sub_node: left_node is not an IR node object" unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_sub_node: right_node is not an IR node object" unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if (defined $source_info) {
            my $left_type = $type_inference->infer_type($left_node);
            my $right_type = $type_inference->infer_type($right_node);

            if (defined $left_type || defined $right_type) {
                my $validator = Chalk::IR::ValidationContext->new(
                    context => $context,
                    graph => $graph
                );
                $validator->validate_type_operation('Subtract', $left_type, $right_type, $source_info);
            }
        }

        my $node_id = $self->next_node_id();
        my $sub = Chalk::IR::Node::Subtract->new(
            id => $node_id,
            inputs => [$current_control, $left_node->id, $right_node->id],
            left_id => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $graph->add_node($sub);

        # Record transformation
        $sub->record_transform('ir_construction', 'Builder::build_sub_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $sub;
    }

    method build_divide_node($left_node, $right_node, $source_info = undef) {
        die "build_divide_node: left_node is undefined" unless defined($left_node);
        die "build_divide_node: right_node is undefined" unless defined($right_node);
        die "build_divide_node: left_node is not an IR node object" unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_divide_node: right_node is not an IR node object" unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if (defined $source_info) {
            my $left_type = $type_inference->infer_type($left_node);
            my $right_type = $type_inference->infer_type($right_node);

            if (defined $left_type || defined $right_type) {
                my $validator = Chalk::IR::ValidationContext->new(
                    context => $context,
                    graph => $graph
                );
                $validator->validate_type_operation('Divide', $left_type, $right_type, $source_info);
            }
        }

        my $node_id = $self->next_node_id();
        my $div = Chalk::IR::Node::Divide->new(
            id => $node_id,
            inputs => [$current_control, $left_node->id, $right_node->id],
            left_id => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $graph->add_node($div);

        # Record transformation
        $div->record_transform('ir_construction', 'Builder::build_divide_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $div;
    }

    # Generate label with loop depth if inside a loop
    method make_variable_label($var_name) {
        if ($loop_depth > 0) {
            return "lexical:loop_" . ($loop_depth - 1) . ":$var_name";
        }
        return "lexical:$var_name";
    }

    # Create Store node (variable assignment)
    method build_store_node($var_name, $value_node, $control = undef, $source_info = undef) {
        # Validate loop variable has proper initial value if we're in a loop
        if (defined $source_info && $loop_depth > 0) {
            my $validator = Chalk::IR::ValidationContext->new(
                context => $context,
                graph => $graph
            );
            $validator->validate_loop_variable_phi($var_name, $loop_depth, $source_info);
        }

        # Store variable using lexical: namespace in context
        # Inside loops, use loop depth in label: lexical:loop_0:$var
        # Store the IR node object directly, not the node ID
        my $label = $self->make_variable_label($var_name);
        $context = Chalk::IR::Context->extend_context($context, $label, $value_node);

        # Track this variable as modified if we're in a loop
        if ($loop_depth > 0 && scalar($loop_modified_vars->@*) > 0) {
            my $current_loop_vars = $loop_modified_vars->[-1];
            $current_loop_vars->{$var_name} = 1;
        }

        return $value_node;
    }

    # Load node (variable read)
    method build_load_node($var_name, $source_info = undef) {
        # Retrieve variable using lexical: namespace from context
        # Try loop-scoped label first, then fall back to outer scope
        # Context now stores IR node objects directly, not node IDs
        my $node;

        # Try current loop depth first (search from innermost to outermost)
        if ($loop_depth > 0) {
            my $depth = $loop_depth - 1;
            while ($depth >= 0) {
                my $label = "lexical:loop_${depth}:$var_name";
                $node = $context->($label);
                last if defined($node);
                $depth--;
            }
        }

        # Fall back to non-loop lexical scope
        $node //= $context->("lexical:$var_name");

        # Validate that variable exists if source_info provided
        if (defined $source_info && !defined $node) {
            my $validator = Chalk::IR::ValidationContext->new(
                context => $context,
                graph => $graph
            );
            $node = $validator->validate_variable_defined($var_name, $source_info);
        }

        # Return the node directly from context (no graph lookup needed)
        return $node;
    }

    # Create Proj node (projection from MultiNode like Start)
    method build_proj_node($source_node, $index, $label) {
        my $node_id = $self->next_node_id();
        my $proj = Chalk::IR::Node::Proj->new(
            id            => $node_id,
            inputs        => [$source_node->id],
            index         => $index,
            label         => $label,
        );
        $graph->add_node($proj);

        # Record transformation
        $proj->record_transform('ir_construction', 'Builder::build_proj_node',
            context => "source_id=" . $source_node->id . ", index=$index, label=$label"
        );

        return $proj;
    }

    # Comparison nodes
    method build_greater_node($left_node, $right_node) {
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node::GT->new(
            id            => $node_id,
            inputs        => [$current_control, $left_node->id, $right_node->id],
            left_id       => $left_node->id,
            right_id      => $right_node->id,
        );
        $graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform('ir_construction', 'Builder::build_greater_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $cmp;
    }

    method build_less_node($left_node, $right_node) {
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node::LT->new(
            id            => $node_id,
            inputs        => [$current_control, $left_node->id, $right_node->id],
            left_id       => $left_node->id,
            right_id      => $right_node->id,
        );
        $graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform('ir_construction', 'Builder::build_less_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $cmp;
    }

    method build_equal_node($left_node, $right_node) {
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node::EQ->new(
            id            => $node_id,
            inputs        => [$current_control, $left_node->id, $right_node->id],
            left_id       => $left_node->id,
            right_id      => $right_node->id,
        );
        $graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform('ir_construction', 'Builder::build_equal_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $cmp;
    }

    method build_greater_or_equal_node($left_node, $right_node) {
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node::GE->new(
            id            => $node_id,
            inputs        => [$current_control, $left_node->id, $right_node->id],
            left_id       => $left_node->id,
            right_id      => $right_node->id,
        );
        $graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform('ir_construction', 'Builder::build_greater_or_equal_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $cmp;
    }

    method build_less_or_equal_node($left_node, $right_node) {
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node::LE->new(
            id            => $node_id,
            inputs        => [$current_control, $left_node->id, $right_node->id],
            left_id       => $left_node->id,
            right_id      => $right_node->id,
        );
        $graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform('ir_construction', 'Builder::build_less_or_equal_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $cmp;
    }

    method build_not_equal_node($left_node, $right_node) {
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node::NE->new(
            id            => $node_id,
            inputs        => [$current_control, $left_node->id, $right_node->id],
            left_id       => $left_node->id,
            right_id      => $right_node->id,
        );
        $graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform('ir_construction', 'Builder::build_not_equal_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $cmp;
    }

    # Unary operation nodes
    method build_not_node($operand_node) {
        my $node_id = $self->next_node_id();
        my $not = Chalk::IR::Node::Not->new(
            id            => $node_id,
            inputs        => [$current_control, $operand_node->id],
            operand_id    => $operand_node->id,
        );
        $graph->add_node($not);

        # Record transformation
        $not->record_transform('ir_construction', 'Builder::build_not_node',
            context => "operand_id=" . $operand_node->id
        );

        return $not;
    }

    method build_negate_node($operand_node) {
        my $node_id = $self->next_node_id();
        my $negate = Chalk::IR::Node::Negate->new(
            id            => $node_id,
            inputs        => [$current_control, $operand_node->id],
            operand_id    => $operand_node->id,
        );
        $graph->add_node($negate);

        # Record transformation
        $negate->record_transform('ir_construction', 'Builder::build_negate_node',
            context => "operand_id=" . $operand_node->id
        );

        return $negate;
    }

    method build_pre_increment_node($operand_node) {
        my $node_id = $self->next_node_id();
        my $pre_inc = Chalk::IR::Node::PreIncrement->new(
            id            => $node_id,
            inputs        => [$current_control, $operand_node->id],
            operand_id    => $operand_node->id,
        );
        $graph->add_node($pre_inc);

        # Record transformation
        $pre_inc->record_transform('ir_construction', 'Builder::build_pre_increment_node',
            context => "operand_id=" . $operand_node->id
        );

        return $pre_inc;
    }

    method build_pre_decrement_node($operand_node) {
        my $node_id = $self->next_node_id();
        my $pre_dec = Chalk::IR::Node::PreDecrement->new(
            id            => $node_id,
            inputs        => [$current_control, $operand_node->id],
            operand_id    => $operand_node->id,
        );
        $graph->add_node($pre_dec);

        # Record transformation
        $pre_dec->record_transform('ir_construction', 'Builder::build_pre_decrement_node',
            context => "operand_id=" . $operand_node->id
        );

        return $pre_dec;
    }

    method build_post_increment_node($operand_node) {
        my $node_id = $self->next_node_id();
        my $post_inc = Chalk::IR::Node::PostIncrement->new(
            id            => $node_id,
            inputs        => [$current_control, $operand_node->id],
            operand_id    => $operand_node->id,
        );
        $graph->add_node($post_inc);

        # Record transformation
        $post_inc->record_transform('ir_construction', 'Builder::build_post_increment_node',
            context => "operand_id=" . $operand_node->id
        );

        return $post_inc;
    }

    method build_post_decrement_node($operand_node) {
        my $node_id = $self->next_node_id();
        my $post_dec = Chalk::IR::Node::PostDecrement->new(
            id            => $node_id,
            inputs        => [$current_control, $operand_node->id],
            operand_id    => $operand_node->id,
        );
        $graph->add_node($post_dec);

        # Record transformation
        $post_dec->record_transform('ir_construction', 'Builder::build_post_decrement_node',
            context => "operand_id=" . $operand_node->id
        );

        return $post_dec;
    }

    # OLD: This will be removed - use build_scalar_ref_node instead
    method build_reference_node($operand_node) {
        my $node_id = $self->next_node_id();
        my $reference = Chalk::IR::Node::Reference->new(
            id            => $node_id,
            inputs        => [$current_control],
            target_context => $context,  # Current context
            target_label   => 'UNKNOWN',  # This is deprecated
        );
        $graph->add_node($reference);

        # Record transformation
        $reference->record_transform('ir_construction', 'Builder::build_reference_node',
            context => "label=UNKNOWN (deprecated)"
        );

        return $reference;
    }

    # Control flow nodes
    method build_if_node($condition_node) {
        my $node_id = $self->next_node_id();
        my $if_node = Chalk::IR::Node::If->new(
            id            => $node_id,
            inputs        => [$current_control, $condition_node->id],
            condition_id  => $condition_node->id,
        );
        $graph->add_node($if_node);

        # Record transformation
        $if_node->record_transform('ir_construction', 'Builder::build_if_node',
            context => "condition_id=" . $condition_node->id
        );

        return $if_node;
    }

    method build_if_true_node($if_node) {
        my $if_true = $self->build_proj_node($if_node, 0, 'IfTrue');
        return $if_true;
    }

    method build_if_false_node($if_node) {
        my $if_false = $self->build_proj_node($if_node, 1, 'IfFalse');
        return $if_false;
    }

    method build_region_node($source_info = undef, @control_inputs) {
        # Validate control flow merge if source_info provided
        if (defined $source_info) {
            my $validator = Chalk::IR::ValidationContext->new(
                context => $context,
                graph => $graph
            );
            $validator->validate_control_merge(\@control_inputs, $source_info);
        }

        my $node_id = $self->next_node_id();
        my $region = Chalk::IR::Node::Region->new(
            id            => $node_id,
            inputs        => \@control_inputs,
            source_info   => $source_info,
        );
        $graph->add_node($region);

        # Record transformation
        $region->record_transform('ir_construction', 'Builder::build_region_node',
            context => "inputs=" . join(", ", @control_inputs)
        );

        return $region;
    }

    method build_phi_node($region_node, @value_inputs) {
        my $node_id = $self->next_node_id();
        my $phi = Chalk::IR::Node::Phi->new(
            id            => $node_id,
            inputs        => [$region_node->id, @value_inputs],
            region_id     => $region_node->id,
        );
        $graph->add_node($phi);

        # Record transformation
        $phi->record_transform('ir_construction', 'Builder::build_phi_node',
            context => "region_id=" . $region_node->id . ", value_inputs=" . join(", ", @value_inputs)
        );

        return $phi;
    }

    # Loop control flow nodes
    method build_loop_node($entry_control = undef) {
        my $ctrl = $entry_control // $current_control // '__CONTROL_PLACEHOLDER__';
        my $node_id = $self->next_node_id();
        my $loop = Chalk::IR::Node::Loop->new(
            id            => $node_id,
            inputs        => [$ctrl],  # Entry control; backedge added later
        );
        $graph->add_node($loop);

        # Record transformation
        $loop->record_transform('ir_construction', 'Builder::build_loop_node',
            context => "entry_control=$ctrl"
        );

        return $loop;
    }

    method build_loop_phi_node($loop_node, $initial_value, $loop_value = undef) {
        # Loop phi starts with control and initial value
        # Loop value added later (lazy phi pattern)
        my @inputs = ($loop_node->id, $initial_value);
        push(@inputs, $loop_value) if defined($loop_value);

        my $node_id = $self->next_node_id();
        my $phi = Chalk::IR::Node::Phi->new(
            id            => $node_id,
            inputs        => \@inputs,
            region_id     => $loop_node->id,
        );
        $graph->add_node($phi);

        # Record transformation
        my $loop_val_str = defined($loop_value) ? $loop_value : "undef";
        $phi->record_transform('ir_construction', 'Builder::build_loop_phi_node',
            context => "loop_id=" . $loop_node->id . ", initial=$initial_value, loop=$loop_val_str"
        );

        return $phi;
    }

    # Function call nodes
    method build_call_node($function_name, $source_info = undef, @arg_nodes) {
        # Validate arity if source_info provided
        if (defined $source_info) {
            my $arg_count = scalar(@arg_nodes);
            my $validator = Chalk::IR::ValidationContext->new(
                context => $context,
                graph => $graph
            );
            $validator->validate_call_arity($function_name, $arg_count, $source_info);
        }

        # Call: control, memory, arguments...
        # For now, use current_control for both control and memory
        my $attributes = { function => $function_name };
        my $node_id = $self->next_node_id();
        my $call = Chalk::IR::Node->new(
            id            => $node_id,
            op            => 'Call',
            inputs        => [$current_control, $current_control, map { $_->id } @arg_nodes],
            attributes    => $attributes,
            source_info   => $source_info,
        );
        $graph->add_node($call);

        # Record transformation
        my $arg_ids = join(", ", map { $_->id } @arg_nodes);
        $call->record_transform('ir_construction', 'Builder::build_call_node',
            context => "function=$function_name, args=[$arg_ids]"
        );

        return $call;
    }

    # Loop depth tracking methods
    method begin_loop_tracking() {
        # Increment loop depth when entering a loop
        $loop_depth++;
        # Push a new set to track modified variables at this loop depth
        push $loop_modified_vars->@*, {};
        return;
    }

    method end_loop_tracking() {
        # Decrement loop depth when exiting a loop
        if ($loop_depth > 0) {
            $loop_depth--;
            # Pop the modified variables set for this loop
            pop $loop_modified_vars->@* if scalar($loop_modified_vars->@*) > 0;
        }
        return;
    }

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
        return \%phi_nodes unless scalar($loop_modified_vars->@*) > 0;

        # Get the current loop's modified variables
        my $modified_vars = $loop_modified_vars->[-1];

        # For each modified variable, create a phi node
        for my $var_name (keys($modified_vars->%*)) {
            # Get pre-loop value (lexical:$var)
            my $pre_loop_label = "lexical:$var_name";
            my $pre_loop_value = $context->($pre_loop_label);

            # Get loop-modified value (lexical:loop_N:$var where N = current depth - 1)
            my $loop_label = "lexical:loop_" . ($loop_depth - 1) . ":$var_name";
            my $loop_value = $context->($loop_label);

            # Only create phi if both values exist
            if (defined($pre_loop_value) && defined($loop_value)) {
                # Build phi node with: control (loop), initial value, loop value
                my $phi = $self->build_loop_phi_node(
                    $loop_node,
                    (ref($pre_loop_value) ? $pre_loop_value->id : $pre_loop_value),
                    (ref($loop_value) ? $loop_value->id : $loop_value)
                );
                $phi_nodes{$var_name} = $phi;
            }
        }

        return \%phi_nodes;
    }

    # Class and object support nodes (Issue #98 Phase 1)

    method build_classdef_node($class_name, $fields) {
        # Create ClassDef node for class definition
        my $attributes = {
            name => $class_name,
            fields => $fields,
        };
        my $node_id = $self->next_node_id();
        my $classdef = Chalk::IR::Node->new(
            id            => $node_id,
            op            => 'ClassDef',
            inputs        => [$current_control],
            attributes    => $attributes,
        );
        $graph->add_node($classdef);

        # Record transformation
        my $field_names = join(", ", $fields->@*);
        $classdef->record_transform('ir_construction', 'Builder::build_classdef_node',
            context => "class=$class_name, fields=[$field_names]"
        );

        return $classdef;
    }

    method build_new_node($class_name, $field_values_hash) {
        # Create New node for object instantiation
        # $field_values_hash is a hashref mapping field names to node objects
        my @input_nodes = ($current_control);
        my %field_value_refs;

        # Build field references from hash
        for my $field_name (sort( keys( $field_values_hash->%* ) )) {
            my $value_node = $field_values_hash->{$field_name};
            push(@input_nodes, $value_node->id);
            $field_value_refs{$field_name} = {
                op => 'NodeRef',
                node_id => $value_node->id
            };
        }

        my $attributes = {
            class => $class_name,
            field_values => \%field_value_refs
        };
        my $node_id = $self->next_node_id();
        my $new_obj = Chalk::IR::Node->new(
            id            => $node_id,
            op            => 'New',
            inputs        => \@input_nodes,
            attributes    => $attributes,
        );
        $graph->add_node($new_obj);

        # Record transformation
        my $field_names = join(", ", sort(keys($field_values_hash->%*)));
        $new_obj->record_transform('ir_construction', 'Builder::build_new_node',
            context => "class=$class_name, fields=[$field_names]"
        );

        return $new_obj;
    }

    method build_field_access_node($object_node, $field_name, $source_info = undef) {
        # Validate field exists in class if source_info provided
        if (defined $source_info) {
            my $class_name = $type_inference->infer_class($object_node);
            if (defined $class_name) {
                my $validator = Chalk::IR::ValidationContext->new(
                    context => $context,
                    graph => $graph
                );
                $validator->validate_class_field($class_name, $field_name, $source_info);
            }
        }

        # Create FieldAccess node for reading a field
        my $object_ref = { op => 'NodeRef', node_id => $object_node->id };
        my $attributes = {
            field => $field_name,
            object => $object_ref
        };
        my $node_id = $self->next_node_id();
        my $field_access = Chalk::IR::Node->new(
            id            => $node_id,
            op            => 'FieldAccess',
            inputs        => [$current_control, $object_node->id],
            attributes    => $attributes,
            source_info   => $source_info,
        );
        $graph->add_node($field_access);

        # Record transformation
        $field_access->record_transform('ir_construction', 'Builder::build_field_access_node',
            context => "object_id=" . $object_node->id . ", field=$field_name"
        );

        return $field_access;
    }

    method build_field_store_node($object_node, $field_name, $value_node) {
        # Create FieldStore node for writing to a field
        my $object_ref = { op => 'NodeRef', node_id => $object_node->id };
        my $value_ref = { op => 'NodeRef', node_id => $value_node->id };
        my $attributes = {
            field => $field_name,
            object => $object_ref,
            value => $value_ref
        };
        my $node_id = $self->next_node_id();
        my $field_store = Chalk::IR::Node->new(
            id            => $node_id,
            op            => 'FieldStore',
            inputs        => [$current_control, $object_node->id, $value_node->id],
            attributes    => $attributes,
        );
        $graph->add_node($field_store);

        # Record transformation
        $field_store->record_transform('ir_construction', 'Builder::build_field_store_node',
            context => "object_id=" . $object_node->id . ", field=$field_name, value_id=" . $value_node->id
        );

        return $field_store;
    }

    # Array operations (Issue #98 Phase 2)
    method build_array_new_node() {
        # Create ArrayNew node for creating an empty array
        my $node_id = $self->next_node_id();
        my $array_new = Chalk::IR::Node->new(
            id => $node_id,
            op => 'ArrayNew',
            inputs => [$current_control],
            attributes => {},
        );
        $graph->add_node($array_new);

        # Record transformation
        $array_new->record_transform('ir_construction', 'Builder::build_array_new_node',
            context => "empty_array"
        );

        return $array_new;
    }

    method build_array_push_node($array_node, $value_node) {
        # Create ArrayPush node for appending to array
        my $array_ref = { op => 'NodeRef', node_id => $array_node->id };
        my $value_ref = { op => 'NodeRef', node_id => $value_node->id };
        my $attributes = {
            array => $array_ref,
            value => $value_ref
        };
        my $node_id = $self->next_node_id();
        my $array_push = Chalk::IR::Node->new(
            id => $node_id,
            op => 'ArrayPush',
            inputs => [$current_control, $array_node->id, $value_node->id],
            attributes => $attributes,
        );
        $graph->add_node($array_push);

        # Record transformation
        $array_push->record_transform('ir_construction', 'Builder::build_array_push_node',
            context => "array_id=" . $array_node->id . ", value_id=" . $value_node->id
        );

        return $array_push;
    }

    method build_array_get_node($array_node, $index_node) {
        # Create ArrayGet node for accessing array element by index using context lookup
        my $node_id = $self->next_node_id();
        my $array_get = Chalk::IR::Node::ArrayGet->new(
            id => $node_id,
            inputs => [$current_control, $array_node->id, $index_node->id],
            array_id => $array_node->id,
            index_id => $index_node->id,
        );
        $graph->add_node($array_get);

        # Record transformation
        $array_get->record_transform('ir_construction', 'Builder::build_array_get_node',
            context => "array_id=" . $array_node->id . ", index_id=" . $index_node->id
        );

        return $array_get;
    }

    method build_array_set_node($array_node, $index_node, $value_node) {
        # Create ArraySet node for setting array element with context extension (immutable)
        my $node_id = $self->next_node_id();
        my $array_set = Chalk::IR::Node::ArraySet->new(
            id => $node_id,
            inputs => [$current_control, $array_node->id, $index_node->id, $value_node->id],
            array_id => $array_node->id,
            index_id => $index_node->id,
            value_id => $value_node->id,
        );
        $graph->add_node($array_set);

        # Record transformation
        $array_set->record_transform('ir_construction', 'Builder::build_array_set_node',
            context => "array_id=" . $array_node->id . ", index_id=" . $index_node->id . ", value_id=" . $value_node->id
        );

        return $array_set;
    }

    method build_array_length_node($array_node) {
        # Create ArrayLength node for getting array size
        my $array_ref = { op => 'NodeRef', node_id => $array_node->id };
        my $attributes = {
            array => $array_ref
        };
        my $node_id = $self->next_node_id();
        my $array_length = Chalk::IR::Node->new(
            id => $node_id,
            op => 'ArrayLength',
            inputs => [$current_control, $array_node->id],
            attributes => $attributes,
        );
        $graph->add_node($array_length);

        # Record transformation
        $array_length->record_transform('ir_construction', 'Builder::build_array_length_node',
            context => "array_id=" . $array_node->id
        );

        return $array_length;
    }

    # Hash operations (Issue #98 Phase 3)
    method build_hash_new_node() {
        # Create HashNew node for creating an empty hash
        my $node_id = $self->next_node_id();
        my $hash_new = Chalk::IR::Node->new(
            id => $node_id,
            op => 'HashNew',
            inputs => [$current_control],
            attributes => {},
        );
        $graph->add_node($hash_new);

        # Record transformation
        $hash_new->record_transform('ir_construction', 'Builder::build_hash_new_node',
            context => "empty_hash"
        );

        return $hash_new;
    }

    method build_hash_set_node($hash_node, $key_node, $value_node) {
        # Create HashSet node for setting hash value with context extension (immutable)
        my $node_id = $self->next_node_id();
        my $hash_set = Chalk::IR::Node::HashSet->new(
            id => $node_id,
            inputs => [$current_control, $hash_node->id, $key_node->id, $value_node->id],
            hash_id => $hash_node->id,
            key_id => $key_node->id,
            value_id => $value_node->id,
        );
        $graph->add_node($hash_set);

        # Record transformation
        $hash_set->record_transform('ir_construction', 'Builder::build_hash_set_node',
            context => "hash_id=" . $hash_node->id . ", key_id=" . $key_node->id . ", value_id=" . $value_node->id
        );

        return $hash_set;
    }

    method build_hash_get_node($hash_node, $key_node) {
        # Create HashGet node for accessing hash value by key using context lookup
        my $node_id = $self->next_node_id();
        my $hash_get = Chalk::IR::Node::HashGet->new(
            id => $node_id,
            inputs => [$current_control, $hash_node->id, $key_node->id],
            hash_id => $hash_node->id,
            key_id => $key_node->id,
        );
        $graph->add_node($hash_get);

        # Record transformation
        $hash_get->record_transform('ir_construction', 'Builder::build_hash_get_node',
            context => "hash_id=" . $hash_node->id . ", key_id=" . $key_node->id
        );

        return $hash_get;
    }

    method build_hash_exists_node($hash_node, $key_node) {
        # Create HashExists node for checking if key exists in hash
        my $hash_ref = { op => 'NodeRef', node_id => $hash_node->id };
        my $key_ref = { op => 'NodeRef', node_id => $key_node->id };
        my $attributes = {
            hash => $hash_ref,
            key => $key_ref
        };
        my $node_id = $self->next_node_id();
        my $hash_exists = Chalk::IR::Node->new(
            id => $node_id,
            op => 'HashExists',
            inputs => [$current_control, $hash_node->id, $key_node->id],
            attributes => $attributes,
        );
        $graph->add_node($hash_exists);

        # Record transformation
        $hash_exists->record_transform('ir_construction', 'Builder::build_hash_exists_node',
            context => "hash_id=" . $hash_node->id . ", key_id=" . $key_node->id
        );

        return $hash_exists;
    }

    method build_hash_keys_node($hash_node) {
        # Create HashKeys node for getting all keys from hash
        my $hash_ref = { op => 'NodeRef', node_id => $hash_node->id };
        my $attributes = {
            hash => $hash_ref
        };
        my $node_id = $self->next_node_id();
        my $hash_keys = Chalk::IR::Node->new(
            id => $node_id,
            op => 'HashKeys',
            inputs => [$current_control, $hash_node->id],
            attributes => $attributes,
        );
        $graph->add_node($hash_keys);

        # Record transformation
        $hash_keys->record_transform('ir_construction', 'Builder::build_hash_keys_node',
            context => "hash_id=" . $hash_node->id
        );

        return $hash_keys;
    }

    # String operations (Issue #98 Phase 4)
    method build_str_concat_node($left_node, $right_node) {
        # Create StrConcat node for concatenating two strings
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };

        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };

        my $node_id = $self->next_node_id();
        my $str_concat = Chalk::IR::Node->new(
            id => $node_id,
            op => 'StrConcat',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes,
        );
        $graph->add_node($str_concat);

        # Record transformation
        $str_concat->record_transform('ir_construction', 'Builder::build_str_concat_node',
            context => "left_id=" . $left_node->id . ", right_id=" . $right_node->id
        );

        return $str_concat;
    }

    # Range operations (Issue #111)
    method build_range_node($start_node, $end_node, $type = 'list') {
        # Create Range node for generating a range between start and end values
        my $start_ref = { op => 'NodeRef', node_id => $start_node->id };
        my $end_ref = { op => 'NodeRef', node_id => $end_node->id };

        my $attributes = {
            start => $start_ref,
            end => $end_ref,
            type => $type,
        };

        my $node_id = $self->next_node_id();
        my $range = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Range',
            inputs => [$current_control, $start_node->id, $end_node->id],
            attributes => $attributes,
        );
        $graph->add_node($range);

        # Record transformation
        $range->record_transform('ir_construction', 'Builder::build_range_node',
            context => "start_id=" . $start_node->id . ", end_id=" . $end_node->id . ", type=$type"
        );

        return $range;
    }

    method build_str_length_node($string_node) {
        # Create StrLength node for getting string length
        my $string_ref = { op => 'NodeRef', node_id => $string_node->id };

        my $attributes = {
            string => $string_ref
        };

        my $node_id = $self->next_node_id();
        my $str_length = Chalk::IR::Node->new(
            id => $node_id,
            op => 'StrLength',
            inputs => [$current_control, $string_node->id],
            attributes => $attributes,
        );
        $graph->add_node($str_length);

        # Record transformation
        $str_length->record_transform('ir_construction', 'Builder::build_str_length_node',
            context => "string_id=" . $string_node->id
        );

        return $str_length;
    }

    method build_str_substr_node($string_node, $offset_node, $length_node) {
        # Create StrSubstr node for extracting substring
        my $string_ref = { op => 'NodeRef', node_id => $string_node->id };
        my $offset_ref = { op => 'NodeRef', node_id => $offset_node->id };
        my $length_ref = { op => 'NodeRef', node_id => $length_node->id };

        my $attributes = {
            string => $string_ref,
            offset => $offset_ref,
            length => $length_ref
        };

        my $node_id = $self->next_node_id();
        my $str_substr = Chalk::IR::Node->new(
            id => $node_id,
            op => 'StrSubstr',
            inputs => [$current_control, $string_node->id, $offset_node->id, $length_node->id],
            attributes => $attributes,
        );
        $graph->add_node($str_substr);

        # Record transformation
        $str_substr->record_transform('ir_construction', 'Builder::build_str_substr_node',
            context => "string_id=" . $string_node->id . ", offset_id=" . $offset_node->id . ", length_id=" . $length_node->id
        );

        return $str_substr;
    }

    # Module system support (Issue #98 Phase 5)
    method build_use_statement_node($type, $module, $imports) {
        # Create UseStatement node for capturing use statement metadata
        # $type: 'version', 'pragma', 'module', or 'external'
        # $module: module name (e.g., '5.42.0', 'experimental', 'Chalk::IR::Node')
        # $imports: arrayref of imported symbols (empty for full import)

        my $graph = $self->graph;
        my $current_control = $self->current_control;

        my $attributes = {
            type => $type,
            module => $module,
            imports => $imports
        };

        my $node_id = $self->next_node_id();
        my $use_stmt = Chalk::IR::Node->new(
            id => $node_id,
            op => 'UseStatement',
            inputs => [$current_control],
            attributes => $attributes,
        );
        $graph->add_node($use_stmt);

        # Record transformation
        my $import_list = join(", ", $imports->@*);
        $use_stmt->record_transform('ir_construction', 'Builder::build_use_statement_node',
            context => "type=$type, module=$module, imports=[$import_list]"
        );

        return $use_stmt;
    }

    # Reference operations (Issue #130 Phase 4)

    # Create reference to a scalar variable: \$x
    method build_scalar_ref_node($var_name, $source_info = undef) {
        my $label = "lexical:$var_name";

        # Validate reference target if source_info provided
        my $target_node_or_id;
        if (defined $source_info) {
            my $validator = Chalk::IR::ValidationContext->new(
                context => $context,
                graph => $graph
            );
            $target_node_or_id = $validator->validate_reference_target($label, $source_info);
        } else {
            # Look up the target node (might be object or ID)
            $target_node_or_id = $context->($label);
            die "Cannot create reference to undefined variable $var_name" unless defined($target_node_or_id);
        }

        # Get the node ID for the dependency
        my $target_node_id = ref($target_node_or_id) ? $target_node_or_id->id : $target_node_or_id;

        my $node_id = $self->next_node_id();
        my $reference = Chalk::IR::Node::Reference->new(
            id             => $node_id,
            inputs         => [$current_control, $target_node_id],  # Add target as dependency
            target_context => $context,
            target_label   => $label,
            source_info    => $source_info,
        );
        $graph->add_node($reference);

        # Record transformation
        $reference->record_transform('ir_construction', 'Builder::build_scalar_ref_node',
            context => "var=$var_name, target_id=$target_node_id"
        );

        return $reference;
    }

    # Create reference to array element: \$arr[1]
    method build_element_ref_node($collection_name, $index_node) {
        # Get the collection from context (might be object or ID)
        my $collection_label = "lexical:$collection_name";
        my $collection_node_or_id = $context->($collection_label);

        # Get the collection node
        my $collection_node;
        if (ref($collection_node_or_id)) {
            $collection_node = $collection_node_or_id;
        } else {
            $collection_node = $graph->get_node($collection_node_or_id);
        }

        # Get the array context from the collection node
        my $array_ctx = $collection_node->array_context;

        # Get the index value - need to evaluate it
        # For now, assume it's a constant node
        my $index_val = $index_node->value;

        # Create the reference pointing to the array context with index: label
        my $label = Chalk::IR::Context->make_index_label($index_val);
        my $node_id = $self->next_node_id();
        my $reference = Chalk::IR::Node::Reference->new(
            id             => $node_id,
            inputs         => [$current_control, $collection_node->id, $index_node->id],
            target_context => $array_ctx,
            target_label   => $label,
        );
        $graph->add_node($reference);

        # Record transformation
        $reference->record_transform('ir_construction', 'Builder::build_element_ref_node',
            context => "collection=$collection_name, index_id=" . $index_node->id . ", index_val=$index_val"
        );

        return $reference;
    }

    # Dereference a scalar reference: $$ref
    method build_scalar_deref_node($ref_var_name) {
        # Get the reference from context (might be object or ID)
        my $ref_label = "lexical:$ref_var_name";
        my $ref_node_or_id = $context->($ref_label);

        # Get the node ID
        my $ref_id = ref($ref_node_or_id) ? $ref_node_or_id->id : $ref_node_or_id;

        # Create ScalarDeref node
        my $node_id = $self->next_node_id();
        my $deref = Chalk::IR::Node::ScalarDeref->new(
            id      => $node_id,
            inputs  => [$current_control, $ref_id],
            ref_id  => $ref_id,
        );
        $graph->add_node($deref);

        # Record transformation
        $deref->record_transform('ir_construction', 'Builder::build_scalar_deref_node',
            context => "var=$ref_var_name, ref_id=$ref_id"
        );

        return $deref;
    }

    # Read variable from context: helper for tests
    method build_variable_read_node($var_name) {
        my $label = "lexical:$var_name";
        my $node_id = $self->next_node_id();
        my $var_read = Chalk::IR::Node::VariableRead->new(
            id        => $node_id,
            inputs    => [$current_control],
            var_label => $label,
        );
        $graph->add_node($var_read);

        # Record transformation
        $var_read->record_transform('ir_construction', 'Builder::build_variable_read_node',
            context => "var=$var_name"
        );

        return $var_read;
    }

    # Assign through a dereferenced reference: $$ref = value
    method build_scalar_deref_assign_node($ref_var_name, $value_node) {
        # Get the reference from context
        my $ref_label = "lexical:$ref_var_name";
        my $ref_node_or_id = $context->($ref_label);

        # Might be node object or node ID depending on when it was stored
        my $ref_node;
        if (ref($ref_node_or_id)) {
            $ref_node = $ref_node_or_id;
        } else {
            $ref_node = $graph->get_node($ref_node_or_id);
        }

        # Get the target label from the reference
        my $target_label = $ref_node->target_label;

        # Extend the BUILDER's current context with the new value (node object, not ID)
        # This updates the variable that the reference points to
        $context = Chalk::IR::Context->extend_context(
            $context,
            $target_label,
            $value_node
        );

        # Return the value node for chaining
        return $value_node;
    }

}

1;

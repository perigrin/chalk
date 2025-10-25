# ABOUTME: IR builder for transforming parsed Chalk code into Sea of Nodes IR
# ABOUTME: Provides methods called by semantic actions to build IR nodes during parsing
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::IR::Builder {
    use Chalk::IR::Node;
    use Chalk::IR::Graph;
    use Chalk::IR::Scope;

    field $graph :reader;
    field $scope :reader;
    field $node_counter :reader = 0;
    field $current_control :reader;  # Current control flow node
    field $loop_entry_scope;  # Snapshot of scope bindings at loop entry
    field $loop_tracking_active = 0;  # Whether loop tracking is active

    ADJUST {
        $graph = Chalk::IR::Graph->new();
        $scope = Chalk::IR::Scope->new();
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

    # Create Start node for a function/method
    method build_start_node($function_name = 'main', $params = undef) {
        $params //= [];
        my $node_id = $self->next_node_id();
        my $empty_inputs = [];
        my $attributes = { function => $function_name, params => $params };
        my $start = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Start',
            inputs => $empty_inputs,
            attributes => $attributes
        );
        $graph->add_node($start);
        $self->set_control($start->id);

        # Create Proj nodes for each parameter and register in scope
        my $param_count = scalar($params->@*);
        for my $i (0..($param_count - 1)) {
            my $param_name = $params->[$i];
            my $proj = $self->build_proj_node($start, $i, $param_name);
            # Register parameter Proj in scope so lookups return it directly
            $scope->define($param_name, $proj->id);
        }

        return $start;
    }

    # Create Constant node
    method build_constant_node($value, $type = 'Int') {
        my $node_id = $self->next_node_id();
        my $attributes = { value => $value, type => $type };
        my $constant = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Constant',
            inputs => [$current_control],
            attributes => $attributes
        );
        $graph->add_node($constant);
        return $constant;
    }

    # Create Return node
    # If $control is undef, uses current_control. Otherwise uses provided control.
    method build_return_node($value_node, $control = undef) {
        # Debug: check what we received
        my $ref_type = ref($value_node) || 'SCALAR';
        my $prefix = substr($ref_type, 0, 15);
        my $is_node = ($prefix eq 'Chalk::IR::Node') ? 1 : 0;
        unless ($ref_type && $is_node) {
            warn "build_return_node received non-node: $ref_type\n";
            return undef;
        }

        # Use provided control, or current_control, or '__CONTROL_PLACEHOLDER__'
        my $ctrl = $control // $current_control // '__CONTROL_PLACEHOLDER__';

        my $node_id = $self->next_node_id();
        my $empty_attrs = {};
        my $return = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Return',
            inputs => [$ctrl, $value_node->id],
            attributes => $empty_attrs
        );
        $graph->add_node($return);
        return $return;
    }

    # Set control input for an existing node
    method set_node_control($node, $control_id) {
        my $inputs = $node->inputs;
        $inputs->[0] = $control_id;  # Control is always first input
    }

    # Create arithmetic operation nodes
    method build_add_node($left_node, $right_node) {
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };
        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };
        my $node_id = $self->next_node_id();
        my $add = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Add',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes
        );
        $graph->add_node($add);
        return $add;
    }

    method build_multiply_node($left_node, $right_node) {
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };
        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };
        my $node_id = $self->next_node_id();
        my $mul = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Multiply',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes
        );
        $graph->add_node($mul);
        return $mul;
    }

    method build_sub_node($left_node, $right_node) {
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };
        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };
        my $node_id = $self->next_node_id();
        my $sub = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Sub',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes
        );
        $graph->add_node($sub);
        return $sub;
    }

    method build_divide_node($left_node, $right_node) {
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };
        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };
        my $node_id = $self->next_node_id();
        my $div = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Div',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes
        );
        $graph->add_node($div);
        return $div;
    }

    # Create Store node (variable assignment)
    method build_store_node($var_name, $value_node, $control = undef) {
        # Use provided control, or current_control, or '__CONTROL_PLACEHOLDER__'
        my $ctrl = $control // $current_control // '__CONTROL_PLACEHOLDER__';

        my $value_ref = { op => 'NodeRef', node_id => $value_node->id };
        my $attributes = {
            name => $var_name,
            value => $value_ref
        };
        my $node_id = $self->next_node_id();
        my $store = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Store',
            inputs => [$ctrl, $value_node->id],
            attributes => $attributes
        );
        $graph->add_node($store);
        $scope->define($var_name, $store->id);
        return $store;
    }

    # Create Load node (variable read)
    method build_load_node($var_name) {
        my $node_id = $scope->lookup($var_name);
        return undef unless $node_id;

        # Check if this is a Proj node (parameter) - if so, return it directly
        my $node = $graph->nodes->{$node_id};
        if ($node && $node->op eq 'Proj') {
            # Parameter: return the Proj node directly
            return $node;
        }

        # Regular variable: create Load node from Store
        my $attributes = {
            name => $var_name,
            store_id => $node_id
        };
        my $load_id = $self->next_node_id();
        my $load = Chalk::IR::Node->new(
            id => $load_id,
            op => 'Load',
            inputs => [$current_control, $node_id],
            attributes => $attributes
        );
        $graph->add_node($load);
        return $load;
    }

    # Create Proj node (projection from MultiNode like Start)
    method build_proj_node($source_node, $index, $label) {
        my $attributes = {
            index => $index,
            label => $label
        };
        my $node_id = $self->next_node_id();
        my $proj = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Proj',
            inputs => [$source_node->id],
            attributes => $attributes
        );
        $graph->add_node($proj);
        return $proj;
    }

    # Comparison nodes
    method build_greater_node($left_node, $right_node) {
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };
        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Greater',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes
        );
        $graph->add_node($cmp);
        return $cmp;
    }

    method build_less_node($left_node, $right_node) {
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };
        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Less',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes
        );
        $graph->add_node($cmp);
        return $cmp;
    }

    method build_equal_node($left_node, $right_node) {
        my $left_ref = { op => 'NodeRef', node_id => $left_node->id };
        my $right_ref = { op => 'NodeRef', node_id => $right_node->id };
        my $attributes = {
            left => $left_ref,
            right => $right_ref
        };
        my $node_id = $self->next_node_id();
        my $cmp = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Equal',
            inputs => [$current_control, $left_node->id, $right_node->id],
            attributes => $attributes
        );
        $graph->add_node($cmp);
        return $cmp;
    }

    # Control flow nodes
    method build_if_node($condition_node) {
        my $condition_ref = { op => 'NodeRef', node_id => $condition_node->id };
        my $attributes = { condition => $condition_ref };
        my $node_id = $self->next_node_id();
        my $if_node = Chalk::IR::Node->new(
            id => $node_id,
            op => 'If',
            inputs => [$current_control, $condition_node->id],
            attributes => $attributes
        );
        $graph->add_node($if_node);
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

    method build_region_node(@control_inputs) {
        my $empty_attrs = {};
        my $node_id = $self->next_node_id();
        my $region = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Region',
            inputs => \@control_inputs,
            attributes => $empty_attrs
        );
        $graph->add_node($region);
        return $region;
    }

    method build_phi_node($region_node, @value_inputs) {
        my $empty_attrs = {};
        my $node_id = $self->next_node_id();
        my $phi = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Phi',
            inputs => [$region_node->id, @value_inputs],
            attributes => $empty_attrs
        );
        $graph->add_node($phi);
        return $phi;
    }

    # Loop control flow nodes
    method build_loop_node($entry_control = undef) {
        my $ctrl = $entry_control // $current_control // '__CONTROL_PLACEHOLDER__';
        my $empty_attrs = {};
        my $node_id = $self->next_node_id();
        my $loop = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Loop',
            inputs => [$ctrl],  # Entry control; backedge added later
            attributes => $empty_attrs
        );
        $graph->add_node($loop);
        return $loop;
    }

    method build_loop_phi_node($loop_node, $initial_value, $loop_value = undef) {
        # Loop phi starts with control and initial value
        # Loop value added later (lazy phi pattern)
        my @inputs = ($loop_node->id, $initial_value);
        push @inputs, $loop_value if defined $loop_value;

        my $empty_attrs = {};
        my $node_id = $self->next_node_id();
        my $phi = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Phi',
            inputs => \@inputs,
            attributes => $empty_attrs
        );
        $graph->add_node($phi);
        return $phi;
    }

    # Function call nodes
    method build_call_node($function_name, @arg_nodes) {
        # Call: control, memory, arguments...
        # For now, use current_control for both control and memory
        my $attributes = { function => $function_name };
        my $node_id = $self->next_node_id();
        my $call = Chalk::IR::Node->new(
            id => $node_id,
            op => 'Call',
            inputs => [$current_control, $current_control, map { $_->id } @arg_nodes],
            attributes => $attributes
        );
        $graph->add_node($call);
        return $call;
    }

    # Loop-carried dependency tracking methods
    method begin_loop_tracking() {
        # Start tracking loop-carried dependencies
        $loop_entry_scope = $scope->snapshot_bindings();
        $loop_tracking_active = 1;
        return;
    }

    method end_loop_tracking() {
        # End tracking and clean up
        $loop_entry_scope = undef;
        $loop_tracking_active = 0;
        return;
    }

    method is_tracking_loop() {
        return $loop_tracking_active;
    }

    method loop_entry_scope() {
        return $loop_entry_scope;
    }

    method generate_loop_phi_nodes($loop_node) {
        # Generate phi nodes for all variables modified within the loop
        return {} unless $loop_tracking_active;
        return {} unless defined $loop_entry_scope;

        # Capture current (loop-end) values before creating phis
        my $loop_end_scope = $scope->snapshot_bindings();

        # Find which variables were modified in the loop
        my @modified_vars = $scope->find_modified_variables($loop_entry_scope);

        # Generate a phi node for each modified variable
        my %phis = ();
        for my $var (@modified_vars) {
            my $initial_value = $loop_entry_scope->{$var};
            my $loop_value = $loop_end_scope->{$var};

            # Create phi with initial value; backedge added later
            my $phi = $self->build_loop_phi_node($loop_node, $initial_value, $loop_value);
            $phis{$var} = $phi;

            # Update scope to use phi node for this variable
            # This ensures uses after the loop see the phi
            $scope->define($var, $phi->id);
        }

        return \%phis;
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
            id => $node_id,
            op => 'ClassDef',
            inputs => [$current_control],
            attributes => $attributes
        );
        $graph->add_node($classdef);
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
            push @input_nodes, $value_node->id;
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
            id => $node_id,
            op => 'New',
            inputs => \@input_nodes,
            attributes => $attributes
        );
        $graph->add_node($new_obj);
        return $new_obj;
    }

    method build_field_access_node($object_node, $field_name) {
        # Create FieldAccess node for reading a field
        my $object_ref = { op => 'NodeRef', node_id => $object_node->id };
        my $attributes = {
            field => $field_name,
            object => $object_ref
        };
        my $node_id = $self->next_node_id();
        my $field_access = Chalk::IR::Node->new(
            id => $node_id,
            op => 'FieldAccess',
            inputs => [$current_control, $object_node->id],
            attributes => $attributes
        );
        $graph->add_node($field_access);
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
            id => $node_id,
            op => 'FieldStore',
            inputs => [$current_control, $object_node->id, $value_node->id],
            attributes => $attributes
        );
        $graph->add_node($field_store);
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
            attributes => {}
        );
        $graph->add_node($array_new);
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
            attributes => $attributes
        );
        $graph->add_node($array_push);
        return $array_push;
    }

    method build_array_get_node($array_node, $index_node) {
        # Create ArrayGet node for accessing array element by index
        my $array_ref = { op => 'NodeRef', node_id => $array_node->id };
        my $index_ref = { op => 'NodeRef', node_id => $index_node->id };
        my $attributes = {
            array => $array_ref,
            index => $index_ref
        };
        my $node_id = $self->next_node_id();
        my $array_get = Chalk::IR::Node->new(
            id => $node_id,
            op => 'ArrayGet',
            inputs => [$current_control, $array_node->id, $index_node->id],
            attributes => $attributes
        );
        $graph->add_node($array_get);
        return $array_get;
    }

    method build_array_set_node($array_node, $index_node, $value_node) {
        # Create ArraySet node for setting array element by index
        my $array_ref = { op => 'NodeRef', node_id => $array_node->id };
        my $index_ref = { op => 'NodeRef', node_id => $index_node->id };
        my $value_ref = { op => 'NodeRef', node_id => $value_node->id };
        my $attributes = {
            array => $array_ref,
            index => $index_ref,
            value => $value_ref
        };
        my $node_id = $self->next_node_id();
        my $array_set = Chalk::IR::Node->new(
            id => $node_id,
            op => 'ArraySet',
            inputs => [$current_control, $array_node->id, $index_node->id, $value_node->id],
            attributes => $attributes
        );
        $graph->add_node($array_set);
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
            attributes => $attributes
        );
        $graph->add_node($array_length);
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
            attributes => {}
        );
        $graph->add_node($hash_new);
        return $hash_new;
    }

    method build_hash_set_node($hash_node, $key_node, $value_node) {
        # Create HashSet node for setting a hash key/value pair
        my $hash_ref = { op => 'NodeRef', node_id => $hash_node->id };
        my $key_ref = { op => 'NodeRef', node_id => $key_node->id };
        my $value_ref = { op => 'NodeRef', node_id => $value_node->id };
        my $attributes = {
            hash => $hash_ref,
            key => $key_ref,
            value => $value_ref
        };
        my $node_id = $self->next_node_id();
        my $hash_set = Chalk::IR::Node->new(
            id => $node_id,
            op => 'HashSet',
            inputs => [$current_control, $hash_node->id, $key_node->id, $value_node->id],
            attributes => $attributes
        );
        $graph->add_node($hash_set);
        return $hash_set;
    }

    method build_hash_get_node($hash_node, $key_node) {
        # Create HashGet node for accessing hash value by key
        my $hash_ref = { op => 'NodeRef', node_id => $hash_node->id };
        my $key_ref = { op => 'NodeRef', node_id => $key_node->id };
        my $attributes = {
            hash => $hash_ref,
            key => $key_ref
        };
        my $node_id = $self->next_node_id();
        my $hash_get = Chalk::IR::Node->new(
            id => $node_id,
            op => 'HashGet',
            inputs => [$current_control, $hash_node->id, $key_node->id],
            attributes => $attributes
        );
        $graph->add_node($hash_get);
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
            attributes => $attributes
        );
        $graph->add_node($hash_exists);
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
            attributes => $attributes
        );
        $graph->add_node($hash_keys);
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
            attributes => $attributes
        );
        $graph->add_node($str_concat);
        return $str_concat;
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
            attributes => $attributes
        );
        $graph->add_node($str_length);
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
            attributes => $attributes
        );
        $graph->add_node($str_substr);
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
            attributes => $attributes
        );
        $graph->add_node($use_stmt);
        return $use_stmt;
    }

}

1;

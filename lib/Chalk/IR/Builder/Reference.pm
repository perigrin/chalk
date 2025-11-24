# ABOUTME: Reference operation builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for ref/deref nodes

use 5.42.0;
use experimental qw(class builtin);

use Chalk::IR::Node::Reference;
use Chalk::IR::Node::ScalarDeref;
use Chalk::IR::Node::VariableRead;
use Chalk::IR::Context;

class Chalk::IR::Builder::Reference {

    # Reference operations (Issue #130 Phase 4)

    # Create reference to a scalar variable: \$x
    method build_scalar_ref_node($builder, $var_name, $source_info = undef) {
        my $label = "lexical:$var_name";
        my $context = $builder->context;
        my $graph = $builder->graph;

        # Validate reference target if source_info provided
        my $target_node_or_id;
        if ( defined($source_info) ) {
            $target_node_or_id =
              $builder->validator->validate_reference_target( $label, $source_info );
        }
        else {
            # Look up the target node (might be object or ID)
            $target_node_or_id = $context->($label);
            die "Cannot create reference to undefined variable $var_name"
              unless defined($target_node_or_id);
        }

        # Get the node ID for the dependency
        my $target_node_id =
          ref($target_node_or_id) ? $target_node_or_id->id : $target_node_or_id;

        my $node_id   = $builder->next_node_id();
        my $reference = Chalk::IR::Node::Reference->new(
            id     => $node_id,
            inputs => [ $builder->current_control, $target_node_id ],
            target_context => $context,
            target_label   => $label,
            source_info    => $source_info,
        );
        $graph->add_node($reference);

        # Record transformation
        $reference->record_transform(
            'ir_construction',
            'Builder::build_scalar_ref_node',
            context => "var=$var_name, target_id=$target_node_id"
        );

        return $reference;
    }

    # Create reference to array element: \$arr[1]
    method build_element_ref_node($builder, $collection_name, $index_node) {
        my $context = $builder->context;
        my $graph = $builder->graph;

        # Get the collection from context (might be object or ID)
        my $collection_label      = "lexical:$collection_name";
        my $collection_node_or_id = $context->($collection_label);

        # Get the collection node
        my $collection_node;
        if ( ref($collection_node_or_id) ) {
            $collection_node = $collection_node_or_id;
        }
        else {
            $collection_node = $graph->get_node($collection_node_or_id);
        }

        # Get the array context from the collection node
        my $array_ctx = $collection_node->array_context;

        # Get the index value - need to evaluate it
        # For now, assume it's a constant node
        my $index_val = $index_node->value;

        # Create the reference pointing to the array context with index: label
        my $label     = Chalk::IR::Context->make_index_label($index_val);
        my $node_id   = $builder->next_node_id();
        my $reference = Chalk::IR::Node::Reference->new(
            id     => $node_id,
            inputs =>
              [ $builder->current_control, $collection_node->id, $index_node->id ],
            target_context => $array_ctx,
            target_label   => $label,
        );
        $graph->add_node($reference);

        # Record transformation
        $reference->record_transform(
            'ir_construction',
            'Builder::build_element_ref_node',
            context => "collection=$collection_name, index_id="
              . $index_node->id
              . ", index_val=$index_val"
        );

        return $reference;
    }

    # Dereference a scalar reference: $$ref
    method build_scalar_deref_node($builder, $ref_var_name) {
        my $context = $builder->context;
        my $graph = $builder->graph;

        # Get the reference from context (might be object or ID)
        my $ref_label      = "lexical:$ref_var_name";
        my $ref_node_or_id = $context->($ref_label);

        # Get the node ID
        my $ref_id =
          ref($ref_node_or_id) ? $ref_node_or_id->id : $ref_node_or_id;

        # Create ScalarDeref node
        my $node_id = $builder->next_node_id();
        my $deref   = Chalk::IR::Node::ScalarDeref->new(
            id     => $node_id,
            inputs => [ $builder->current_control, $ref_id ],
            ref_id => $ref_id,
        );
        $graph->add_node($deref);

        # Record transformation
        $deref->record_transform(
            'ir_construction',
            'Builder::build_scalar_deref_node',
            context => "var=$ref_var_name, ref_id=$ref_id"
        );

        return $deref;
    }

    # Read variable from context: helper for tests
    method build_variable_read_node($builder, $var_name) {
        my $label    = "lexical:$var_name";
        my $node_id  = $builder->next_node_id();
        my $var_read = Chalk::IR::Node::VariableRead->new(
            id        => $node_id,
            inputs    => [$builder->current_control],
            var_label => $label,
        );
        $builder->graph->add_node($var_read);

        # Record transformation
        $var_read->record_transform(
            'ir_construction',
            'Builder::build_variable_read_node',
            context => "var=$var_name"
        );

        return $var_read;
    }

    # Assign through a dereferenced reference: $$ref = value
    method build_scalar_deref_assign_node($builder, $ref_var_name, $value_node) {
        my $context = $builder->context;
        my $graph = $builder->graph;

        # Get the reference from context
        my $ref_label      = "lexical:$ref_var_name";
        my $ref_node_or_id = $context->($ref_label);

        # Might be node object or node ID depending on when it was stored
        my $ref_node;
        if ( ref($ref_node_or_id) ) {
            $ref_node = $ref_node_or_id;
        }
        else {
            $ref_node = $graph->get_node($ref_node_or_id);
        }

        # Get the target label from the reference
        my $target_label = $ref_node->target_label;

        # Extend the BUILDER's current context with the new value (node object, not ID)
        # This updates the variable that the reference points to
        # Note: This modifies the builder's context, but we access it through $builder->set_context
        my $new_context = Chalk::IR::Context->extend_context( $context, $target_label, $value_node );
        $builder->set_context($new_context);

        # Return the value node for chaining
        return $value_node;
    }
}

1;

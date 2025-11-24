# ABOUTME: Class and object builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for class/object nodes

use 5.42.0;
use experimental qw(class builtin);

class Chalk::IR::Builder::Object {

    # Class and object support nodes (Issue #98 Phase 1)

    method build_classdef_node($builder, $class_name, $fields) {
        # Create ClassDef node for class definition
        my $attributes = {
            name   => $class_name,
            fields => $fields,
        };
        my $node_id  = $builder->next_node_id();
        my $classdef = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'ClassDef',
            inputs     => [$builder->current_control],
            attributes => $attributes,
        );
        $builder->graph->add_node($classdef);

        # Record transformation
        my $field_names = join( ", ", $fields->@* );
        $classdef->record_transform(
            'ir_construction',
            'Builder::build_classdef_node',
            context => "class=$class_name, fields=[$field_names]"
        );

        return $classdef;
    }

    method build_new_node($builder, $class_name, $field_values_hash) {
        # Create New node for object instantiation
        # $field_values_hash is a hashref mapping field names to node objects
        my @input_nodes = ($builder->current_control);
        my %field_value_refs;

        # Build field references from hash
        for my $field_name ( sort( keys( $field_values_hash->%* ) ) ) {
            my $value_node = $field_values_hash->{$field_name};
            push( @input_nodes, $value_node->id );
            $field_value_refs{$field_name} = {
                op      => 'NodeRef',
                node_id => $value_node->id
            };
        }

        my $attributes = {
            class        => $class_name,
            field_values => \%field_value_refs
        };
        my $node_id = $builder->next_node_id();
        my $new_obj = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'New',
            inputs     => \@input_nodes,
            attributes => $attributes,
        );
        $builder->graph->add_node($new_obj);

        # Record transformation
        my $field_names = join( ", ", sort( keys( $field_values_hash->%* ) ) );
        $new_obj->record_transform(
            operation   => 'ir_construction',
            rule_name   => 'Builder::build_new_node',
            description => "class=$class_name, fields=[$field_names]"
        );

        return $new_obj;
    }

    method build_field_access_node($builder, $object_node, $field_name, $source_info = undef) {
        # Validate field exists in class if source_info provided
        if ( defined($source_info) ) {
            my $class_name = $builder->type_inference->infer_class($object_node);
            if ( defined($class_name) ) {
                $builder->validator->validate_class_field( $class_name, $field_name,
                    $source_info );
            }
        }

        # Create FieldAccess node for reading a field
        my $object_ref = { op => 'NodeRef', node_id => $object_node->id };
        my $attributes = {
            field  => $field_name,
            object => $object_ref
        };
        my $node_id      = $builder->next_node_id();
        my $field_access = Chalk::IR::Node->new(
            id          => $node_id,
            op          => 'FieldAccess',
            inputs      => [ $builder->current_control, $object_node->id ],
            attributes  => $attributes,
            source_info => $source_info,
        );
        $builder->graph->add_node($field_access);

        # Record transformation
        $field_access->record_transform(
            operation   => 'ir_construction',
            rule_name   => 'Builder::build_field_access_node',
            description => "object_id="
              . $object_node->id
              . ", field=$field_name"
        );

        return $field_access;
    }

    method build_field_store_node($builder, $object_node, $field_name, $value_node) {
        # Create FieldStore node for writing to a field
        my $object_ref = { op => 'NodeRef', node_id => $object_node->id };
        my $value_ref  = { op => 'NodeRef', node_id => $value_node->id };
        my $attributes = {
            field  => $field_name,
            object => $object_ref,
            value  => $value_ref
        };
        my $node_id     = $builder->next_node_id();
        my $field_store = Chalk::IR::Node->new(
            id     => $node_id,
            op     => 'FieldStore',
            inputs => [ $builder->current_control, $object_node->id, $value_node->id ],
            attributes => $attributes,
        );
        $builder->graph->add_node($field_store);

        # Record transformation
        $field_store->record_transform(
            'ir_construction',
            'Builder::build_field_store_node',
            context => "object_id="
              . $object_node->id
              . ", field=$field_name, value_id="
              . $value_node->id
        );

        return $field_store;
    }
}

1;

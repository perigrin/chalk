# ABOUTME: Array and Hash operation builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for data structure nodes

use 5.42.0;
use experimental qw(class builtin);

use Chalk::IR::Node::NewArray;
use Chalk::IR::Node::NewHash;
use Chalk::IR::Node::ArrayGet;
use Chalk::IR::Node::ArraySet;
use Chalk::IR::Node::HashGet;
use Chalk::IR::Node::HashSet;

class Chalk::IR::Builder::DataStructures {

    # Array operations (Issue #98 Phase 2)
    method build_array_new_node($builder) {
        # Create NewArray node for creating an empty array
        my $node_id   = $builder->next_node_id();
        my $array_new = Chalk::IR::Node::NewArray->new(
            id         => $node_id,
            inputs     => [$builder->current_control],
        );
        $builder->graph->add_node($array_new);

        # Record transformation
        $array_new->record_transform(
            'ir_construction',
            'Builder::build_array_new_node',
            context => "empty_array"
        );

        return $array_new;
    }

    method build_array_push_node($builder, $array_node, $value_node) {
        # Create ArrayPush node for appending to array
        my $array_ref  = { op => 'NodeRef', node_id => $array_node->id };
        my $value_ref  = { op => 'NodeRef', node_id => $value_node->id };
        my $attributes = {
            array => $array_ref,
            value => $value_ref
        };
        my $node_id    = $builder->next_node_id();
        my $array_push = Chalk::IR::Node->new(
            id     => $node_id,
            op     => 'ArrayPush',
            inputs => [ $builder->current_control, $array_node->id, $value_node->id ],
            attributes => $attributes,
        );
        $builder->graph->add_node($array_push);

        # Record transformation
        $array_push->record_transform(
            'ir_construction',
            'Builder::build_array_push_node',
            context => "array_id="
              . $array_node->id
              . ", value_id="
              . $value_node->id
        );

        return $array_push;
    }

    method build_array_get_node($builder, $array_node, $index_node) {
    # Create ArrayGet node for accessing array element by index using context lookup
        my $node_id   = $builder->next_node_id();
        my $array_get = Chalk::IR::Node::ArrayGet->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $array_node->id, $index_node->id ],
            array_id => $array_node->id,
            index_id => $index_node->id,
        );
        $builder->graph->add_node($array_get);

        # Record transformation
        $array_get->record_transform(
            'ir_construction',
            'Builder::build_array_get_node',
            context => "array_id="
              . $array_node->id
              . ", index_id="
              . $index_node->id
        );

        return $array_get;
    }

    method build_array_set_node($builder, $array_node, $index_node, $value_node) {
    # Create ArraySet node for setting array element with context extension (immutable)
        my $node_id   = $builder->next_node_id();
        my $array_set = Chalk::IR::Node::ArraySet->new(
            id     => $node_id,
            inputs => [
                $builder->current_control, $array_node->id,
                $index_node->id,  $value_node->id
            ],
            array_id => $array_node->id,
            index_id => $index_node->id,
            value_id => $value_node->id,
        );
        $builder->graph->add_node($array_set);

        # Record transformation
        $array_set->record_transform(
            'ir_construction',
            'Builder::build_array_set_node',
            context => "array_id="
              . $array_node->id
              . ", index_id="
              . $index_node->id
              . ", value_id="
              . $value_node->id
        );

        return $array_set;
    }

    method build_array_length_node($builder, $array_node) {
        # Create ArrayLength node for getting array size
        my $array_ref    = { op    => 'NodeRef', node_id => $array_node->id };
        my $attributes   = { array => $array_ref };
        my $node_id      = $builder->next_node_id();
        my $array_length = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'ArrayLength',
            inputs     => [ $builder->current_control, $array_node->id ],
            attributes => $attributes,
        );
        $builder->graph->add_node($array_length);

        # Record transformation
        $array_length->record_transform(
            'ir_construction',
            'Builder::build_array_length_node',
            context => "array_id=" . $array_node->id
        );

        return $array_length;
    }

    # Hash operations (Issue #98 Phase 3)
    method build_hash_new_node($builder) {
        # Create NewHash node for creating an empty hash
        my $node_id  = $builder->next_node_id();
        my $hash_new = Chalk::IR::Node::NewHash->new(
            id         => $node_id,
            inputs     => [$builder->current_control],
        );
        $builder->graph->add_node($hash_new);

        # Record transformation
        $hash_new->record_transform(
            'ir_construction',
            'Builder::build_hash_new_node',
            context => "empty_hash"
        );

        return $hash_new;
    }

    method build_hash_set_node($builder, $hash_node, $key_node, $value_node) {
     # Create HashSet node for setting hash value with context extension (immutable)
        my $node_id  = $builder->next_node_id();
        my $hash_set = Chalk::IR::Node::HashSet->new(
            id     => $node_id,
            inputs => [
                $builder->current_control, $hash_node->id,
                $key_node->id,    $value_node->id
            ],
            hash_id  => $hash_node->id,
            key_id   => $key_node->id,
            value_id => $value_node->id,
        );
        $builder->graph->add_node($hash_set);

        # Record transformation
        $hash_set->record_transform(
            'ir_construction',
            'Builder::build_hash_set_node',
            context => "hash_id="
              . $hash_node->id
              . ", key_id="
              . $key_node->id
              . ", value_id="
              . $value_node->id
        );

        return $hash_set;
    }

    method build_hash_get_node($builder, $hash_node, $key_node) {
      # Create HashGet node for accessing hash value by key using context lookup
        my $node_id  = $builder->next_node_id();
        my $hash_get = Chalk::IR::Node::HashGet->new(
            id      => $node_id,
            inputs  => [ $builder->current_control, $hash_node->id, $key_node->id ],
            hash_id => $hash_node->id,
            key_id  => $key_node->id,
        );
        $builder->graph->add_node($hash_get);

        # Record transformation
        $hash_get->record_transform(
            'ir_construction',
            'Builder::build_hash_get_node',
            context => "hash_id="
              . $hash_node->id
              . ", key_id="
              . $key_node->id
        );

        return $hash_get;
    }

    method build_hash_exists_node($builder, $hash_node, $key_node) {
        # Create HashExists node for checking if key exists in hash
        my $hash_ref   = { op => 'NodeRef', node_id => $hash_node->id };
        my $key_ref    = { op => 'NodeRef', node_id => $key_node->id };
        my $attributes = {
            hash => $hash_ref,
            key  => $key_ref
        };
        my $node_id     = $builder->next_node_id();
        my $hash_exists = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'HashExists',
            inputs     => [ $builder->current_control, $hash_node->id, $key_node->id ],
            attributes => $attributes,
        );
        $builder->graph->add_node($hash_exists);

        # Record transformation
        $hash_exists->record_transform(
            'ir_construction',
            'Builder::build_hash_exists_node',
            context => "hash_id="
              . $hash_node->id
              . ", key_id="
              . $key_node->id
        );

        return $hash_exists;
    }

    method build_hash_keys_node($builder, $hash_node) {
        # Create HashKeys node for getting all keys from hash
        my $hash_ref   = { op   => 'NodeRef', node_id => $hash_node->id };
        my $attributes = { hash => $hash_ref };
        my $node_id    = $builder->next_node_id();
        my $hash_keys  = Chalk::IR::Node->new(
            id         => $node_id,
            op         => 'HashKeys',
            inputs     => [ $builder->current_control, $hash_node->id ],
            attributes => $attributes,
        );
        $builder->graph->add_node($hash_keys);

        # Record transformation
        $hash_keys->record_transform(
            'ir_construction',
            'Builder::build_hash_keys_node',
            context => "hash_id=" . $hash_node->id
        );

        return $hash_keys;
    }
}

1;

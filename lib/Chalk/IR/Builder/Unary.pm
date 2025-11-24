# ABOUTME: Unary operation builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for unary nodes

use 5.42.0;
use experimental qw(class builtin);

use Chalk::IR::Node::Not;
use Chalk::IR::Node::Negate;
use Chalk::IR::Node::PreIncrement;
use Chalk::IR::Node::PreDecrement;
use Chalk::IR::Node::PostIncrement;
use Chalk::IR::Node::PostDecrement;
use Chalk::IR::Node::Reference;

class Chalk::IR::Builder::Unary {

    method build_not_node($builder, $operand_node) {
        my $node_id = $builder->next_node_id();
        my $not     = Chalk::IR::Node::Not->new(
            id         => $node_id,
            inputs     => [ $builder->current_control, $operand_node->id ],
            operand_id => $operand_node->id,
        );
        $builder->graph->add_node($not);

        # Record transformation
        $not->record_transform(
            'ir_construction',
            'Builder::build_not_node',
            context => "operand_id=" . $operand_node->id
        );

        return $not;
    }

    method build_negate_node($builder, $operand_node) {
        my $node_id = $builder->next_node_id();
        my $negate  = Chalk::IR::Node::Negate->new(
            id         => $node_id,
            inputs     => [ $builder->current_control, $operand_node->id ],
            operand_id => $operand_node->id,
        );
        $builder->graph->add_node($negate);

        # Record transformation
        $negate->record_transform(
            'ir_construction',
            'Builder::build_negate_node',
            context => "operand_id=" . $operand_node->id
        );

        return $negate;
    }

    method build_pre_increment_node($builder, $operand_node) {
        my $node_id = $builder->next_node_id();
        my $pre_inc = Chalk::IR::Node::PreIncrement->new(
            id         => $node_id,
            inputs     => [ $builder->current_control, $operand_node->id ],
            operand_id => $operand_node->id,
        );
        $builder->graph->add_node($pre_inc);

        # Record transformation
        $pre_inc->record_transform(
            'ir_construction',
            'Builder::build_pre_increment_node',
            context => "operand_id=" . $operand_node->id
        );

        return $pre_inc;
    }

    method build_pre_decrement_node($builder, $operand_node) {
        my $node_id = $builder->next_node_id();
        my $pre_dec = Chalk::IR::Node::PreDecrement->new(
            id         => $node_id,
            inputs     => [ $builder->current_control, $operand_node->id ],
            operand_id => $operand_node->id,
        );
        $builder->graph->add_node($pre_dec);

        # Record transformation
        $pre_dec->record_transform(
            'ir_construction',
            'Builder::build_pre_decrement_node',
            context => "operand_id=" . $operand_node->id
        );

        return $pre_dec;
    }

    method build_post_increment_node($builder, $operand_node) {
        my $node_id  = $builder->next_node_id();
        my $post_inc = Chalk::IR::Node::PostIncrement->new(
            id         => $node_id,
            inputs     => [ $builder->current_control, $operand_node->id ],
            operand_id => $operand_node->id,
        );
        $builder->graph->add_node($post_inc);

        # Record transformation
        $post_inc->record_transform(
            'ir_construction',
            'Builder::build_post_increment_node',
            context => "operand_id=" . $operand_node->id
        );

        return $post_inc;
    }

    method build_post_decrement_node($builder, $operand_node) {
        my $node_id  = $builder->next_node_id();
        my $post_dec = Chalk::IR::Node::PostDecrement->new(
            id         => $node_id,
            inputs     => [ $builder->current_control, $operand_node->id ],
            operand_id => $operand_node->id,
        );
        $builder->graph->add_node($post_dec);

        # Record transformation
        $post_dec->record_transform(
            'ir_construction',
            'Builder::build_post_decrement_node',
            context => "operand_id=" . $operand_node->id
        );

        return $post_dec;
    }

    # OLD: This will be removed - use build_scalar_ref_node instead
    method build_reference_node($builder, $operand_node) {
        my $node_id   = $builder->next_node_id();
        my $reference = Chalk::IR::Node::Reference->new(
            id             => $node_id,
            inputs         => [$builder->current_control],
            target_context => $builder->context,             # Current context
            target_label   => 'UNKNOWN',            # This is deprecated
        );
        $builder->graph->add_node($reference);

        # Record transformation
        $reference->record_transform(
            'ir_construction',
            'Builder::build_reference_node',
            context => "label=UNKNOWN (deprecated)"
        );

        return $reference;
    }
}

1;

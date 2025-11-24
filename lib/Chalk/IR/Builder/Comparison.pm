# ABOUTME: Comparison operation builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for comparison nodes

use 5.42.0;
use experimental qw(class builtin);

use Chalk::IR::Node::GT;
use Chalk::IR::Node::LT;
use Chalk::IR::Node::EQ;
use Chalk::IR::Node::NE;
use Chalk::IR::Node::LE;
use Chalk::IR::Node::GE;

class Chalk::IR::Builder::Comparison {

    method build_greater_node($builder, $left_node, $right_node) {
        my $node_id = $builder->next_node_id();
        my $cmp     = Chalk::IR::Node::GT->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
        );
        $builder->graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform(
            'ir_construction',
            'Builder::build_greater_node',
            context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id
        );

        return $cmp;
    }

    method build_less_node($builder, $left_node, $right_node) {
        my $node_id = $builder->next_node_id();
        my $cmp     = Chalk::IR::Node::LT->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
        );
        $builder->graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform( 'ir_construction', 'Builder::build_less_node',
                context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id );

        return $cmp;
    }

    method build_equal_node($builder, $left_node, $right_node) {
        my $node_id = $builder->next_node_id();
        my $cmp     = Chalk::IR::Node::EQ->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
        );
        $builder->graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform( 'ir_construction', 'Builder::build_equal_node',
                context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id );

        return $cmp;
    }

    method build_greater_or_equal_node($builder, $left_node, $right_node) {
        my $node_id = $builder->next_node_id();
        my $cmp     = Chalk::IR::Node::GE->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
        );
        $builder->graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform(
            'ir_construction',
            'Builder::build_greater_or_equal_node',
            context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id
        );

        return $cmp;
    }

    method build_less_or_equal_node($builder, $left_node, $right_node) {
        my $node_id = $builder->next_node_id();
        my $cmp     = Chalk::IR::Node::LE->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
        );
        $builder->graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform(
            'ir_construction',
            'Builder::build_less_or_equal_node',
            context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id
        );

        return $cmp;
    }

    method build_not_equal_node($builder, $left_node, $right_node) {
        my $node_id = $builder->next_node_id();
        my $cmp     = Chalk::IR::Node::NE->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
        );
        $builder->graph->add_node($cmp);

        # Record transformation
        $cmp->record_transform(
            'ir_construction',
            'Builder::build_not_equal_node',
            context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id
        );

        return $cmp;
    }
}

1;

# ABOUTME: Arithmetic operation builder methods for IR construction
# ABOUTME: Defines methods in Chalk::IR::Builder namespace for add/sub/mul/div nodes

use 5.42.0;
use experimental qw(class builtin);

use Chalk::IR::Node::Add;
use Chalk::IR::Node::Subtract;
use Chalk::IR::Node::Multiply;
use Chalk::IR::Node::Divide;

class Chalk::IR::Builder::Arithmetic {

    method build_add_node($builder, $left_node, $right_node, $source_info = undef) {
        die "build_add_node: left_node is undefined" unless defined($left_node);
        die "build_add_node: right_node is undefined"
          unless defined($right_node);
        die "build_add_node: left_node is not an IR node object"
          unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_add_node: right_node is not an IR node object"
          unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if ( defined($source_info) ) {
            my $left_type  = $builder->type_inference->infer_type($left_node);
            my $right_type = $builder->type_inference->infer_type($right_node);

            if ( defined($left_type) || defined($right_type) ) {
                $builder->validator->validate_type_operation( 'Add', $left_type,
                    $right_type, $source_info );
            }
        }

        my $node_id = $builder->next_node_id();
        my $add     = Chalk::IR::Node::Add->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $builder->graph->add_node($add);

        # Record transformation
        $add->record_transform( 'ir_construction', 'Builder::build_add_node',
                context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id );

        return $add;
    }

    method build_multiply_node($builder, $left_node, $right_node, $source_info = undef) {
        die "build_multiply_node: left_node is undefined"
          unless defined($left_node);
        die "build_multiply_node: right_node is undefined"
          unless defined($right_node);
        die "build_multiply_node: left_node is not an IR node object"
          unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_multiply_node: right_node is not an IR node object"
          unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if ( defined($source_info) ) {
            my $left_type  = $builder->type_inference->infer_type($left_node);
            my $right_type = $builder->type_inference->infer_type($right_node);

            if ( defined($left_type) || defined($right_type) ) {
                $builder->validator->validate_type_operation( 'Multiply', $left_type,
                    $right_type, $source_info );
            }
        }

        my $node_id = $builder->next_node_id();
        my $mul     = Chalk::IR::Node::Multiply->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $builder->graph->add_node($mul);

        # Record transformation
        $mul->record_transform(
            'ir_construction',
            'Builder::build_multiply_node',
            context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id
        );

        return $mul;
    }

    method build_sub_node($builder, $left_node, $right_node, $source_info = undef) {
        die "build_sub_node: left_node is undefined" unless defined($left_node);
        die "build_sub_node: right_node is undefined"
          unless defined($right_node);
        die "build_sub_node: left_node is not an IR node object"
          unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_sub_node: right_node is not an IR node object"
          unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if ( defined($source_info) ) {
            my $left_type  = $builder->type_inference->infer_type($left_node);
            my $right_type = $builder->type_inference->infer_type($right_node);

            if ( defined($left_type) || defined($right_type) ) {
                $builder->validator->validate_type_operation( 'Subtract', $left_type,
                    $right_type, $source_info );
            }
        }

        my $node_id = $builder->next_node_id();
        my $sub     = Chalk::IR::Node::Subtract->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $builder->graph->add_node($sub);

        # Record transformation
        $sub->record_transform( 'ir_construction', 'Builder::build_sub_node',
                context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id );

        return $sub;
    }

    method build_divide_node($builder, $left_node, $right_node, $source_info = undef) {
        die "build_divide_node: left_node is undefined"
          unless defined($left_node);
        die "build_divide_node: right_node is undefined"
          unless defined($right_node);
        die "build_divide_node: left_node is not an IR node object"
          unless ref($left_node) && ref($left_node) =~ qr/^Chalk::IR::Node/;
        die "build_divide_node: right_node is not an IR node object"
          unless ref($right_node) && ref($right_node) =~ qr/^Chalk::IR::Node/;

        # Type validation if source_info provided
        if ( defined($source_info) ) {
            my $left_type  = $builder->type_inference->infer_type($left_node);
            my $right_type = $builder->type_inference->infer_type($right_node);

            if ( defined($left_type) || defined($right_type) ) {
                $builder->validator->validate_type_operation( 'Divide', $left_type,
                    $right_type, $source_info );
            }
        }

        my $node_id = $builder->next_node_id();
        my $div     = Chalk::IR::Node::Divide->new(
            id       => $node_id,
            inputs   => [ $builder->current_control, $left_node->id, $right_node->id ],
            left_id  => $left_node->id,
            right_id => $right_node->id,
            source_info => $source_info,
        );
        $builder->graph->add_node($div);

        # Record transformation
        $div->record_transform( 'ir_construction', 'Builder::build_divide_node',
                context => "left_id="
              . $left_node->id
              . ", right_id="
              . $right_node->id );

        return $div;
    }
}

1;

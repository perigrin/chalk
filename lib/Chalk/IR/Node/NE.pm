# ABOUTME: Not Equal comparison node in the IR graph
# ABOUTME: Represents != inequality comparison between two values, returns native bool
use 5.42.0;
use experimental qw(class);
use utf8;
use builtin qw(true false);

class Chalk::IR::Node::NE {
    use Chalk::IR::Type::TypeBool;
    use Chalk::IR::Type::Top;
    use Chalk::IR::Node::Constant;

    field $left :param :reader;
    field $right :param :reader;
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    method id() { refaddr($self) }

    method inputs() {
        return [ $left->id, $right->id ];
    }

    method op() { 'NE' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'NE',
            inputs => $self->inputs,
            attributes => {
                left_id  => $left->id,
                right_id => $right->id,
            },
        };
    }

    method execute($context) {
        my $left_val = $context->("node:" . $left->id);
        my $right_val = $context->("node:" . $right->id);
        return ($left_val != $right_val) ? true : false;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method compute() {
        my $left_type = $left->compute();
        my $right_type = $right->compute();

        if ($left_type->is_constant && $right_type->is_constant) {
            my $result = $left_type->value != $right_type->value;
            return Chalk::IR::Type::TypeBool->constant($result);
        }

        return Chalk::IR::Type::Top->top();
    }

    method peephole($graph = undef) {
        my $type = $self->compute();
        if ($type->is_constant) {
            return Chalk::IR::Node::Constant->new(
                value => $type->value,
                type  => 'Bool',
            );
        }
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;

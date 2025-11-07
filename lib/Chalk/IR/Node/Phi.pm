# ABOUTME: Phi node in the IR graph
# ABOUTME: Represents SSA phi function that selects value based on control flow path
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::Phi :isa(Chalk::IR::Node::Base) {
    field $region_id :param :reader;

    method op() { 'Phi' }

    method to_hash() {
        return {
            id     => $self->id,
            op     => 'Phi',
            inputs => $self->inputs,
            attributes => {
                region_id => $region_id,
            },
        };
    }

    method execute($context) {
        # Phi selects value based on Region's active path
        # inputs[0] = region_id
        # inputs[1..n] = values for each path
        my $active_path = $context->("node:$region_id");
        my @inputs = $self->inputs->@*;

        # Skip region input (index 0), select value at active_path + 1
        my $value_index = $active_path + 1;
        if ($value_index >= @inputs) {
            die "Phi node: active path $active_path out of range";
        }

        my $value_id = $inputs[$value_index];
        return $context->("node:$value_id");
    }
}

1;

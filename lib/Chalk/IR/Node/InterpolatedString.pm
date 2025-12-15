# ABOUTME: InterpolatedString node for string interpolation
# ABOUTME: Represents "Hello $name!" with parts to be concatenated at runtime
use 5.42.0;
use experimental qw(class);
use utf8;

class Chalk::IR::Node::InterpolatedString {
    field $parts :param :reader;        # Array of parts (literals and expressions)
    field $source_info :param :reader = undef;
    field $transform_chain :reader = [];

    # Dependency tracking for peephole re-optimization
    field $_deps = [];

    method add_dep($dependent_node_id) {
        push $_deps->@*, $dependent_node_id;
    }

    method get_deps() {
        return $_deps->@*;
    }

    method id() { refaddr($self) }

    method inputs() {
        my @inputs;
        for my $part (@$parts) {
            push @inputs, $part->id if defined $part && $part->can('id');
        }
        return \@inputs;
    }

    method op() { 'InterpolatedString' }

    method to_hash() {
        my @part_ids;
        for my $part (@$parts) {
            push @part_ids, $part->id if defined $part && $part->can('id');
        }

        return {
            id     => $self->id,
            op     => 'InterpolatedString',
            inputs => $self->inputs,
            attributes => {
                part_ids => \@part_ids,
            },
        };
    }

    method execute($context) {
        # Execute interpolation:
        # 1. Evaluate each part
        # 2. Stringify and concatenate all parts
        # 3. Return final string

        # For now, return undef as placeholder
        # Full implementation requires runtime value handling
        return undef;
    }

    method attributes() {
        return $self->to_hash()->{attributes};
    }

    method peephole($graph = undef) {
        # Could optimize if all parts are constant strings
        # For now, return self as-is
        return $self;
    }

    method record_transform(@args) {
        return;
    }
}

1;

# ABOUTME: Proj node - projection from conditional branch (v2 rewrite)
# ABOUTME: Extracts control path from If node (true/false branch)
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Proj2 :isa(Chalk::IR::Node::Base2) {
    field $source :param :reader;  # The If node this projects from
    field $index :param :reader;   # 0 = true branch, 1 = false branch
    field $label :param :reader;   # "IfTrue" or "IfFalse"
    field $id :reader = "proj_" . $source->id . "_" . $index;

    method op() { 'Proj' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Proj',
            inputs => [$source->id],
            attributes => {
                source => $source->id,
                index  => $index,
                label  => $label,
            },
        };
    }
}

1;

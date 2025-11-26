# ABOUTME: Region node - control flow merge point (v2 rewrite)
# ABOUTME: Merges multiple control paths (e.g., from if-else branches)
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Region2 :isa(Chalk::IR::Node::Base2) {
    field $controls :param :reader;  # Array of control input nodes (Proj nodes)
    field $id :reader;

    ADJUST {
        $id = "region_" . join("_", map { $_->id } $controls->@*);
    }

    method op() { 'Region' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Region',
            inputs => [map { $_->id } $controls->@*],
            attributes => {
                controls => [map { $_->id } $controls->@*],
            },
        };
    }
}

1;

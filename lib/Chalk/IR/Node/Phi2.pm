# ABOUTME: Phi node - SSA phi function (v2 rewrite)
# ABOUTME: Selects value based on control path taken to Region
use 5.42.0;
use experimental qw(class);

class Chalk::IR::Node::Phi2 :isa(Chalk::IR::Node::Base2) {
    field $region :param :reader;    # Region node this Phi depends on
    field $values :param :reader;    # Array of value nodes (parallel to Region's controls)
    field $id :reader;

    ADJUST {
        $id = "phi_" . $region->id . "_" . join("_", map { $_->id } $values->@*);
    }

    method op() { 'Phi' }

    method to_hash() {
        return {
            id     => $id,
            op     => 'Phi',
            inputs => [$region->id, (map { $_->id } $values->@*)],
            attributes => {
                region => $region->id,
                values => [map { $_->id } $values->@*],
            },
        };
    }
}

1;

# ABOUTME: Enumerates all (rule_name, alt_idx, dot) triples as small integer IDs.
# ABOUTME: Enables integer-indexed chart lookups instead of string-key hashing.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::CoreItemIndex {
    field %id_for_key;   # "rule_name:alt_idx:dot" => integer
    field @id_to_info;   # integer => { rule_name, alt_idx, dot }
    field %advance_map;  # core_id => core_id for dot+1
    field $count :reader = 0;

    # Register a single core item, returns its integer ID
    method register($rule_name, $alt_idx, $dot) {
        my $key = join(':', $rule_name, $alt_idx, $dot);
        return $id_for_key{$key} if exists $id_for_key{$key};

        my $id = $count++;
        $id_for_key{$key} = $id;
        $id_to_info[$id] = {
            rule_name => $rule_name,
            alt_idx   => $alt_idx,
            dot       => $dot,
        };
        return $id;
    }

    # Look up the ID for a (rule_name, alt_idx, dot) triple
    method id_for($rule_name, $alt_idx, $dot) {
        my $key = join(':', $rule_name, $alt_idx, $dot);
        return $id_for_key{$key};
    }

    # Get the info for a given integer ID
    method item_for($id) {
        return $id_to_info[$id];
    }

    # Get the ID for the same item but with dot+1
    method advance($id) {
        return $advance_map{$id} if exists $advance_map{$id};

        my $info = $id_to_info[$id];
        return unless defined $info;

        my $next_id = $self->id_for(
            $info->{rule_name}, $info->{alt_idx}, $info->{dot} + 1
        );
        $advance_map{$id} = $next_id if defined $next_id;
        return $next_id;
    }

    # Build the index from a grammar (arrayref of Rule objects)
    method build_from_grammar($grammar) {
        for my $rule ($grammar->@*) {
            my $name = $rule->name();
            my $expressions = $rule->expressions();
            for my $alt_idx (0 .. $expressions->$#*) {
                my $alt = $expressions->[$alt_idx];
                # Register dot positions 0 through length of alternative
                for my $dot (0 .. scalar $alt->@*) {
                    $self->register($name, $alt_idx, $dot);
                }
            }
        }
    }
}

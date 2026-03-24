# ABOUTME: Enumerates all (rule_name, alt_idx, dot) triples as small integer IDs.
# ABOUTME: Enables integer-indexed chart lookups instead of string-key hashing.
use 5.42.0;
use utf8;
use experimental 'class';

class Chalk::Bootstrap::CoreItemIndex {
    field %id_for_key;        # "rule_name:alt_idx:dot" => integer
    field @id_to_info;        # integer => { rule_name, alt_idx, dot }
    field @id_to_rule_name;   # integer => rule name string (O(1) accessor)
    field @id_to_alt_idx;     # integer => alt index integer (O(1) accessor)
    field @id_to_dot;         # integer => dot position integer (O(1) accessor)
    field @id_to_rule;        # integer => Rule object (populated by build_from_grammar)
    field @id_is_complete;    # integer => boolean (precomputed: dot >= length of alt)
    field @id_symbol_after;   # integer => Symbol object or undef (precomputed)
    field %advance_map;       # core_id => core_id for dot+1
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
        $id_to_rule_name[$id] = $rule_name;
        $id_to_alt_idx[$id]   = $alt_idx;
        $id_to_dot[$id]       = $dot;
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

    # O(1) accessors that return individual fields for a given core_id integer
    method rule_name_for($id) { return $id_to_rule_name[$id] }
    method alt_idx_for($id)   { return $id_to_alt_idx[$id]   }
    method dot_for($id)       { return $id_to_dot[$id]        }
    method rule_for($id)      { return $id_to_rule[$id]       }
    method is_complete($id)   { return $id_is_complete[$id]   }
    method symbol_after($id)  { return $id_symbol_after[$id]  }

    # Bulk accessors returning arrayrefs for hot-loop direct indexing.
    # Avoids per-element method dispatch overhead in the Earley inner loop.
    method rule_names()       { return \@id_to_rule_name      }
    method alt_idxs()         { return \@id_to_alt_idx        }
    method dots()             { return \@id_to_dot            }
    method completions()      { return \@id_is_complete       }
    method symbols_after()    { return \@id_symbol_after      }

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

    # Build the index from a grammar (arrayref of Rule objects).
    # Also populates @id_to_rule, @id_is_complete, and @id_symbol_after
    # so that rule_for($id), is_complete($id), and symbol_after($id) are O(1).
    method build_from_grammar($grammar) {
        for my $rule ($grammar->@*) {
            my $name = $rule->name();
            my $expressions = $rule->expressions();
            for my $alt_idx (0 .. $expressions->$#*) {
                my $alt = $expressions->[$alt_idx];
                my $alt_len = scalar $alt->@*;
                # Register dot positions 0 through length of alternative
                for my $dot (0 .. $alt_len) {
                    my $id = $self->register($name, $alt_idx, $dot);
                    $id_to_rule[$id] = $rule;
                    $id_is_complete[$id] = ($dot >= $alt_len) ? true : false;
                    $id_symbol_after[$id] = ($dot < $alt_len) ? $alt->[$dot] : undef;
                }
            }
        }
    }
}

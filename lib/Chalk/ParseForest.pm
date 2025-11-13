# ABOUTME: Shared Parse Forest data structure for representing ambiguous parses
# ABOUTME: Provides node classes and forest management independent of semirings
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;
use Chalk::Base;

# Symbol Node - represents a nonterminal symbol at a position
class Chalk::ParseForest::SymbolNode {
    use overload '""' => 'to_string';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;
    field @packed_nodes;

    method add_packed_node($packed_node) {
        my @new_children = $packed_node->children();

        # Check if we already have a packed node with the same children
        for my $existing (@packed_nodes) {
            my @existing_children = $existing->children();

            # Different sizes can't be duplicates, skip
            next unless @existing_children == @new_children;

            # Same size - check if all children are identical references
            my $all_match = 1;
            for my $i (0..$#existing_children) {
                unless (refaddr($existing_children[$i]) == refaddr($new_children[$i])) {
                    $all_match = 0;
                    last;
                }
            }
            return if $all_match;  # Found exact duplicate, don't add
        }

        push( @packed_nodes, $packed_node );
    }

    method packed_nodes() { @packed_nodes }

    method to_string(@args) {
        return "$symbol\[$start_pos(),$end_pos()\]";
    }

    method key() { "$symbol()|$start_pos()|$end_pos()" }
}

# Intermediate Node - represents partial derivation with rule position
# Per Scott's algorithm: labeled as (A ::= α · β, j, i) showing rule and dot position
# Used for binarization of rules with |RHS| > 2 to achieve O(n³) complexity
class Chalk::ParseForest::IntermediateNode {
    use overload '""' => 'to_string';

    field $rule_label :param :reader;  # Format: "A ::= α · β"
    field $start_pos  :param :reader;
    field $end_pos    :param :reader;
    field @packed_nodes;

    method add_packed_node($packed_node) {
        my @new_children = $packed_node->children();

        # Check if we already have a packed node with the same children
        for my $existing (@packed_nodes) {
            my @existing_children = $existing->children();

            # Different sizes can't be duplicates, skip
            next unless @existing_children == @new_children;

            # Same size - check if all children are identical references
            my $all_match = 1;
            for my $i (0..$#existing_children) {
                unless (refaddr($existing_children[$i]) == refaddr($new_children[$i])) {
                    $all_match = 0;
                    last;
                }
            }
            return if $all_match;  # Found exact duplicate, don't add
        }

        push( @packed_nodes, $packed_node );
    }

    method packed_nodes() { @packed_nodes }

    method to_string(@args) {
        return "($rule_label, $start_pos, $end_pos)";
    }

    method key() { "$rule_label|$start_pos|$end_pos" }
}

# Packed Node - represents one alternative parse of a symbol
class Chalk::ParseForest::PackedNode {
    use overload '""' => 'to_string';

    field $rule :param :reader;
    field @children;

    method add_child($child) {
        push( @children, $child );
    }

    method children() { @children }

    method to_string(@args) {
        my $rule_str     = $rule ? $rule->to_string : "terminal";
        my $children_str = join( ", ", map { "$_" } @children );
        return "$rule_str -> [$children_str]";
    }
}

# Terminal Node - represents a terminal symbol at a position
class Chalk::ParseForest::TerminalNode {
    use overload '""' => 'to_string';

    field $symbol    :param :reader;
    field $start_pos :param :reader;
    field $end_pos   :param :reader;

    method to_string(@args) {
        return "'$symbol'\[$start_pos(),$end_pos()\]";
    }

    method key() { "$symbol()|$start_pos()|$end_pos()" }
}

# Parse Forest - manages the collection of parse nodes
class Chalk::ParseForest {
    field %symbol_nodes;
    field %terminal_nodes;
    field %intermediate_nodes;

    method get_or_create_symbol_node( $symbol, $start_pos, $end_pos ) {
        my $key = "$symbol|$start_pos|$end_pos";
        return $symbol_nodes{$key} //= Chalk::ParseForest::SymbolNode->new(
            symbol    => $symbol,
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
    }

    method get_or_create_terminal_node( $symbol, $start_pos, $end_pos ) {
        my $key = "$symbol|$start_pos|$end_pos";
        return $terminal_nodes{$key} //= Chalk::ParseForest::TerminalNode->new(
            symbol    => $symbol,
            start_pos => $start_pos,
            end_pos   => $end_pos
        );
    }

    method get_or_create_intermediate_node( $rule_label, $start_pos, $end_pos ) {
        my $key = "$rule_label|$start_pos|$end_pos";
        return $intermediate_nodes{$key} //= Chalk::ParseForest::IntermediateNode->new(
            rule_label => $rule_label,
            start_pos  => $start_pos,
            end_pos    => $end_pos
        );
    }

    method add_alternative( $node1, $node2 ) {
        my $class = 'Chalk::ParseForest::SymbolNode';
        return unless ref($node1) eq $class && ref($node2) eq $class;

        # Merge all packed nodes from node2 into node1
        my @nodes = $node2->packed_nodes();
        for my $packed (@nodes) {
            $node1->add_packed_node($packed);  # add_packed_node handles de-duplication
        }
    }

    method nodes() {
        return \%symbol_nodes;
    }

    # Get a symbol node by LHS symbol and position span
    method get_node( $lhs, $start_pos, $end_pos ) {
        my $key = "$lhs|$start_pos|$end_pos";
        return $symbol_nodes{$key};
    }
}

1;

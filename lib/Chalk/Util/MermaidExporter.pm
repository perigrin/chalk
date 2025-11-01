# ABOUTME: Visitor pattern exporter for converting IR graphs to Mermaid diagram format
# ABOUTME: Provides to_mermaid() method to generate visualization-ready Mermaid syntax from Sea of Nodes IR
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all);
use utf8;

class Chalk::Util::MermaidExporter {

    # Export IR graph to Mermaid diagram format for visualization
    # Takes a Chalk::IR::Graph object and returns Mermaid syntax string
    sub export($class, $graph) {
        my @lines = ('graph TD');

        my $nodes = $graph->nodes();

        # Return minimal graph if empty
        return join("\n", @lines) if scalar(keys %{$nodes}) == 0;

        # Generate node declarations with labels
        for my $node_id (sort keys %{$nodes}) {
            my $node = $nodes->{$node_id};
            my $op = $node->op();
            my $label = $op;

            # Add attributes to label for important node types
            my $attrs = $node->to_hash()->{attributes} // {};
            if ($op eq 'Constant' && exists $attrs->{value}) {
                $label .= ": $attrs->{value}";
            }

            # Sanitize node_id for Mermaid (replace hyphens with underscores)
            my $safe_id = $node_id;
            $safe_id =~ s/-/_/g;

            push @lines, "    $safe_id" . "[$label]";
        }

        # Generate edges from node inputs
        for my $node_id (sort keys %{$nodes}) {
            my $node = $nodes->{$node_id};
            my $safe_target = $node_id;
            $safe_target =~ s/-/_/g;

            for my $input_id ($node->inputs()->@*) {
                next unless defined $input_id;
                my $safe_source = $input_id;
                $safe_source =~ s/-/_/g;
                push @lines, "    $safe_source --> $safe_target";
            }
        }

        return join("\n", @lines);
    }
}

1;

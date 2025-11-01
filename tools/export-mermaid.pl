#!/usr/bin/env perl
# ABOUTME: Command-line tool to export Chalk IR graphs to Mermaid diagram format
# ABOUTME: Usage: export-mermaid.pl <graph-file.pl> [output.md]
use 5.42.0;
use utf8;
use lib 'lib';
use lib 'tools';
use MermaidExporter;

sub usage {
    print STDERR <<'EOF';
Usage: export-mermaid.pl <graph-script.pl> [output.md]

Export a Chalk IR graph to Mermaid diagram format.

Arguments:
  graph-script.pl  - Perl script that creates and returns a Chalk::IR::Graph object
  output.md        - Optional output file (defaults to STDOUT)

Example:
  # Create a graph script (my-graph.pl):
  use 5.42.0;
  use lib 'lib';
  use Chalk::IR::Graph;
  use Chalk::IR::Node;

  my $graph = Chalk::IR::Graph->new();
  my $start = Chalk::IR::Node->new(
      id => 'n1', op => 'Start', inputs => [], attributes => {}
  );
  my $const = Chalk::IR::Node->new(
      id => 'n2', op => 'Constant', inputs => ['n1'],
      attributes => { value => 42, type => 'int' }
  );
  $graph->add_node($start);
  $graph->add_node($const);
  return $graph;

  # Export it:
  tools/export-mermaid.pl my-graph.pl > graph.md

EOF
    exit 1;
}

# Parse arguments
my $graph_file = shift @ARGV or usage();
my $output_file = shift @ARGV;

# Validate input file
unless (-f $graph_file) {
    die "Error: Graph file '$graph_file' not found\n";
}

# Load and execute the graph script
my $graph = do $graph_file;
die "Error loading graph: $@\n" if $@;
die "Error: Graph file must return a Chalk::IR::Graph object\n"
    unless $graph && $graph->isa('Chalk::IR::Graph');

# Export to Mermaid
my $mermaid = MermaidExporter->export($graph);

# Output
if ($output_file) {
    open my $fh, '>', $output_file
        or die "Error: Cannot write to '$output_file': $!\n";
    print $fh "```mermaid\n";
    print $fh $mermaid;
    print $fh "\n```\n";
    close $fh;
    print "Exported Mermaid diagram to: $output_file\n";
} else {
    print "```mermaid\n";
    print $mermaid;
    print "\n```\n";
}

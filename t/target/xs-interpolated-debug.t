# ABOUTME: Debug test to inspect IR before XS generation
# ABOUTME: Helps diagnose why Constant values are objects instead of strings

use 5.42.0;
use Test::More;
use Data::Dumper;

BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::ChalkIR;
use Scalar::Util 'blessed';

my $code = q{sub msg { return "Simple message"; }};

my $bnf_file = "grammar/chalk.bnf";
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $content = do { local $/; <$fh> };
close $fh;

my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');
my $semiring = Chalk::Semiring::ChalkIR->new(grammar => $grammar);
my $parser = Chalk::Parser->new(
    grammar => $grammar,
    semiring => $semiring,
);

my $result = $parser->parse_string($code);
ok(defined $result, 'Parse succeeded');

my $winning_node;
if ($result->can('context')) {
    my $ctx = $result->context;
    if ($ctx->can('focus')) {
        $winning_node = $ctx->focus;
    }
}

ok(defined $winning_node, 'Got winning node');

# Find all Constant nodes
my @constants;
my %visited;
my @queue = ($winning_node);

while (@queue) {
    my $node = shift @queue;
    next unless blessed($node) && $node->can('id');
    my $node_id = $node->id;
    next if $visited{$node_id}++;

    if ($node->can('op') && $node->op eq 'Constant') {
        push @constants, $node;
        diag "Found Constant node:";
        diag "  ID: " . $node->id;
        diag "  Value: " . Dumper($node->value);
        diag "  Type: " . ref($node->type);
    }

    # Traverse
    for my $method (qw(value_node value control left right operand condition source call callee)) {
        next unless $node->can($method);
        my $ref = $node->$method;
        next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
        push @queue, $ref;
    }

    for my $method (qw(branches control_users args parts return_nodes function_defs)) {
        next unless $node->can($method) && $node->$method;
        my $arr = $node->$method;
        next unless ref($arr) eq 'ARRAY';
        for my $ref (@$arr) {
            next unless blessed($ref) && $ref->can('id') && !$visited{$ref->id};
            push @queue, $ref;
        }
    }
}

ok(scalar(@constants) > 0, 'Found at least one Constant');

done_testing();

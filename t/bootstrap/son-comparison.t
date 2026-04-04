# ABOUTME: Compares Chalk IR against perl5-son optree translation for structural equivalence.
# ABOUTME: Validates that Chalk's parser produces correct Sea of Nodes graphs for compiled methods.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# Skip if perl5-son not installed
eval { require SoN::FromOptree; require SoN::Render::Text; require SoN::Compare; 1 }
    or plan skip_all => 'perl5-son not installed';

use SoN::FromOptree;
use SoN::Render::Text;
use SoN::Compare;
use Chalk::Bootstrap::IR::ToSoN;
use TestPerlHelpers qw(setup_perl_grammar parse_file_with_cfg);

my $renderer = SoN::Render::Text->new();
my $comparator = SoN::Compare->new();
my $adapter = Chalk::Bootstrap::IR::ToSoN->new();

# Build grammar pipeline
my $gen_grammar = eval { setup_perl_grammar('Chalk::Grammar::Perl::SoNComparison') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# Helper: compare a method from a file through both paths
# ============================================================

my sub compare_method(%args) {
    my $file        = $args{file};
    my $class_name  = $args{class_name};
    my $method_name = $args{method_name};
    my $field_map   = $args{field_map} // {};

    subtest "$class_name\::$method_name" => sub {
        # Path 1: perl5-son from optree
        my $class_pkg = $class_name;
        eval "require $class_pkg" unless $class_pkg->can($method_name);
        my $method_ref = $class_pkg->can($method_name);
        ok(defined $method_ref, "can find $method_name in $class_name") or return;

        my $optree_graph = eval { SoN::FromOptree->translate($method_ref) };
        ok(defined $optree_graph, "optree translation succeeds") or do {
            diag "FromOptree error: $@";
            return;
        };

        # Path 2: Chalk parser → IR → ToSoN adapter
        my ($ir, $sa, $ctx) = parse_file_with_cfg($gen_grammar, $file);
        ok(defined $ir, "Chalk parses $file") or return;

        # Find the MethodDecl
        my $method_ir;
        my $stmts = $ir->inputs()->[0];
        for my $stmt ($stmts->@*) {
            next unless $stmt isa Chalk::Bootstrap::IR::Node::Constructor;
            next unless $stmt->class() eq 'ClassDecl';
            my $body = $stmt->inputs()->[2];
            for my $item ($body->@*) {
                next unless $item isa Chalk::Bootstrap::IR::Node::Constructor;
                next unless $item->class() eq 'MethodDecl';
                if ($item->inputs()->[0]->value() eq $method_name) {
                    $method_ir = $item;
                    last;
                }
            }
        }
        ok(defined $method_ir, "found MethodDecl for $method_name") or return;

        my $chalk_graph = eval {
            $adapter->translate_method($method_ir, $class_name, $field_map)
        };
        ok(defined $chalk_graph, "Chalk→SoN translation succeeds") or do {
            diag "ToSoN error: $@";
            return;
        };

        # Render both for diagnostics
        my $optree_text = $renderer->render($optree_graph);
        my $chalk_text  = $renderer->render($chalk_graph);
        diag "optree:\n$optree_text";
        diag "chalk:\n$chalk_text";

        # Compare
        my $diff = $comparator->diff($optree_graph, $chalk_graph);
        if ($diff->is_empty()) {
            pass("graphs are structurally equivalent");
        } else {
            # For now, report diffs as diagnostics rather than failures
            # since the adapter is a proof of concept
            diag "Structural differences:\n" . $diff->to_text();
            # Count only operation-type mismatches as real failures
            my @real_diffs = grep {
                $_->{type} ne 'stamp'  # stamp differences are expected
            } $diff->diffs()->@*;
            is(scalar @real_diffs, 0, "no structural differences (ignoring stamps)")
                or diag "Non-stamp diffs: " . scalar @real_diffs;
        }
    };
}

# ============================================================
# Symbol.pm — simple field-based methods
# ============================================================

my %symbol_fields = (
    '$type'       => 0,
    '$value'      => 1,
    '$quantifier' => 2,
);

compare_method(
    file        => 'lib/Chalk/Grammar/Symbol.pm',
    class_name  => 'Chalk::Grammar::Symbol',
    method_name => 'is_terminal',
    field_map   => \%symbol_fields,
);

compare_method(
    file        => 'lib/Chalk/Grammar/Symbol.pm',
    class_name  => 'Chalk::Grammar::Symbol',
    method_name => 'is_reference',
    field_map   => \%symbol_fields,
);

compare_method(
    file        => 'lib/Chalk/Grammar/Symbol.pm',
    class_name  => 'Chalk::Grammar::Symbol',
    method_name => 'is_quantified',
    field_map   => \%symbol_fields,
);

done_testing;

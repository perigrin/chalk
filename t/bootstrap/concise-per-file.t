# ABOUTME: Per-file oracle validation: parse real .pm files, compare ConciseTree against B::Concise.
# ABOUTME: Tests that the full pipeline produces correct ops for actual source files, tiered by complexity.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_concise_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::ConciseTree;
use Chalk::Bootstrap::ConciseTree::Oracle;
use Chalk::Bootstrap::ConciseTree::Comparator;

# Check B::Concise is available
my $concise_check = `perl -MO=Concise,-exec -e '1' 2>&1`;
my $has_concise = ($concise_check =~ /enter/);

# Build the Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::PerFileValidation/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::PerFileValidation::grammar();
    my $parser = build_perl_concise_parser($gen_grammar, start => 'Program');
    skip 'Concise parser not built', 1 unless defined $parser;

    my $oracle = Chalk::Bootstrap::ConciseTree::Oracle->new();
    my $comparator = Chalk::Bootstrap::ConciseTree::Comparator->new();

    # Helper: parse a .pm file and return our ConciseTree
    my sub our_tree_for_file($file) {
        my $source = do {
            open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
            local $/;
            <$fh>;
        };
        my $result = $parser->parse_value($source);
        return undef unless defined $result;
        return undef unless $result->[0]; # Boolean
        return $result->[4]->extract();   # SemanticAction result
    }

    # Helper: get B::Concise oracle tree for a .pm file
    my sub oracle_tree_for_file($file) {
        skip "B::Concise not available", 1 unless $has_concise;
        my $output = `perl -Ilib -MO=Concise,-exec $file 2>&1`;
        return $oracle->parse_concise_output($output);
    }

    # Helper: run per-file comparison and report
    my sub validate_file($file, $label) {
        my $ours = our_tree_for_file($file);
        ok(defined $ours, "$label: parses successfully")
            or diag("Parse returned undef for $file");

        SKIP: {
            skip "$label did not parse", 1 unless defined $ours;
            my $theirs = oracle_tree_for_file($file);
            skip "B::Concise oracle failed for $file", 1 unless defined $theirs;

            my $cmp = $comparator->compare($ours, $theirs);
            ok($cmp->{match}, "$label: matches B::Concise oracle")
                or diag(
                    "File: $file\n",
                    "Differences:\n",
                    (map { "  $_\n" } $cmp->{differences}->@*),
                    "Ours: ", join(", ", map { $_->structural_key() } $ours->ops()->@*), "\n",
                    "Theirs: ", join(", ", map { $_->structural_key() } $theirs->ops()->@*), "\n",
                );
        }
    }

    # ========================================================================
    # Tier A: Simplest files (11-15 lines)
    # Pure data classes with use declarations, feature class, simple methods
    # returning string constants. All constructs already have action methods.
    # ========================================================================

    validate_file(
        'lib/Chalk/Bootstrap/IR/Node/Start.pm',
        'Tier A: IR::Node::Start',
    );

    validate_file(
        'lib/Chalk/Bootstrap/IR/Node/Return.pm',
        'Tier A: IR::Node::Return',
    );

    validate_file(
        'lib/Chalk/Bootstrap/Target.pm',
        'Tier A: Target',
    );

    validate_file(
        'lib/Chalk/Bootstrap/Optimizer/Pass.pm',
        'Tier A: Optimizer::Pass',
    );

    # ========================================================================
    # Tier B: Classes with field declarations (17-22 lines)
    # Same as Tier A but with field declarations, which cause B::Concise to
    # emit nextstate instead of stub inside the class body.
    # ========================================================================

    validate_file(
        'lib/Chalk/Bootstrap/IR/Node/Constant.pm',
        'Tier B: IR::Node::Constant',
    );

    validate_file(
        'lib/Chalk/Bootstrap/Target/XS/AST/Node.pm',
        'Tier B: XS::AST::Node',
    );

    validate_file(
        'lib/Chalk/Bootstrap/Target/XS/AST/Statement.pm',
        'Tier B: XS::AST::Statement',
    );

    validate_file(
        'lib/Chalk/Bootstrap/Target/XS/AST/Module.pm',
        'Tier B: XS::AST::Module',
    );

    validate_file(
        'lib/Chalk/Bootstrap/IR/Node/Constructor.pm',
        'Tier B: IR::Node::Constructor',
    );
}

done_testing;

# ABOUTME: Tests Perl IR to Perl source code emission for all .pm files under lib/.
# ABOUTME: Dynamically scans lib/ and validates codegen for each file found.
use 5.42.0;
use utf8;
use Test::More;
use File::Find;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate eval_module);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_perl_grammar('Chalk::Grammar::Perl::TargetPerlTierDTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# Collect all .pm files under lib/
# ============================================================

my @pm_files;
find(sub {
    return unless /\.pm$/;
    push @pm_files, $File::Find::name;
}, 'lib');
@pm_files = sort @pm_files;

ok(scalar @pm_files > 0, 'found .pm files to test');

# ============================================================
# Known parse/eval issues — mark as TODO rather than failing
# ============================================================

my %TODO_PARSE = (
    'lib/Chalk/Bootstrap/Perl/Actions.pm'
        => 'complex anonymous sub/hash patterns',
    'lib/Chalk/Bootstrap/BNF/Target/XS.pm'
        => 'pre-existing parse failure',
);

# Files with known eval failures (parse succeeds but eval doesn't)
my %TODO_EVAL = (
    'lib/Chalk/Bootstrap/IR/NodeFactory.pm'
        => 'delete argument codegen issue',
    # Boolean.pm and Structural.pm: FIXED (scoping fix unblocked them)
    'lib/Chalk/Bootstrap/Semiring/Precedence.pm'
        => 'complex hash operations',
    'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm'
        => 'exists argument codegen',
    'lib/Chalk/Bootstrap/Semiring/TypeInference.pm'
        => 'complex coderef/tree-walker patterns',
    'lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm'
        => 'complex method dispatch patterns',
    'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm'
        => 'complex semiring delegation',
    'lib/Chalk/Bootstrap/Perl/Target/Perl.pm'
        => 'complex string interpolation patterns',
    # KeywordTable.pm and PrecedenceTable.pm: FIXED (scoping + hash init)
    'lib/Chalk/Grammar/Perl/TypeLibrary.pm'
        => 'my sub declarations emit incorrectly',
    'lib/Chalk/Bootstrap/BNF/Target/XS/AST/XSUB.pm'
        => 'depends on parent class Node and VarDecl isa check',
    'lib/Chalk/Bootstrap/Optimizer/DCE.pm'
        => 'depends on parent class Optimizer::Pass',
    'lib/Chalk/Bootstrap/Desugar.pm'
        => 'depends on Grammar::Rule/Symbol classes',
    'lib/Chalk/Grammar/BNF.pm'
        => 'depends on Rule/Symbol classes',
    'lib/Chalk/Grammar/BNF/Generated.pm'
        => 'depends on Symbol/Rule/BNF classes',
    'lib/Chalk/Grammar/BNF/Actions.pm'
        => 'depends on Symbol/Rule constructors',
    'lib/Chalk/Grammar/Chalk/Rule/ExpressionList.pm'
        => 'depends on Rule parent class',
);

# ============================================================
# Test each file
# ============================================================

for my $file (@pm_files) {
    # Derive a short label from the file path
    (my $label = $file) =~ s{^lib/}{};

    subtest $label => sub {
        # Step 1: Parse and generate
        my $code;
        if (my $reason = $TODO_PARSE{$file}) {
            $code = eval { parse_and_generate($gen_grammar, $file) };
            TODO: {
                local $TODO = $reason;
                ok(defined $code, 'generated Perl code');
            }
            return unless defined $code;
        } else {
            $code = eval { parse_and_generate($gen_grammar, $file) };
            if (!defined $code) {
                # Unexpected parse failure — report but don't die
                fail("generated Perl code");
                diag("Parse error: $@") if $@;
                return;
            }
            pass('generated Perl code');
        }

        # Step 2: Derive namespace for eval
        (my $ns = $file) =~ s{^lib/}{};
        $ns =~ s{/}{::}g;
        $ns =~ s{\.pm$}{};
        my $test_ns = "${ns}::GenTierD";

        # Step 3: Eval
        if (my $reason = $TODO_EVAL{$file}) {
            my ($ok, $err) = eval_module($code, $ns, $test_ns);
            TODO: {
                local $TODO = $reason;
                ok($ok, 'evals cleanly') or diag "Error: $err";
            }
        } else {
            my ($ok, $err) = eval_module($code, $ns, $test_ns);
            ok($ok, 'evals cleanly') or diag "Error: $err";
        }
    };
}

done_testing();

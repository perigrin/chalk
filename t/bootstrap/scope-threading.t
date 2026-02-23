# ABOUTME: Tests that VarDecl populates scope via post-parse tree walk.
# ABOUTME: Verifies build_scope extracts variable bindings from parsed Context tree.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScopeThreadTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ScopeThreadTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    # Get the SemanticAction semiring from the parser's FilterComposite
    my $semiring = $parser->semiring();
    # FilterComposite stores semirings array — SemanticAction is index 4
    my $sa = $semiring->semirings()->[4];
    ok($sa isa Chalk::Bootstrap::Semiring::SemanticAction, 'got SemanticAction from parser');

    # --- Test 1: Simple variable declaration populates scope ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $x = 42;');
        ok(defined $result, 'my $x = 42 parses');

        my $sem_ctx = $result->[4];
        ok(defined $sem_ctx, 'SemanticAction context exists');

        # Build scope from parse tree via post-parse walk
        my $scope = $sa->build_scope($sem_ctx);
        ok($scope isa Chalk::Bootstrap::Scope, 'build_scope returns a Scope');
        my $x_node = $scope->lookup('$x');
        ok(defined $x_node, '$x is in scope after declaration');
    }

    # --- Test 2: Multiple declarations accumulate in scope ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $a = 1; my $b = 2;');
        ok(defined $result, 'two declarations parse');

        my $sem_ctx = $result->[4];
        my $scope = $sa->build_scope($sem_ctx);
        ok($scope isa Chalk::Bootstrap::Scope, 'build_scope returns a Scope');
        ok(defined $scope->lookup('$a'), '$a is in scope');
        ok(defined $scope->lookup('$b'), '$b is in scope');
    }

    # --- Test 3: cfg_state still works for control flow ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $y = 1;');
        ok(defined $result, 'my $y = 1 parses');

        my $sem_ctx = $result->[4];
        my $state = $sa->cfg_state($sem_ctx);
        ok(defined $state, 'cfg_state available on parse result');
        ok($state->{scope} isa Chalk::Bootstrap::Scope, 'state has a Scope');
    }
}

done_testing();

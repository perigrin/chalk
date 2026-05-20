# ABOUTME: Tests that VarDecl populates scope via parse-time cfg_state propagation.
# ABOUTME: Verifies cfg_state scope threading extracts variable bindings from parsed Context tree.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Scope;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Build the Perl grammar recognizer pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $ir = perl_pipeline();

SKIP: {
    skip 'Perl grammar failed to parse', 1 unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    my $generated = $target->generate($ir);
    $generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ScopeThreadTest/g;
    eval $generated;
    skip "Generated code failed to compile: $@", 1 if $@;

    my $gen_grammar = Chalk::Grammar::Perl::ScopeThreadTest::grammar();
    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    skip 'IR parser not built', 1 unless defined $parser;

    # Get the SemanticAction semiring from the parser's FilterComposite
    my $semiring = $parser->semiring();
    # FilterComposite stores semirings array -- SemanticAction is index 4
    my $sa = $semiring->semirings()->[4];
    ok($sa isa Chalk::Bootstrap::Semiring::SemanticAction, 'got SemanticAction from parser');

    # --- Test 1: Simple variable declaration populates scope via cfg_state ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $x = 42;');
        ok(defined $result, 'my $x = 42 parses');

        my $sem_ctx = $result;
        ok(defined $sem_ctx, 'SemanticAction context exists');

        # cfg_state scope should contain $x from parse-time propagation
        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state available on parse result');
        ok($state->{scope} isa Chalk::Bootstrap::Scope, 'state has a Scope');
        my $x_node = $state->{scope}->lookup('$x');
        ok(defined $x_node, '$x is in scope after declaration');
    }

    # --- Test 2: Multiple declarations accumulate in scope ---
    {
        Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
        $semiring->reset_cache();

        my $result = $parser->parse_value('my $a = 1; my $b = 2;');
        ok(defined $result, 'two declarations parse');

        my $sem_ctx = $result;
        my $state = $sem_ctx->cfg_state();
        ok(defined $state, 'cfg_state available');
        ok($state->{scope} isa Chalk::Bootstrap::Scope, 'state has a Scope');
        ok(defined $state->{scope}->lookup('$a'), '$a is in scope');
        ok(defined $state->{scope}->lookup('$b'), '$b is in scope');
    }
}

done_testing();

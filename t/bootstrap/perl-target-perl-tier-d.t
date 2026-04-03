# ABOUTME: Tests Perl IR to Perl source code emission for Tier D files.
# ABOUTME: Validates generated Perl compiles, evals, and behaves equivalently for 31 uncovered files.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPerlHelpers qw(setup_perl_grammar parse_and_generate eval_module);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_perl_grammar('Chalk::Grammar::Perl::TargetPerlTierDTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# Helper: test a file with structural checks, optional eval+behavioral
# ============================================================

my sub test_perl_file(%args) {
    my $file             = $args{file};
    my $label            = $args{label};
    my $structural       = $args{structural} // [];
    my $original_ns      = $args{original_ns};
    my $test_ns          = $args{test_ns};
    my $behavioral       = $args{behavioral};
    my $todo_parse       = $args{todo_parse};
    my $todo_eval        = $args{todo_eval};
    my $todo_structural  = $args{todo_structural};

    subtest $label => sub {
        my $code;
        if ($todo_parse) {
            $code = eval { parse_and_generate($gen_grammar, $file) };
            TODO: {
                local $TODO = $todo_parse;
                ok(defined $code, 'generated Perl code');
            }
            return unless defined $code;
        } else {
            $code = parse_and_generate($gen_grammar, $file);
            ok(defined $code, 'generated Perl code') or return;
        }

        for my $check ($structural->@*) {
            if ($todo_structural && $code !~ $check->{pattern}) {
                TODO: {
                    local $TODO = $todo_structural;
                    like($code, $check->{pattern}, $check->{label});
                }
            } else {
                like($code, $check->{pattern}, $check->{label});
            }
        }

        # If no namespace provided, structural-only test
        return unless defined $original_ns;

        my ($ok, $err);
        if ($todo_eval) {
            ($ok, $err) = eval_module($code, $original_ns, $test_ns);
            TODO: {
                local $TODO = $todo_eval;
                ok($ok, 'evals cleanly') or diag "Error: $err";
            }
            return unless $ok;
        } else {
            ($ok, $err) = eval_module($code, $original_ns, $test_ns);
            ok($ok, 'evals cleanly') or do { diag "Error: $err"; return };
        }

        if ($behavioral) {
            $behavioral->($test_ns);
        }
    };
}

# ============================================================
# Data model classes
# ============================================================

test_perl_file(
    file        => 'lib/Chalk/Grammar/Symbol.pm',
    label       => 'Symbol.pm',
    structural  => [
        { pattern => qr/field \$type/, label => 'has field $type' },
        { pattern => qr/field \$value/, label => 'has field $value' },
        { pattern => qr/method is_terminal/, label => 'has method is_terminal' },
        { pattern => qr/method to_string/, label => 'has method to_string' },
    ],
    original_ns => 'Chalk::Grammar::Symbol',
    test_ns     => 'Chalk::Grammar::SymbolGenD',
    behavioral  => sub ($mod) {
        my $sym = $mod->new(type => 'terminal', value => '/\\d+/');
        is($sym->type(), 'terminal', 'type reader');
        is($sym->value(), '/\\d+/', 'value reader');
        ok($sym->is_terminal(), 'is_terminal returns true');
        ok(!$sym->is_reference(), 'is_reference returns false');
        ok(!$sym->is_quantified(), 'unquantified symbol');

        my $ref_sym = $mod->new(
            type => 'reference', value => 'Expression', quantifier => '+',
        );
        ok($ref_sym->is_reference(), 'reference symbol');
        ok($ref_sym->is_quantified(), 'quantified symbol');
        like($ref_sym->to_string(), qr/Expression\+/, 'to_string includes quantifier');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Grammar/Rule.pm',
    label       => 'Rule.pm',
    structural  => [
        { pattern => qr/field \$name/, label => 'has field $name' },
        { pattern => qr/field \$expressions/, label => 'has field $expressions' },
        { pattern => qr/method alternative_count/, label => 'has method alternative_count' },
    ],
    original_ns => 'Chalk::Grammar::Rule',
    test_ns     => 'Chalk::Grammar::RuleGenD',
    behavioral  => sub ($mod) {
        use Chalk::Grammar::Symbol;
        my $sym1 = Chalk::Grammar::Symbol->new(type => 'reference', value => 'Foo');
        my $sym2 = Chalk::Grammar::Symbol->new(type => 'terminal', value => '/bar/');
        my $rule = $mod->new(
            name => 'TestRule',
            expressions => [[$sym1, $sym2], [$sym2]],
        );
        is($rule->name(), 'TestRule', 'name reader');
        is($rule->alternative_count(), 2, 'alternative_count');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/Terminal.pm',
    label       => 'Terminal.pm',
    structural  => [
        { pattern => qr/Terminal/, label => 'contains Terminal class' },
        { pattern => qr/sub match/, label => 'has sub match declaration' },
    ],
    original_ns => 'Chalk::Bootstrap::Terminal',
    test_ns     => 'Chalk::Bootstrap::TerminalGenD',
    behavioral  => sub ($mod) {
        # match is a sub (not method), call as package function
        my $match = $mod->can('match');
        ok(defined $match, 'match function exists');
        if ($match) {
            my $end = $match->("hello123world", 5, '\d+');
            is($end, 8, 'match returns correct end position');
            my $no = $match->("hello", 0, '\d+');
            is($no, undef, 'match returns undef on no match');
        }
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/IR/Node.pm',
    label       => 'IR::Node.pm',
    structural  => [
        { pattern => qr/field \$id/, label => 'has field $id' },
        { pattern => qr/method add_consumer/, label => 'has method add_consumer' },
        { pattern => qr/method remove_consumer/, label => 'has method remove_consumer' },
    ],
    original_ns => 'Chalk::Bootstrap::IR::Node',
    test_ns     => 'Chalk::Bootstrap::IR::NodeGenD',
    behavioral  => sub ($mod) {
        my $node = $mod->new(id => 'test_1');
        is($node->id(), 'test_1', 'id reader');
        is(ref($node->inputs()), 'ARRAY', 'inputs returns arrayref');
        is(ref($node->consumers()), 'ARRAY', 'consumers returns arrayref');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/IR/NodeFactory.pm',
    label       => 'IR::NodeFactory.pm',
    structural  => [
        { pattern => qr/NodeFactory/, label => 'contains NodeFactory class' },
        { pattern => qr/method make/, label => 'has method make' },
    ],
    original_ns => 'Chalk::Bootstrap::IR::NodeFactory',
    test_ns     => 'Chalk::Bootstrap::IR::NodeFactoryGenD',
    todo_parse  => 'IR::NodeFactory.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'NodeFactory.pm depends on IR::Node classes',
    behavioral  => sub ($mod) {
        my $factory = $mod->new();
        ok(defined $factory, 'NodeFactory can be constructed');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/Optimizer/DCE.pm',
    label       => 'Optimizer::DCE.pm',
    structural  => [
        { pattern => qr/method name/, label => 'has method name' },
        { pattern => qr/method run/, label => 'has method run' },
    ],
    original_ns => 'Chalk::Bootstrap::Optimizer::DCE',
    test_ns     => 'Chalk::Bootstrap::Optimizer::DCEGenD',
    todo_eval   => 'DCE.pm depends on parent class Optimizer::Pass which may not be available',
    behavioral  => sub ($mod) {
        my $dce = $mod->new();
        is($dce->name(), 'DCE', 'name returns DCE');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/Optimizer.pm',
    label       => 'Optimizer.pm',
    structural  => [
        { pattern => qr/method add_pass/, label => 'has method add_pass' },
        { pattern => qr/method optimize/, label => 'has method optimize' },
        { pattern => qr/method pass_count/, label => 'has method pass_count' },
    ],
    original_ns => 'Chalk::Bootstrap::Optimizer',
    test_ns     => 'Chalk::Bootstrap::OptimizerGenD',
    todo_eval   => 'Grammar fragmentation: field() default syntax',
    behavioral  => sub ($mod) {
        my $opt = $mod->new();
        is($opt->pass_count(), 0, 'new optimizer has 0 passes');
    },
);

# ============================================================
# Semiring classes
# ============================================================

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/Semiring/Boolean.pm',
    label       => 'Semiring::Boolean.pm',
    structural  => [
        { pattern => qr/method zero/, label => 'has method zero' },
        { pattern => qr/method one/, label => 'has method one' },
        { pattern => qr/method multiply/, label => 'has method multiply' },
        { pattern => qr/method add/, label => 'has method add' },
    ],
    original_ns => 'Chalk::Bootstrap::Semiring::Boolean',
    test_ns     => 'Chalk::Bootstrap::Semiring::BooleanGenD',
    todo_eval   => 'Grammar fragmentation: unless defined in method body',
    behavioral  => sub ($mod) {
        my $bool = $mod->new();
        ok(defined $bool->zero(), 'zero is defined');
        ok($bool->one(), 'one is truthy');
        ok($bool->is_zero($bool->zero()), 'zero detected');
        ok(!$bool->is_zero($bool->one()), 'one is not zero');
    },
);

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/Structural.pm',
    label      => 'Semiring::Structural.pm',
    structural => [
        { pattern => qr/method zero/, label => 'has method zero' },
        { pattern => qr/method one/, label => 'has method one' },
        { pattern => qr/method multiply/, label => 'has method multiply' },
        { pattern => qr/method add/, label => 'has method add' },
        { pattern => qr/method on_scan/, label => 'has method on_scan' },
        { pattern => qr/method on_complete/, label => 'has method on_complete' },
    ],
    original_ns => 'Chalk::Bootstrap::Semiring::Structural',
    test_ns     => 'Chalk::Bootstrap::Semiring::StructuralGenD',
    todo_eval   => 'Grammar fragmentation: complex bitfield operations',
    behavioral  => sub ($mod) {
        my $s = $mod->new();
        is($s->zero(), 0, 'zero is 0');
        is($s->one(), 1, 'one is 1');
        ok($s->is_zero(0), '0 is zero');
        ok(!$s->is_zero(1), '1 is not zero');
        is($s->multiply(3, 5), 3 | 5, 'multiply is bitwise OR');
    },
);

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/Precedence.pm',
    label      => 'Semiring::Precedence.pm',
    structural => [
        { pattern => qr/method zero/, label => 'has method zero' },
        { pattern => qr/method one/, label => 'has method one' },
        { pattern => qr/method multiply/, label => 'has method multiply' },
        { pattern => qr/method add/, label => 'has method add' },
    ],
    original_ns => 'Chalk::Bootstrap::Semiring::Precedence',
    test_ns     => 'Chalk::Bootstrap::Semiring::PrecedenceGenD',
    todo_eval   => 'Grammar fragmentation: complex hash operations',
    behavioral  => sub ($mod) {
        my $p = $mod->new();
        ok(!defined $p->zero(), 'zero is undef');
        ok(defined $p->one(), 'one is defined');
        ok($p->is_zero(undef), 'undef is zero');
        ok(!$p->is_zero($p->one()), 'one is not zero');
    },
);

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm',
    label      => 'Semiring::SemanticAction.pm',
    structural => [
        { pattern => qr/method zero/, label => 'has method zero' },
        { pattern => qr/method one/, label => 'has method one' },
        { pattern => qr/method multiply/, label => 'has method multiply' },
        { pattern => qr/method add/, label => 'has method add' },
    ],
    original_ns => 'Chalk::Bootstrap::Semiring::SemanticAction',
    test_ns     => 'Chalk::Bootstrap::Semiring::SemanticActionGenD',
    todo_parse  => 'Semiring::SemanticAction.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'Grammar fragmentation: complex sub/coderef patterns',
    behavioral  => sub ($mod) {
        my $sa = $mod->new(actions => {}, ir_factory => undef);
        ok(!defined $sa->zero(), 'zero is undef');
        ok(defined $sa->one(), 'one is defined');
        ok($sa->is_zero(undef), 'undef is zero');
    },
);

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/TypeInference.pm',
    label      => 'Semiring::TypeInference.pm',
    structural => [
        { pattern => qr/method zero/, label => 'has method zero' },
        { pattern => qr/method one/, label => 'has method one' },
        { pattern => qr/method multiply/, label => 'has method multiply' },
        { pattern => qr/method add/, label => 'has method add' },
        { pattern => qr/method should_scan/, label => 'has method should_scan' },
    ],
    original_ns => 'Chalk::Bootstrap::Semiring::TypeInference',
    test_ns     => 'Chalk::Bootstrap::Semiring::TypeInferenceGenD',
    todo_parse  => 'Semiring::TypeInference.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'Grammar fragmentation: complex coderef/tree-walker patterns',
    behavioral  => sub ($mod) {
        my $ti = $mod->new(
            keyword_check  => sub ($w) { false },
            builtin_lookup => sub ($n) { undef },
        );
        ok(!defined $ti->zero(), 'zero is undef');
        ok(defined $ti->one(), 'one is defined');
        ok($ti->is_zero(undef), 'undef is zero');
    },
);

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm',
    label      => 'Semiring::TypeInferenceActions.pm',
    structural => [
        { pattern => qr/TypeInferenceActions/, label => 'contains TypeInferenceActions class' },
    ],
    original_ns => 'Chalk::Bootstrap::Semiring::TypeInferenceActions',
    test_ns     => 'Chalk::Bootstrap::Semiring::TypeInferenceActionsGenD',
    todo_parse  => 'Semiring::TypeInferenceActions.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'Grammar fragmentation: complex method dispatch patterns',
    behavioral  => sub ($mod) {
        my $actions = $mod->new();
        ok(defined $actions, 'TypeInferenceActions can be constructed');
    },
);

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm',
    label      => 'Semiring::FilterComposite.pm',
    structural => [
        { pattern => qr/method zero/, label => 'has method zero' },
        { pattern => qr/method one/, label => 'has method one' },
        { pattern => qr/method add/, label => 'has method add' },
        { pattern => qr/method multiply/, label => 'has method multiply' },
    ],
    original_ns => 'Chalk::Bootstrap::Semiring::FilterComposite',
    test_ns     => 'Chalk::Bootstrap::Semiring::FilterCompositeGenD',
    todo_eval   => 'Grammar fragmentation: complex semiring delegation',
    behavioral  => sub ($mod) {
        use Chalk::Bootstrap::Semiring::Boolean;
        my $bool = Chalk::Bootstrap::Semiring::Boolean->new();
        my $fc = $mod->new(semirings => [$bool]);
        ok(defined $fc, 'FilterComposite can be constructed');
    },
);

# ============================================================
# Static/utility modules
# ============================================================

test_perl_file(
    file        => 'lib/Chalk/Grammar/Perl/KeywordTable.pm',
    label       => 'KeywordTable.pm',
    structural  => [
        { pattern => qr/KeywordTable/, label => 'contains KeywordTable class' },
    ],
    original_ns => 'Chalk::Grammar::Perl::KeywordTable',
    test_ns     => 'Chalk::Grammar::Perl::KeywordTableGenD',
    todo_parse  => 'KeywordTable.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'sub inside class emits as string literal',
);

test_perl_file(
    file        => 'lib/Chalk/Grammar/Perl/PrecedenceTable.pm',
    label       => 'PrecedenceTable.pm',
    structural  => [
        { pattern => qr/PrecedenceTable/, label => 'contains PrecedenceTable class' },
    ],
    original_ns => 'Chalk::Grammar::Perl::PrecedenceTable',
    test_ns     => 'Chalk::Grammar::Perl::PrecedenceTableGenD',
    todo_parse  => 'PrecedenceTable.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'sub inside class emits as string literal',
);

test_perl_file(
    file       => 'lib/Chalk/Grammar/Perl/TypeLibrary.pm',
    label      => 'TypeLibrary.pm',
    structural => [
        { pattern => qr/TypeLibrary/, label => 'contains TypeLibrary' },
        # type_satisfies and get_builtin are `my sub` lexical subs;
        # the IR emits them as string literals, not function definitions.
        { pattern => qr/get_builtin/, label => 'has get_builtin reference' },
    ],
    original_ns => 'Chalk::Grammar::Perl::TypeLibrary',
    test_ns     => 'Chalk::Grammar::Perl::TypeLibraryGenD',
    todo_parse  => 'TypeLibrary.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'my sub declarations emit as string literals, not function definitions',
);

# ============================================================
# XS AST classes
# ============================================================

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/BNF/Target/XS/AST/CompositeNode.pm',
    label       => 'XS::AST::CompositeNode.pm',
    structural  => [
        { pattern => qr/field \$children/, label => 'has field $children' },
        { pattern => qr/method emit/, label => 'has method emit' },
    ],
    original_ns => 'Chalk::Bootstrap::BNF::Target::XS::AST::CompositeNode',
    test_ns     => 'Chalk::Bootstrap::BNF::Target::XS::AST::CompositeNodeGenD',
    behavioral  => sub ($mod) {
        my $node = $mod->new(children => []);
        ok(defined $node, 'CompositeNode can be constructed');
        is(ref($node->children()), 'ARRAY', 'children returns arrayref');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/BNF/Target/XS/AST/VarDecl.pm',
    label       => 'XS::AST::VarDecl.pm',
    structural  => [
        { pattern => qr/field \$type/, label => 'has field $type' },
        { pattern => qr/field \$name/, label => 'has field $name' },
        { pattern => qr/method emit/, label => 'has method emit' },
    ],
    original_ns => 'Chalk::Bootstrap::BNF::Target::XS::AST::VarDecl',
    test_ns     => 'Chalk::Bootstrap::BNF::Target::XS::AST::VarDeclGenD',
    behavioral  => sub ($mod) {
        my $decl = $mod->new(type => 'SV *', name => 'result');
        is($decl->type(), 'SV *', 'type reader');
        is($decl->name(), 'result', 'name reader');
        like($decl->emit(), qr/SV \*result/, 'emit produces C declaration');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/BNF/Target/XS/AST/Preamble.pm',
    label       => 'XS::AST::Preamble.pm',
    structural  => [
        { pattern => qr/method emit/, label => 'has method emit' },
    ],
    original_ns => 'Chalk::Bootstrap::BNF::Target::XS::AST::Preamble',
    test_ns     => 'Chalk::Bootstrap::BNF::Target::XS::AST::PreambleGenD',
    behavioral  => sub ($mod) {
        my $preamble = $mod->new();
        my $emitted = $preamble->emit();
        like($emitted, qr/PERL_NO_GET_CONTEXT/, 'emit includes PERL_NO_GET_CONTEXT');
        like($emitted, qr/#include "XSUB.h"/, 'emit includes XSUB.h');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/BNF/Target/XS/AST/XSUB.pm',
    label       => 'XS::AST::XSUB.pm',
    structural  => [
        { pattern => qr/field \$name/, label => 'has field $name' },
        { pattern => qr/field \$params/, label => 'has field $params' },
        { pattern => qr/method emit/, label => 'has method emit' },
    ],
    original_ns => 'Chalk::Bootstrap::BNF::Target::XS::AST::XSUB',
    test_ns     => 'Chalk::Bootstrap::BNF::Target::XS::AST::XSUBGenD',
    todo_eval   => 'XSUB.pm depends on parent class Node and VarDecl isa check',
    behavioral  => sub ($mod) {
        my $xsub = $mod->new(
            name => 'test_func',
            params => ['SV *self'],
            body => [],
        );
        is($xsub->name(), 'test_func', 'name reader');
        is($xsub->return_type(), 'SV *', 'return_type default');
    },
);

# ============================================================
# Code generation targets
# ============================================================

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/BNF/Target/Perl.pm',
    label       => 'Target::Perl.pm',
    structural  => [
        { pattern => qr/method generate/, label => 'has method generate' },
    ],
    original_ns => 'Chalk::Bootstrap::BNF::Target::Perl',
    test_ns     => 'Chalk::Bootstrap::BNF::Target::PerlGenD',
    todo_eval   => 'Target::Perl depends on IR node types',
    behavioral  => sub ($mod) {
        my $target = $mod->new();
        ok(defined $target, 'Target::Perl can be constructed');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/Perl/Target/Perl.pm',
    label       => 'Perl::Target::Perl.pm',
    structural  => [
        { pattern => qr/method generate/, label => 'has method generate' },
    ],
    original_ns => 'Chalk::Bootstrap::Perl::Target::Perl',
    test_ns     => 'Chalk::Bootstrap::Perl::Target::PerlGenD',
    todo_eval   => 'Grammar fragmentation: complex string interpolation patterns',
    behavioral  => sub ($mod) {
        my $target = $mod->new();
        ok(defined $target, 'Perl::Target::Perl can be constructed');
    },
);

# ============================================================
# Actions / pipeline modules
# ============================================================

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Perl/Actions.pm',
    label      => 'Perl::Actions.pm',
    todo_parse => 'Perl::Actions.pm parse fails (complex anonymous sub/hash patterns)',
    structural => [
        { pattern => qr/Perl::Actions/, label => 'contains Perl::Actions' },
    ],
);

test_perl_file(
    file        => 'lib/Chalk/Bootstrap/ConciseTree/Actions.pm',
    label       => 'ConciseTree::Actions.pm',
    structural  => [
        { pattern => qr/Actions/, label => 'contains Actions class' },
        { pattern => qr/method/, label => 'has method definitions' },
    ],
    original_ns => 'Chalk::Bootstrap::ConciseTree::Actions',
    test_ns     => 'Chalk::Bootstrap::ConciseTree::ActionsGenD',
    todo_parse  => 'ConciseTree::Actions.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'Actions depends on ConciseOp/ConciseTree and uses complex patterns',
    behavioral  => sub ($mod) {
        my $actions = $mod->new();
        ok(defined $actions, 'ConciseTree::Actions can be constructed');
    },
);

test_perl_file(
    file             => 'lib/Chalk/Bootstrap/Desugar.pm',
    label            => 'Desugar.pm',
    structural       => [
        { pattern => qr/Desugar/, label => 'contains Desugar' },
        { pattern => qr/desugar_grammar/, label => 'has desugar_grammar' },
    ],
    original_ns      => 'Chalk::Bootstrap::Desugar',
    test_ns          => 'Chalk::Bootstrap::DesugarGenD',
    todo_structural  => 'Desugar.pm IR codegen omits desugar_grammar function',
    todo_eval        => 'Desugar depends on Grammar::Rule/Symbol classes',
    behavioral  => sub ($mod) {
        ok(defined $mod->can('desugar_grammar'), 'desugar_grammar is available');
    },
);

# ============================================================
# Grammar BNF modules
# ============================================================

test_perl_file(
    file        => 'lib/Chalk/Grammar/BNF.pm',
    label       => 'Grammar::BNF.pm',
    structural  => [
        { pattern => qr/BNF/, label => 'contains BNF' },
    ],
    original_ns => 'Chalk::Grammar::BNF',
    test_ns     => 'Chalk::Grammar::BNFGenD',
    todo_parse  => 'Grammar::BNF.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'BNF depends on Rule/Symbol classes',
    behavioral  => sub ($mod) {
        my $bnf = $mod->new();
        ok(defined $bnf, 'BNF can be constructed');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Grammar/BNF/Generated.pm',
    label       => 'Grammar::BNF::Generated.pm',
    structural  => [
        { pattern => qr/Generated/, label => 'contains Generated' },
        { pattern => qr/grammar/, label => 'has grammar function' },
    ],
    original_ns => 'Chalk::Grammar::BNF::Generated',
    test_ns     => 'Chalk::Grammar::BNF::GeneratedGenD',
    todo_parse  => 'Grammar::BNF::Generated.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'Generated.pm depends on Symbol/Rule/BNF classes',
);

test_perl_file(
    file        => 'lib/Chalk/Grammar/BNF/Actions.pm',
    label       => 'Grammar::BNF::Actions.pm',
    structural  => [
        { pattern => qr/Actions/, label => 'contains Actions' },
    ],
    original_ns => 'Chalk::Grammar::BNF::Actions',
    test_ns     => 'Chalk::Grammar::BNF::ActionsGenD',
    todo_parse  => 'Grammar::BNF::Actions.pm parse fails (Unknown Constructor class: SubDecl)',
    todo_eval   => 'BNF::Actions depends on Symbol/Rule constructors',
    behavioral  => sub ($mod) {
        my $actions = $mod->new();
        ok(defined $actions, 'BNF::Actions can be constructed');
    },
);

test_perl_file(
    file        => 'lib/Chalk/Grammar/Chalk/Rule/ExpressionList.pm',
    label       => 'Grammar::Chalk::Rule::ExpressionList.pm',
    structural  => [
        { pattern => qr/ExpressionList/, label => 'contains ExpressionList' },
    ],
    original_ns => 'Chalk::Grammar::Chalk::Rule::ExpressionList',
    test_ns     => 'Chalk::Grammar::Chalk::Rule::ExpressionListGenD',
    todo_eval   => 'ExpressionList depends on Rule parent class',
);

# ============================================================
# Expected parse failures
# ============================================================

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/Earley.pm',
    label      => 'Earley.pm',
);

test_perl_file(
    file       => 'lib/Chalk/Bootstrap/BNF/Target/XS.pm',
    label      => 'Target::XS.pm (expected parse failure)',
    todo_parse => 'Target::XS.pm has pre-existing parse failure',
);

done_testing();

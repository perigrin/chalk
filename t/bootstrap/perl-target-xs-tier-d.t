# ABOUTME: Tests Perl IR to XS compilation for Tier D files.
# ABOUTME: Compiles generated XS, loads module, and validates behavioral equivalence for 31 uncovered files.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

# === Skip guards ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load fork_test);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSTierDTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# ============================================================
# Helper: structural + behavioral test for a file
# ============================================================

my sub test_file(%args) {
    my $file   = $args{file};
    my $label  = $args{label};
    my $module = $args{module};
    my $structural_checks = $args{structural} // [];
    my $behavioral = $args{behavioral};
    my $skip_build = $args{skip_build};
    my $todo_parse = $args{todo_parse};

    subtest "$label" => sub {
        my $ir;
        if ($todo_parse) {
            $ir = eval { parse_file_ir($gen_grammar, $file) };
            TODO: {
                local $TODO = $todo_parse;
                ok(defined $ir, 'parse produces IR');
            }
            return unless defined $ir;
        } else {
            $ir = eval { parse_file_ir($gen_grammar, $file) };
            if ($@) {
                diag "parse_file_ir died: $@";
                ok(false, 'parse produces IR');
                return;
            }
            ok(defined $ir, 'parse produces IR') or return;
        }

        my ($dist, $err) = eval { build_and_load($ir, $module) };
        if ($@) {
            $err //= "build_and_load died: $@";
            $dist = undef;
        }

        if ($skip_build) {
            TODO: {
                local $TODO = $skip_build;
                ok(defined $dist, 'XS builds') or do {
                    diag $err if $err;
                    return;
                };
            }
            return unless defined $dist;
        } else {
            ok(defined $dist, 'XS builds') or do {
                diag $err if $err;
                return;
            };
        }

        # Structural checks on XS source
        my ($xs_file) = grep { /\.xs$/ } keys $dist->%*;
        if ($xs_file) {
            my $xs_code = $dist->{$xs_file};
            like($xs_code, qr/MODULE\s*=/, 'XS has MODULE line');
            for my $check ($structural_checks->@*) {
                like($xs_code, $check->{pattern}, $check->{label});
            }
        }

        # Behavioral tests (fork-safe)
        if ($behavioral && defined $dist) {
            $behavioral->($module);
        }
    };
}

# ============================================================
# Data model classes
# ============================================================

test_file(
    file   => 'lib/Chalk/Grammar/Symbol.pm',
    label  => 'Symbol.pm',
    module => 'Chalk::Grammar::XS::TierD::Symbol',
    structural => [
        { pattern => qr/type\(self/, label => 'has type reader' },
        { pattern => qr/value\(self/, label => 'has value reader' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $sym = $m->new(type => 'terminal', value => '/foo/');
            die "type != terminal" unless $sym->type() eq 'terminal';
            die "value != /foo/" unless $sym->value() eq '/foo/';
        }, 'field readers');
    },
);

test_file(
    file   => 'lib/Chalk/Grammar/Rule.pm',
    label  => 'Rule.pm',
    module => 'Chalk::Grammar::XS::TierD::Rule',
    structural => [
        { pattern => qr/name\(self/, label => 'has name reader' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            use Chalk::Grammar::Symbol;
            my $sym = Chalk::Grammar::Symbol->new(type => 'terminal', value => '/x/');
            my $rule = $m->new(name => 'Test', expressions => [[$sym]]);
            die "name != Test" unless $rule->name() eq 'Test';
        }, 'name reader');
    },
);

test_file(
    file   => 'lib/Chalk/Bootstrap/Terminal.pm',
    label  => 'Terminal.pm',
    module => 'Chalk::Bootstrap::XS::TierD::Terminal',
);

test_file(
    file   => 'lib/Chalk/Bootstrap/IR/Node.pm',
    label  => 'IR::Node.pm',
    module => 'Chalk::Bootstrap::XS::TierD::IRNode',
    structural => [
        { pattern => qr/id\(self/, label => 'has id reader' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $node = $m->new(id => 'test_1');
            die "id != test_1" unless $node->id() eq 'test_1';
        }, 'id reader');
    },
);

test_file(
    file       => 'lib/Chalk/Bootstrap/IR/NodeFactory.pm',
    label      => 'IR::NodeFactory.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::NodeFactory',
    skip_build => 'XS target generator dies: Constructor node missing value method',
);

test_file(
    file   => 'lib/Chalk/Bootstrap/Optimizer/DCE.pm',
    label  => 'Optimizer::DCE.pm',
    module => 'Chalk::Bootstrap::XS::TierD::DCE',
    structural => [
        { pattern => qr/name\(self/, label => 'has name method' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $dce = $m->new();
            die "name != DCE" unless $dce->name() eq 'DCE';
        }, 'name method');
    },
);

test_file(
    file   => 'lib/Chalk/Bootstrap/Optimizer.pm',
    label  => 'Optimizer.pm',
    module => 'Chalk::Bootstrap::XS::TierD::Optimizer',
    structural => [
        { pattern => qr/pass_count\(self/, label => 'has pass_count method' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $opt = $m->new();
            die "pass_count != 0" unless $opt->pass_count() == 0;
        }, 'pass_count');
    },
);

# ============================================================
# Semiring classes
# ============================================================

test_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/Boolean.pm',
    label      => 'Semiring::Boolean.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::Boolean',
    skip_build => 'XS emitter: RETVAL/xsreturn label issues in early-return codegen',
    structural => [
        { pattern => qr/zero\(self/, label => 'has zero method' },
        { pattern => qr/one\(self/, label => 'has one method' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $bool = $m->new();
            die "zero undefined" unless defined $bool->zero();
            die "one not truthy" unless $bool->one();
        }, 'zero/one');
    },
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/Structural.pm',
    label      => 'Semiring::Structural.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::Structural',
    skip_build => 'XS emitter: RETVAL/xsreturn label issues in early-return codegen',
    structural => [
        { pattern => qr/zero\(self/, label => 'has zero method' },
        { pattern => qr/one\(self/, label => 'has one method' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $s = $m->new();
            die "zero != 0" unless $s->zero() == 0;
            die "one != 1" unless $s->one() == 1;
        }, 'zero/one');
    },
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/Precedence.pm',
    label      => 'Semiring::Precedence.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::Precedence',
    skip_build => 'XS emitter: RETVAL/xsreturn label issues in early-return codegen',
    structural => [
        { pattern => qr/zero\(self/, label => 'has zero method' },
        { pattern => qr/one\(self/, label => 'has one method' },
    ],
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm',
    label      => 'Semiring::SemanticAction.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::SemanticAction',
    skip_build => 'XS emitter: RETVAL/xsreturn label issues in early-return codegen',
    structural => [
        { pattern => qr/zero\(self/, label => 'has zero method' },
        { pattern => qr/one\(self/, label => 'has one method' },
    ],
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/TypeInference.pm',
    label      => 'Semiring::TypeInference.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::TypeInference',
    skip_build => 'XS emitter: RETVAL/xsreturn label issues in early-return codegen',
    structural => [
        { pattern => qr/zero\(self/, label => 'has zero method' },
        { pattern => qr/one\(self/, label => 'has one method' },
    ],
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm',
    label      => 'Semiring::TypeInferenceActions.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::TypeInferenceActions',
    structural => [
        { pattern => qr/TypeInferenceActions/, label => 'has TypeInferenceActions class' },
    ],
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm',
    label      => 'Semiring::FilterComposite.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::FilterComposite',
    structural => [
        { pattern => qr/zero\(self/, label => 'has zero method' },
        { pattern => qr/one\(self/, label => 'has one method' },
    ],
);

# ============================================================
# Static/utility modules
# ============================================================

test_file(
    file   => 'lib/Chalk/Grammar/Perl/KeywordTable.pm',
    label  => 'KeywordTable.pm',
    module => 'Chalk::Grammar::XS::TierD::KeywordTable',
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $obj = $m->new();
            die "module not loaded" unless defined $obj;
        }, 'construction');
    },
);

test_file(
    file   => 'lib/Chalk/Grammar/Perl/PrecedenceTable.pm',
    label  => 'PrecedenceTable.pm',
    module => 'Chalk::Grammar::XS::TierD::PrecedenceTable',
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $obj = $m->new();
            die "module not loaded" unless defined $obj;
        }, 'construction');
    },
);

test_file(
    file   => 'lib/Chalk/Grammar/Perl/TypeLibrary.pm',
    label  => 'TypeLibrary.pm',
    module => 'Chalk::Grammar::XS::TierD::TypeLibrary',
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $obj = $m->new();
            die "module not loaded" unless defined $obj;
        }, 'construction');
    },
);

# ============================================================
# XS AST classes
# ============================================================

test_file(
    file   => 'lib/Chalk/Bootstrap/Target/XS/AST/CompositeNode.pm',
    label  => 'XS::AST::CompositeNode.pm',
    module => 'Chalk::Bootstrap::XS::TierD::CompositeNode',
    structural => [
        { pattern => qr/emit\(self/, label => 'has emit method' },
    ],
);

test_file(
    file   => 'lib/Chalk/Bootstrap/Target/XS/AST/VarDecl.pm',
    label  => 'XS::AST::VarDecl.pm',
    module => 'Chalk::Bootstrap::XS::TierD::VarDecl',
    structural => [
        { pattern => qr/emit\(self/, label => 'has emit method' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $decl = $m->new(type => 'SV *', name => 'result');
            die "type != SV *" unless $decl->type() eq 'SV *';
            die "name != result" unless $decl->name() eq 'result';
        }, 'field readers');
    },
);

test_file(
    file   => 'lib/Chalk/Bootstrap/Target/XS/AST/Preamble.pm',
    label  => 'XS::AST::Preamble.pm',
    module => 'Chalk::Bootstrap::XS::TierD::Preamble',
    structural => [
        { pattern => qr/emit\(self/, label => 'has emit method' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $preamble = $m->new();
            die "no PERL_NO_GET_CONTEXT" unless $preamble->emit() =~ /PERL_NO_GET_CONTEXT/;
        }, 'emit preamble');
    },
);

test_file(
    file   => 'lib/Chalk/Bootstrap/Target/XS/AST/XSUB.pm',
    label  => 'XS::AST::XSUB.pm',
    module => 'Chalk::Bootstrap::XS::TierD::XSUB',
    structural => [
        { pattern => qr/emit\(self/, label => 'has emit method' },
    ],
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $xsub = $m->new(
                name => 'test_func',
                params => ['SV *self'],
                return_type => 'SV *',
                body => [],
            );
            die "name != test_func" unless $xsub->name() eq 'test_func';
            die "return_type != SV *" unless $xsub->return_type() eq 'SV *';
        }, 'field readers');
    },
);

# ============================================================
# Code generation targets
# ============================================================

test_file(
    file   => 'lib/Chalk/Bootstrap/Target/Perl.pm',
    label  => 'Target::Perl.pm',
    module => 'Chalk::Bootstrap::XS::TierD::TargetPerl',
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Perl/Target/Perl.pm',
    label      => 'Perl::Target::Perl.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::PerlTargetPerl',
    skip_build => 'XS target generator dies: Constructor node missing value method',
    structural => [
        { pattern => qr/generate\(self/, label => 'has generate method' },
    ],
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Perl/Target/XS.pm',
    label      => 'Perl::Target::XS.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::PerlTargetXS',
    skip_build => 'XS emitter: av_push void value, type mismatch, early-return codegen issues',
    structural => [
        { pattern => qr/generate\(self/, label => 'has generate method' },
    ],
);

# ============================================================
# Actions / pipeline modules
# ============================================================

test_file(
    file       => 'lib/Chalk/Bootstrap/Perl/Actions.pm',
    label      => 'Perl::Actions.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::PerlActions',
    todo_parse => 'Perl::Actions.pm parse fails (complex anonymous sub/hash patterns)',
);

test_file(
    file       => 'lib/Chalk/Bootstrap/ConciseTree/Actions.pm',
    label      => 'ConciseTree::Actions.pm',
    module     => 'Chalk::Bootstrap::XS::TierD::ConciseTreeActions',
    skip_build => 'XS emitter: AV*/SV* type mismatch, RETVAL/xsreturn issues',
    structural => [
        { pattern => qr/ConciseTreeActions|Actions/, label => 'has Actions class' },
    ],
);

test_file(
    file   => 'lib/Chalk/Bootstrap/Desugar.pm',
    label  => 'Desugar.pm',
    module => 'Chalk::Bootstrap::XS::TierD::Desugar',
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            die "module not loaded" unless defined $m;
        }, 'module loads');
    },
);

# ============================================================
# Grammar BNF modules
# ============================================================

test_file(
    file   => 'lib/Chalk/Grammar/BNF.pm',
    label  => 'Grammar::BNF.pm',
    module => 'Chalk::Grammar::XS::TierD::BNF',
    behavioral => sub ($mod) {
        fork_test($mod, sub ($m) {
            my $bnf = $m->new();
            die "not constructed" unless defined $bnf;
        }, 'construction');
    },
);

test_file(
    file   => 'lib/Chalk/Grammar/BNF/Generated.pm',
    label  => 'Grammar::BNF::Generated.pm',
    module => 'Chalk::Grammar::XS::TierD::BNFGenerated',
);

test_file(
    file       => 'lib/Chalk/Grammar/BNF/Actions.pm',
    label      => 'Grammar::BNF::Actions.pm',
    module     => 'Chalk::Grammar::XS::TierD::BNFActions',
    skip_build => 'XS emitter: xsreturn label issues in early-return codegen',
    structural => [
        { pattern => qr/Actions/, label => 'has Actions class' },
    ],
);

test_file(
    file       => 'lib/Chalk/Grammar/Chalk/Rule/ExpressionList.pm',
    label      => 'Grammar::Chalk::Rule::ExpressionList.pm',
    module     => 'Chalk::Grammar::XS::TierD::ExpressionList',
    skip_build => 'XS emitter: av_push void value, NULL unsupported op',
    structural => [
        { pattern => qr/ExpressionList/, label => 'has ExpressionList class' },
    ],
);

# ============================================================
# Expected parse failures
# ============================================================

test_file(
    file       => 'lib/Chalk/Bootstrap/Earley.pm',
    label      => 'Earley.pm (expected parse failure)',
    module     => 'Chalk::Bootstrap::XS::TierD::Earley',
    todo_parse => 'Earley.pm uses try/catch which is not in grammar yet',
);

test_file(
    file       => 'lib/Chalk/Bootstrap/Target/XS.pm',
    label      => 'Target::XS.pm (expected parse failure)',
    module     => 'Chalk::Bootstrap::XS::TierD::TargetXS',
    todo_parse => 'Target::XS.pm has pre-existing parse failure',
    skip_build => 'XS target generator dies: Constructor node missing value method',
);

done_testing();

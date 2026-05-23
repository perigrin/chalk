# ABOUTME: Tests Perl IR to Perl source code emission for Tier B files.
# ABOUTME: Validates generated Perl compiles, evals, and behaves equivalently.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;
use Chalk::Bootstrap::Perl::Target::Perl;

# Build Perl grammar pipeline
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TargetPerlTierBTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::TargetPerlTierBTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper ===

my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();

my sub parse_and_generate($file) {
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();
    my $mop = Chalk::Bootstrap::Semiring::SemanticAction::current_mop();
    my $result = $parser->parse_value($source);
    return undef unless defined $result && !$result->is_zero();
    return undef unless defined $mop;

    my $out = $perl_target->generate($mop);
    return undef unless ref($out) eq 'HASH';
    my @values = values $out->%*;
    return $values[0];
}

# ============================================================
# 1. Constant.pm — 2 fields (:param :reader), method
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/IR/Node/Constant.pm');
    ok(defined $code, 'Constant.pm: generated Perl code');

    SKIP: {
        skip 'Constant.pm: no code generated', 8 unless defined $code;

        like($code, qr/field \$const_type/, 'Constant.pm: has field $const_type');
        like($code, qr/field \$value/, 'Constant.pm: has field $value');
        like($code, qr/:param/, 'Constant.pm: has :param attribute');
        like($code, qr/:reader/, 'Constant.pm: has :reader attribute');

        # Rename and eval
        my $renamed = $code;
        $renamed =~ s/Chalk::IR::Node::Constant\b/Chalk::IR::Node::ConstantGenerated/g;
        $renamed =~ s/Chalk::IR::Node\b(?!::)/Chalk::IR::Node/g;
        eval $renamed;
        is($@, '', 'Constant.pm: generated code evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'Constant.pm: eval failed', 3 if $@;
            my $obj = Chalk::IR::Node::ConstantGenerated->new(
                id => 'test', inputs => [],
                const_type => 'string', value => 'hello',
            );
            is($obj->const_type(), 'string', 'Constant.pm: const_type reader works');
            is($obj->value(), 'hello', 'Constant.pm: value reader works');
            is($obj->operation(), 'Constant', 'Constant.pm: operation() returns Constant');
        }
    }
}

# ============================================================
# 2. XS::AST::Node.pm — no fields, method with die
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/BNF/Target/XS/AST/Node.pm');
    ok(defined $code, 'XS::AST::Node.pm: generated Perl code');

    SKIP: {
        skip 'XS::AST::Node.pm: no code generated', 3 unless defined $code;

        my $renamed = $code;
        $renamed =~ s/Chalk::Bootstrap::BNF::Target::XS::AST::Node\b/Chalk::Bootstrap::BNF::Target::XS::AST::NodeGenerated/g;
        eval $renamed;
        is($@, '', 'XS::AST::Node.pm: evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'XS::AST::Node.pm: eval failed', 1 if $@;
            my $obj = Chalk::Bootstrap::BNF::Target::XS::AST::NodeGenerated->new();
            eval { $obj->emit() };
            like($@, qr/Subclass must implement emit/,
                'XS::AST::Node.pm: emit() dies with expected message');
        }
    }
}

# ============================================================
# 3. XS::AST::Statement.pm — 1 field, method with interpolation
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/BNF/Target/XS/AST/Statement.pm');
    ok(defined $code, 'Statement.pm: generated Perl code');

    SKIP: {
        skip 'Statement.pm: no code generated', 5 unless defined $code;

        like($code, qr/field \$code/, 'Statement.pm: has field $code');

        my $renamed = $code;
        $renamed =~ s/Chalk::Bootstrap::BNF::Target::XS::AST::Statement\b/Chalk::Bootstrap::BNF::Target::XS::AST::StatementGenerated/g;
        $renamed =~ s/Chalk::Bootstrap::BNF::Target::XS::AST::Node\b(?!Generated)/Chalk::Bootstrap::BNF::Target::XS::AST::Node/g;
        eval $renamed;
        is($@, '', 'Statement.pm: evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'Statement.pm: eval failed', 2 if $@;
            my $obj = Chalk::Bootstrap::BNF::Target::XS::AST::StatementGenerated->new(
                code => 'RETVAL = sv;',
            );
            is($obj->code(), 'RETVAL = sv;', 'Statement.pm: code reader works');
            is($obj->emit(), "    RETVAL = sv;\n",
                'Statement.pm: emit() returns interpolated string');
        }
    }
}

# ============================================================
# 4. XS::AST::Module.pm — 2 fields, method with 2-var interpolation
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/BNF/Target/XS/AST/Module.pm');
    ok(defined $code, 'Module.pm: generated Perl code');

    SKIP: {
        skip 'Module.pm: no code generated', 5 unless defined $code;

        like($code, qr/field \$module/, 'Module.pm: has field $module');
        like($code, qr/field \$package/, 'Module.pm: has field $package');

        my $renamed = $code;
        $renamed =~ s/Chalk::Bootstrap::BNF::Target::XS::AST::Module\b/Chalk::Bootstrap::BNF::Target::XS::AST::ModuleGenerated/g;
        $renamed =~ s/Chalk::Bootstrap::BNF::Target::XS::AST::Node\b(?!Generated)/Chalk::Bootstrap::BNF::Target::XS::AST::Node/g;
        eval $renamed;
        is($@, '', 'Module.pm: evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'Module.pm: eval failed', 2 if $@;
            my $obj = Chalk::Bootstrap::BNF::Target::XS::AST::ModuleGenerated->new(
                module => 'Foo::Bar', package => 'Foo::Bar',
            );
            is($obj->module(), 'Foo::Bar', 'Module.pm: module reader works');
            is($obj->emit(), "MODULE = Foo::Bar  PACKAGE = Foo::Bar\n\n",
                'Module.pm: emit() returns correctly interpolated string');
        }
    }
}

# NOTE: The Constructor.pm test block was removed when the polymorphic
# IR migration deleted Chalk::IR::Node::Constructor. The Constructor
# type no longer exists in the tree.

done_testing();

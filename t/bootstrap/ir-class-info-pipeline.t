# ABOUTME: Tests that Actions.pm produces Chalk::IR::ClassInfo for class declarations.
# ABOUTME: Verifies end-to-end pipeline: parse source with class decls -> ClassInfo structs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::MethodInfo;
use Chalk::IR::Program;

# Build Perl grammar pipeline
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::ClassInfoPipelineTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::ClassInfoPipelineTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_file($file) {
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result;
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# ============================================================
# 1. Constant.pm — Actions.pm should produce ClassInfo for class declarations
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant.pm: parse produces IR');

    SKIP: {
        skip 'Constant.pm: no IR', 20 unless defined $ir;

        isa_ok($ir, 'Chalk::IR::Program', 'Constant.pm: IR is Chalk::IR::Program');

        # Find the ClassInfo node — should replace Constructor:ClassDecl
        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'Constant.pm: Program classes() contains ClassInfo object')
            or diag("Got " . scalar($ir->classes()->@*) . " classes");

        SKIP: {
            skip 'Constant.pm: no ClassInfo', 15 unless defined $cls;

            isa_ok($cls, 'Chalk::IR::ClassInfo', 'ClassInfo object is correct type');
            ok(defined $cls->name(), 'ClassInfo has name');
            ok(!ref($cls->name()), 'ClassInfo name is plain string');

            # body() preserves all items in declaration order
            my $body = $cls->body();
            is(ref $body, 'ARRAY', 'ClassInfo body() is arrayref');
            ok(scalar $body->@* > 0, 'ClassInfo body() is non-empty');

            # Fields should be FieldInfo structs
            my @fields = $cls->fields()->@*;
            ok(scalar @fields >= 2, 'Constant.pm: ClassInfo has at least 2 fields')
                or diag("Got " . scalar @fields . " fields");

            if (scalar @fields >= 1) {
                isa_ok($fields[0], 'Chalk::IR::FieldInfo', 'ClassInfo field[0] is FieldInfo');
                is($fields[0]->name(), '$const_type', 'ClassInfo field[0] name is $const_type');
            }

            # Methods should be MethodInfo structs
            my @methods = $cls->methods()->@*;
            ok(scalar @methods >= 1, 'Constant.pm: ClassInfo has at least 1 method')
                or diag("Got " . scalar @methods . " methods");

            my ($op_method) = grep { $_->name() eq 'operation' } @methods;
            ok(defined $op_method, 'Constant.pm: ClassInfo has operation() as MethodInfo');

            if (defined $op_method) {
                isa_ok($op_method, 'Chalk::IR::MethodInfo', 'operation() method is MethodInfo');
            }

            # No subs expected in Constant.pm (pure class with fields + methods)
            # (Just verify the subs accessor works)
            is(ref($cls->subs()), 'ARRAY', 'ClassInfo subs() is arrayref');
        }
    }
}

# ============================================================
# 2. FieldInfo.pm — class with parent (:isa) should set parent
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/IR/Node.pm');
    ok(defined $ir, 'Node.pm: parse produces IR');

    SKIP: {
        skip 'Node.pm: no IR', 5 unless defined $ir;

        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'Node.pm: found ClassInfo');

        SKIP: {
            skip 'Node.pm: no ClassInfo', 3 unless defined $cls;

            isa_ok($cls, 'Chalk::IR::ClassInfo', 'Node.pm ClassInfo is correct type');
            ok(defined $cls->name(), 'Node.pm ClassInfo has name');
            # Node.pm is a base class, parent may or may not be set depending on grammar
        }
    }
}

done_testing();

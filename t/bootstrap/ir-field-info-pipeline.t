# ABOUTME: Tests that Actions.pm produces Chalk::IR::FieldInfo for field declarations.
# ABOUTME: Verifies end-to-end pipeline: parse source with field decls -> FieldInfo structs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::ClassInfo;
use Chalk::IR::FieldInfo;
use Chalk::IR::Program;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::FieldInfoPipelineTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::FieldInfoPipelineTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_file($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
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
# 1. Constant.pm — Actions.pm should produce FieldInfo for fields
# ============================================================

{
    my $ir = parse_file('lib/Chalk/Bootstrap/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant.pm: parse produces IR');

    SKIP: {
        skip 'Constant.pm: no IR', 20 unless defined $ir;

        isa_ok($ir, 'Chalk::IR::Program', 'Constant.pm: IR is Chalk::IR::Program');
        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'Constant.pm: found class declaration');

        SKIP: {
            skip 'Constant.pm: no class declaration', 15 unless defined $cls;

            my $body = $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
            is(ref $body, 'ARRAY', 'Constant.pm: body is arrayref');

            # Fields should now be Chalk::IR::FieldInfo, not Constructor:FieldDecl
            my @fields = grep { $_ isa Chalk::IR::FieldInfo } $body->@*;
            is(scalar @fields, 2, 'Constant.pm: body contains 2 FieldInfo objects');

            my $f1 = $fields[0];
            isa_ok($f1, 'Chalk::IR::FieldInfo', 'Constant.pm field 1 is FieldInfo');
            is($f1->name(), '$const_type', 'Constant.pm field 1 name is plain string');

            my $f1_attrs = $f1->attributes();
            is(ref $f1_attrs, 'ARRAY', 'Constant.pm field 1 attributes is arrayref');
            is(scalar $f1_attrs->@*, 2, 'Constant.pm field 1 has 2 attributes');

            # Attributes should be plain hashrefs {name => 'param'} etc.
            is($f1_attrs->[0]{name}, 'param',  'Constant.pm field 1 attr[0] is param');
            is($f1_attrs->[1]{name}, 'reader', 'Constant.pm field 1 attr[1] is reader');

            is($f1->default_value(), undef, 'Constant.pm field 1 has no default');

            my $f2 = $fields[1];
            isa_ok($f2, 'Chalk::IR::FieldInfo', 'Constant.pm field 2 is FieldInfo');
            is($f2->name(), '$value', 'Constant.pm field 2 name is plain string');
        }
    }
}

# ============================================================
# 2. Constant.pm — field with default value (via AssignmentExpression)
# ============================================================

{
    # ConciseOp.pm has fields with default values — verify FieldInfo stores them
    my $ir = parse_file('lib/Chalk/Bootstrap/ConciseOp.pm');
    ok(defined $ir, 'ConciseOp.pm: parse produces IR');

    SKIP: {
        skip 'ConciseOp.pm: no IR', 10 unless defined $ir;

        my ($cls) = $ir->classes()->@*;
        ok(defined $cls, 'ConciseOp.pm: found class declaration');

        SKIP: {
            skip 'ConciseOp.pm: no class declaration', 5 unless defined $cls;

            my $body = $cls isa Chalk::IR::ClassInfo ? $cls->body() : $cls->inputs()->[2];
            my @fields = grep { $_ isa Chalk::IR::FieldInfo } $body->@*;
            ok(scalar @fields >= 5, 'ConciseOp.pm: at least 5 FieldInfo objects')
                or diag("Got " . scalar @fields . " fields");

            # Find a field that has a default value
            my ($field_with_default) = grep { defined $_->default_value() } @fields;
            ok(defined $field_with_default,
                'ConciseOp.pm: at least one field has a default_value');
        }
    }
}

done_testing();

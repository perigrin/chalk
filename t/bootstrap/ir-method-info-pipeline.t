# ABOUTME: Tests that Actions.pm produces Chalk::IR::MethodInfo for method declarations.
# ABOUTME: Verifies end-to-end pipeline: parse source with methods -> MethodInfo structs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::MethodInfo;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::MethodInfoPipelineTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::MethodInfoPipelineTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

my sub parse_file($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $result = $parser->parse_value($source);
    return undef unless defined $result;

    my $sem_ctx = $result->[4];
    return undef unless defined $sem_ctx;
    return $sem_ctx->extract();
}

# ============================================================
# 1. Constant.pm — Actions.pm should produce MethodInfo for methods
# ============================================================

{
    my $ir = parse_file('lib/Chalk/IR/Node/Constant.pm');
    ok(defined $ir, 'Constant.pm: parse produces IR');

    SKIP: {
        skip 'Constant.pm: no IR', 20 unless defined $ir;

        my $stmts = $ir->inputs()->[0];
        my $cls;
        for my $stmt ($stmts->@*) {
            if ($stmt isa Chalk::Bootstrap::IR::Node::Constructor
                    && $stmt->class() eq 'ClassDecl') {
                $cls = $stmt;
            }
        }
        ok(defined $cls, 'Constant.pm: found ClassDecl');

        SKIP: {
            skip 'Constant.pm: no ClassDecl', 15 unless defined $cls;

            my $body = $cls->inputs()->[2];
            is(ref $body, 'ARRAY', 'Constant.pm: body is arrayref');

            # Methods should now be Chalk::IR::MethodInfo, not Constructor:MethodDecl
            my @methods = grep { $_ isa Chalk::IR::MethodInfo } $body->@*;
            ok(scalar @methods >= 2,
                'Constant.pm: body contains at least 2 MethodInfo objects')
                or diag("Got " . scalar @methods . " MethodInfo objects; body has "
                    . scalar($body->@*) . " items total");

            my ($op_method) = grep { $_->name() eq 'operation' } @methods;
            ok(defined $op_method, 'Constant.pm: found operation() method as MethodInfo');

            SKIP: {
                skip 'Constant.pm: no operation() method', 6 unless defined $op_method;

                isa_ok($op_method, 'Chalk::IR::MethodInfo', 'operation() is a MethodInfo');
                is($op_method->name(), 'operation', 'MethodInfo name is plain string');

                my $params = $op_method->params();
                is(ref $params, 'ARRAY', 'MethodInfo params is arrayref');
                ok(scalar $params->@* >= 0, 'MethodInfo params is valid arrayref');

                # Params should be plain strings, not Constant nodes
                if (scalar $params->@* > 0) {
                    ok(!ref($params->[0]), 'MethodInfo param[0] is a plain string');
                }

                my $body_stmts = $op_method->body();
                is(ref $body_stmts, 'ARRAY', 'MethodInfo body() is arrayref');
                ok(scalar $body_stmts->@* > 0, 'MethodInfo body() is non-empty');

                my $rt = $op_method->return_type();
                ok(defined $rt, 'MethodInfo return_type() is defined');
                ok(!ref($rt), 'MethodInfo return_type() is a plain string');
            }

            my ($ch_method) = grep { $_->name() eq 'content_hash' } @methods;
            ok(defined $ch_method, 'Constant.pm: found content_hash() method as MethodInfo');
        }
    }
}

done_testing();

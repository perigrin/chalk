# ABOUTME: Tests that Actions.pm produces Chalk::IR::SubInfo for sub declarations.
# ABOUTME: Verifies end-to-end pipeline: parse source with package subs -> SubInfo structs.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::IR::SubInfo;
use Chalk::IR::Program;

# Build Perl grammar pipeline
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::SubInfoPipelineTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::SubInfoPipelineTest::grammar();
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
# 1. Serialize/JSON.pm — Actions.pm should produce SubInfo for package subs
# ============================================================

{
    my $ir = parse_file('lib/Chalk/IR/Serialize/JSON.pm');
    ok(defined $ir, 'Serialize/JSON.pm: parse produces IR');

    SKIP: {
        skip 'Serialize/JSON.pm: no IR', 15 unless defined $ir;

        isa_ok($ir, 'Chalk::IR::Program', 'Serialize/JSON.pm: IR is Chalk::IR::Program');

        # Collect all top-level SubInfo nodes (package-level subs)
        my @subs = $ir->top_level_subs()->@*;
        ok(scalar @subs >= 2,
            'Serialize/JSON.pm: top_level_subs contains at least 2 SubInfo objects')
            or diag("Got " . scalar @subs . " SubInfo objects");

        # to_json and helper subs should be SubInfo
        my ($to_json_sub) = grep { $_->name() eq 'to_json' } @subs;
        ok(defined $to_json_sub, 'Serialize/JSON.pm: found to_json() as SubInfo');

        SKIP: {
            skip 'Serialize/JSON.pm: no to_json()', 8 unless defined $to_json_sub;

            isa_ok($to_json_sub, 'Chalk::IR::SubInfo', 'to_json() is a SubInfo');
            is($to_json_sub->name(), 'to_json', 'SubInfo name is plain string');

            my $params = $to_json_sub->params();
            is(ref $params, 'ARRAY', 'SubInfo params is arrayref');
            ok(scalar $params->@* >= 1, 'SubInfo params is non-empty');

            # Params should be plain strings, not Constant nodes
            ok(!ref($params->[0]), 'SubInfo param[0] is a plain string');

            my $scope = $to_json_sub->scope();
            is($scope, 'package', 'SubInfo scope is package for bare sub');

            my $body_stmts = $to_json_sub->body();
            is(ref $body_stmts, 'ARRAY', 'SubInfo body() is arrayref');
            ok(scalar $body_stmts->@* > 0, 'SubInfo body() is non-empty');
        }

        my ($other_sub) = grep { $_->name() ne 'to_json' } @subs;
        ok(defined $other_sub, 'Serialize/JSON.pm: found at least one other top-level sub');
    }
}

done_testing();

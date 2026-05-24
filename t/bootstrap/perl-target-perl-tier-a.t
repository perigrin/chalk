# ABOUTME: Tests Perl IR to Perl source code emission for Tier A files.
# ABOUTME: Validates generated Perl compiles, evals, and behaves equivalently.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;
use Chalk::Bootstrap::Semiring::SemanticAction;

# Build Perl grammar pipeline: IR -> generated grammar -> eval -> grammar objects
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TargetPerlTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::TargetPerlTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR -> generate Perl source ===

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
# 1. Start.pm — class :isa, method returning string
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/IR/Node/Start.pm');
    ok(defined $code, 'Start.pm: generated Perl code');

    SKIP: {
        skip 'Start.pm: no code generated', 5 unless defined $code;

        # Structural checks
        like($code, qr/use 5\.42\.0/, 'Start.pm: contains use 5.42.0');
        like($code, qr/class\b/, 'Start.pm: contains class keyword');
        like($code, qr/:isa\(Chalk::IR::Node\)/, 'Start.pm: has :isa');

        # Rename class to avoid collision, eval
        my $renamed = $code;
        $renamed =~ s/Chalk::IR::Node::Start/Chalk::IR::Node::StartGenerated/g;
        $renamed =~ s/Chalk::IR::Node\b(?!::)/Chalk::IR::Node/g;
        eval $renamed;
        is($@, '', 'Start.pm: generated code evals cleanly') or diag "Code:\n$renamed\nError: $@";

        # Behavioral equivalence
        SKIP: {
            skip 'Start.pm: eval failed', 1 if $@;
            my $obj = Chalk::IR::Node::StartGenerated->new(
                id => 'test', inputs => [],
            );
            is($obj->operation(), 'Start',
                'Start.pm: generated class operation() returns Start');
        }
    }
}

# ============================================================
# 2. Return.pm — class :isa, method returning string
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/IR/Node/Return.pm');
    ok(defined $code, 'Return.pm: generated Perl code');

    SKIP: {
        skip 'Return.pm: no code generated', 3 unless defined $code;

        my $renamed = $code;
        $renamed =~ s/Chalk::IR::Node::Return\b/Chalk::IR::Node::ReturnGenerated/g;
        eval $renamed;
        is($@, '', 'Return.pm: generated code evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'Return.pm: eval failed', 1 if $@;
            my $obj = Chalk::IR::Node::ReturnGenerated->new(
                id => 'test', inputs => [],
            );
            is($obj->operation(), 'Return',
                'Return.pm: generated class operation() returns Return');
        }
    }
}

# ============================================================
# 3. Target.pm — class, 2 methods with param, die
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/Target.pm');
    ok(defined $code, 'Target.pm: generated Perl code');

    SKIP: {
        skip 'Target.pm: no code generated', 4 unless defined $code;

        my $renamed = $code;
        $renamed =~ s/Chalk::Bootstrap::Target\b/Chalk::Bootstrap::TargetGenerated/g;
        eval $renamed;
        is($@, '', 'Target.pm: generated code evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'Target.pm: eval failed', 2 if $@;
            my $obj = Chalk::Bootstrap::TargetGenerated->new();
            eval { $obj->generate(undef) };
            like($@, qr/Subclass must implement generate/,
                'Target.pm: generate() dies with expected message');

            eval { $obj->generate_distribution(undef) };
            like($@, qr/Subclass must implement generate_distribution/,
                'Target.pm: generate_distribution() dies with expected message');
        }
    }
}

# ============================================================
# 4. Pass.pm — class, 2 methods (0/1 param), die
# ============================================================

{
    my $code = parse_and_generate('lib/Chalk/Bootstrap/Optimizer/Pass.pm');
    ok(defined $code, 'Pass.pm: generated Perl code');

    SKIP: {
        skip 'Pass.pm: no code generated', 4 unless defined $code;

        my $renamed = $code;
        $renamed =~ s/Chalk::Bootstrap::Optimizer::Pass\b/Chalk::Bootstrap::Optimizer::PassGenerated/g;
        eval $renamed;
        is($@, '', 'Pass.pm: generated code evals cleanly') or diag "Code:\n$renamed\nError: $@";

        SKIP: {
            skip 'Pass.pm: eval failed', 2 if $@;
            my $obj = Chalk::Bootstrap::Optimizer::PassGenerated->new();
            eval { $obj->name() };
            like($@, qr/Subclass must implement name/,
                'Pass.pm: name() dies with expected message');

            eval { $obj->run(undef) };
            like($@, qr/Subclass must implement run/,
                'Pass.pm: run() dies with expected message');
        }
    }
}

done_testing();

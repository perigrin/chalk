# ABOUTME: Tests determinism of Perl IR codegen across multiple hash seeds.
# ABOUTME: Verifies Target::Perl and Target::XS produce byte-identical output.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Build Perl grammar pipeline once (grammar is deterministic)
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::DeterminismTest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::DeterminismTest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse a file and extract Perl IR ===

my sub parse_file_ir($file) {
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    open my $fh, '<:utf8', $file or die "Cannot read $file: $!";
    local $/;
    my $source = <$fh>;

    my $parser = build_perl_ir_parser($gen_grammar, start => 'Program');
    my $semiring = $parser->semiring();
    $semiring->reset_cache();
    my $result = $parser->parse_value($source);
    return unless defined $result;

    my $sa = $semiring->semirings()->[4];
    my $sem_ctx = $result->[4];
    return unless defined $sem_ctx;
    my $ir = $sem_ctx->extract();
    return unless defined $ir;

    return ($ir, $sa, $sem_ctx);
}

# === Test files and their XS module names ===

my @test_files = (
    {
        file   => 'lib/Chalk/Bootstrap/IR/Node/Start.pm',
        module => 'Chalk::Bootstrap::Perl::XS::Det::Start',
        label  => 'Start',
    },
    {
        file   => 'lib/Chalk/Bootstrap/Target.pm',
        module => 'Chalk::Bootstrap::Perl::XS::Det::Target',
        label  => 'Target',
    },
);

my @seeds = (0, 1, 42, 12345, 99999);

for my $tc (@test_files) {
    my $label = $tc->{label};

    # Collect codegen output for each seed
    my @perl_outputs;
    my @xs_outputs;

    for my $seed (@seeds) {
        local $ENV{PERL_HASH_SEED} = $seed;
        local $ENV{PERL_PERTURB_KEYS} = 'NO';

        my ($ir, $sa, $sem_ctx) = parse_file_ir($tc->{file});
        unless (defined $ir) {
            fail("$label: seed $seed failed to parse");
            push @perl_outputs, undef;
            push @xs_outputs, undef;
            next;
        }

        # Perl target
        my $perl_target = Chalk::Bootstrap::Perl::Target::Perl->new();
        push @perl_outputs, $perl_target->generate_with_cfg($ir, $sa, $sem_ctx);

        # XS target
        my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
            module_name => $tc->{module},
        );
        my $dist = $xs_target->generate_distribution_with_cfg($ir, $sa, $sem_ctx);
        # Concatenate all files in sorted key order for comparison
        my $xs_concat = join("\n---\n",
            map { "$_\n" . $dist->{$_} } sort keys $dist->%*
        );
        push @xs_outputs, $xs_concat;
    }

    # Verify Perl output is identical across all seeds
    my $first_perl = $perl_outputs[0];
    ok(defined $first_perl, "$label: Perl codegen seed $seeds[0] produces output");
    for my $i (1 .. $#seeds) {
        is($perl_outputs[$i], $first_perl,
            "$label: Perl codegen identical for seed $seeds[$i]");
    }

    # Verify XS output is identical across all seeds
    my $first_xs = $xs_outputs[0];
    ok(defined $first_xs, "$label: XS codegen seed $seeds[0] produces output");
    for my $i (1 .. $#seeds) {
        is($xs_outputs[$i], $first_xs,
            "$label: XS codegen identical for seed $seeds[$i]");
    }
}

done_testing();

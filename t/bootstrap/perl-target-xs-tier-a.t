# ABOUTME: Tests Perl IR to XS compilation for Tier A files.
# ABOUTME: Compiles generated XS, loads module, and validates behavioral equivalence.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);

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

# === Setup ===

use TestPipeline qw(perl_pipeline build_perl_ir_parser);
use Chalk::Bootstrap::IR::NodeFactory;
use Chalk::Bootstrap::Target::Perl;
use Chalk::Bootstrap::Perl::Target::XS;

# Build Perl grammar pipeline
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $raw_ir = perl_pipeline();
ok(defined $raw_ir, 'perl_pipeline produces grammar IR');

my $bnf_target = Chalk::Bootstrap::Target::Perl->new();
my $generated = $bnf_target->generate($raw_ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::XSTierATest/g;
eval $generated;
is($@, '', 'generated grammar code evals cleanly') or BAIL_OUT("Cannot continue: $@");

my $gen_grammar = Chalk::Grammar::Perl::XSTierATest::grammar();
ok(defined $gen_grammar, 'grammar objects loaded');

# === Helper to parse file -> IR ===

my sub parse_file_ir($file) {
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

# === Test each Tier A file ===

my @test_cases = (
    {
        file        => 'lib/Chalk/Bootstrap/IR/Node/Start.pm',
        module      => 'Chalk::Bootstrap::Perl::XS::TierA::Start',
        label       => 'Start',
        methods     => [
            { name => 'operation', args => [], expected => 'Start' },
        ],
    },
    {
        file        => 'lib/Chalk/Bootstrap/IR/Node/Return.pm',
        module      => 'Chalk::Bootstrap::Perl::XS::TierA::Return',
        label       => 'Return',
        methods     => [
            { name => 'operation', args => [], expected => 'Return' },
        ],
    },
    {
        file        => 'lib/Chalk/Bootstrap/Target.pm',
        module      => 'Chalk::Bootstrap::Perl::XS::TierA::Target',
        label       => 'Target',
        methods     => [
            { name => 'generate', args => [undef], dies => qr/Subclass must implement generate/ },
            { name => 'generate_distribution', args => [undef], dies => qr/Subclass must implement generate_distribution/ },
        ],
    },
    {
        file        => 'lib/Chalk/Bootstrap/Optimizer/Pass.pm',
        module      => 'Chalk::Bootstrap::Perl::XS::TierA::Pass',
        label       => 'Pass',
        methods     => [
            { name => 'name', args => [], dies => qr/Subclass must implement name/ },
            { name => 'run', args => [undef], dies => qr/Subclass must implement run/ },
        ],
    },
);

for my $tc (@test_cases) {
    my $label = $tc->{label};
    my $ir = parse_file_ir($tc->{file});
    ok(defined $ir, "$label: parse produces IR");

    SKIP: {
        skip "$label: no IR", 10 unless defined $ir;

        my $xs_target = Chalk::Bootstrap::Perl::Target::XS->new(
            module_name => $tc->{module},
        );
        my $dist = $xs_target->generate_distribution($ir);
        is(ref($dist), 'HASH', "$label: generate_distribution returns hashref");
        cmp_ok(scalar keys $dist->%*, '>=', 3, "$label: distribution has >= 3 files");

        # Write to tempdir
        my $tmpdir = tempdir(CLEANUP => 1);
        for my $path (sort keys $dist->%*) {
            my $full_path = "$tmpdir/$path";
            my $dir = dirname($full_path);
            make_path($dir) unless -d $dir;
            open(my $fh, '>:encoding(UTF-8)', $full_path)
                or die "Cannot write $full_path: $!";
            print $fh $dist->{$path};
            close $fh;
        }

        # Build cycle
        my $build_output = `cd "$tmpdir" && "$^X" Build.PL 2>&1 && "$^X" Build 2>&1`;
        my $exit = $? >> 8;
        is($exit, 0, "$label: XS compiles successfully") or do {
            diag $build_output;
            # Dump generated XS for debugging
            for my $path (sort keys $dist->%*) {
                if ($path =~ /\.xs$/) {
                    diag "=== $path ===\n" . $dist->{$path};
                }
            }
            skip "$label: build failed", 5;
        };

        # Load module
        unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
        eval "require $tc->{module}";
        is($@, '', "$label: module loads") or do {
            diag $@;
            skip "$label: load failed", 4;
        };

        # Create instance and test methods
        my $obj = eval { $tc->{module}->new() };
        is($@, '', "$label: new() succeeds") or do {
            diag $@;
            skip "$label: new failed", 3;
        };

        for my $meth ($tc->{methods}->@*) {
            my $mname = $meth->{name};
            if (defined $meth->{expected}) {
                my $result = eval { $obj->$mname($meth->{args}->@*) };
                is($@, '', "$label: $mname() doesn't die");
                is($result, $meth->{expected},
                    "$label: $mname() returns '$meth->{expected}'");
            } elsif (defined $meth->{dies}) {
                eval { $obj->$mname($meth->{args}->@*) };
                like($@, $meth->{dies},
                    "$label: $mname() dies with expected message");
            }
        }
    }
}

done_testing();

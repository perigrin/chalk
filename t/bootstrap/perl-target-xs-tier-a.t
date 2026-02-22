# ABOUTME: Tests Perl IR to XS compilation for Tier A files.
# ABOUTME: Compiles generated XS, loads module, and validates behavioral equivalence.
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

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);

# Build Perl grammar pipeline
my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSTierATest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# === Test cases ===

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
    my $ir = parse_file_ir($gen_grammar, $tc->{file});
    ok(defined $ir, "$label: parse produces IR");

    SKIP: {
        skip "$label: no IR", 10 unless defined $ir;

        my $module = $tc->{module};
        my ($dist, $err) = build_and_load($ir, $module);
        ok(defined $dist, "$label: XS builds") or do {
            diag $err;
            skip "$label: build failed", 5;
        };

        # Create instance and test methods
        my $obj = eval { $module->new() };
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

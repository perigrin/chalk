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
        skip_behavioral => 'inherits from IR::Node with required params - XS wrapper param forwarding not yet implemented',
        methods     => [
            { name => 'operation', args => [], expected => 'Start' },
        ],
    },
    {
        file        => 'lib/Chalk/Bootstrap/IR/Node/Return.pm',
        module      => 'Chalk::Bootstrap::Perl::XS::TierA::Return',
        label       => 'Return',
        skip_behavioral => 'inherits from IR::Node with required params - XS wrapper param forwarding not yet implemented',
        methods     => [
            { name => 'operation', args => [], expected => 'Return' },
        ],
    },
    {
        file        => 'lib/Chalk/Bootstrap/Target.pm',
        module      => 'Chalk::Bootstrap::Perl::XS::TierA::Target',
        label       => 'Target',
        new_args    => {},
        methods     => [
            { name => 'generate', args => [undef], dies => qr/Subclass must implement generate/ },
            { name => 'generate_distribution', args => [undef], dies => qr/Subclass must implement generate_distribution/ },
        ],
    },
    {
        file        => 'lib/Chalk/Bootstrap/Optimizer/Pass.pm',
        module      => 'Chalk::Bootstrap::Perl::XS::TierA::Pass',
        label       => 'Pass',
        new_args    => {},
        methods     => [
            { name => 'name', args => [], dies => qr/Subclass must implement name/ },
            { name => 'run', args => [undef], dies => qr/Subclass must implement run/ },
        ],
    },
);

for my $tc (@test_cases) {
    my $label = $tc->{label};
    my ($ir, $sa, $sem_ctx) = parse_file_ir($gen_grammar, $tc->{file});
    ok(defined $ir, "$label: parse produces IR");

    SKIP: {
        skip "$label: no IR", 10 unless defined $ir;

        my $module = $tc->{module};
        my ($dist, $err) = build_and_load($ir, $sa, $sem_ctx, $module);
        ok(defined $dist, "$label: XS builds") or do {
            diag $err;
            skip "$label: build failed", 5;
        };

        # Create instance and test methods
        SKIP: {
            if (my $skip_reason = $tc->{skip_behavioral}) {
                skip "$label: $skip_reason", scalar($tc->{methods}->@*) * 2 + 1;
            }

            my $new_args = $tc->{new_args} // {};
            my $obj = eval { $module->new(%$new_args) };
            is($@, '', "$label: new() succeeds") or do {
                diag $@;
                skip "$label: new failed", scalar($tc->{methods}->@*) * 2;
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
}

done_testing();

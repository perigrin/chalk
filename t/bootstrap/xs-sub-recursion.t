# ABOUTME: Tests that __SUB__->() recursion in my sub compiles to direct C call.
# ABOUTME: Validates that generated C doesn't use call_sv(self) in static helpers.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';

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

my $gen_grammar = eval { setup_xs_grammar('Chalk::Grammar::Perl::SubRecTest') };
ok(defined $gen_grammar, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

# Parse TypeInferenceActions.pm which has __SUB__->() recursion in my sub helpers
my ($ir, $sa, $sem_ctx) = eval {
    parse_file_ir($gen_grammar, 'lib/Chalk/Bootstrap/Semiring/TypeInferenceActions.pm')
};
ok(defined $ir, 'TypeInferenceActions: parse produces IR') or BAIL_OUT("Cannot continue: $@");

# Build XS — this should not fail with 'self' undeclared
my $module = 'Chalk::Bootstrap::XS::Test::SubRecursion';
my ($dist, $err) = eval { build_and_load($ir, $sa, $sem_ctx, $module) };
if ($@) {
    $err //= "build_and_load died: $@";
    $dist = undef;
}

ok(defined $dist, 'TypeInferenceActions: XS builds') or do {
    diag $err if $err;
    # Check if the error mentions 'self' undeclared
    if (defined $err && $err =~ /self.*undeclared|undeclared.*self/) {
        diag "Root cause: __SUB__->() compiled as call_sv(self) in static helper";
    }
};

done_testing();

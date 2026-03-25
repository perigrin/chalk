# ABOUTME: Smoke test for Target::C-based build_and_load in TestXSHelpers.
# ABOUTME: Verifies the new C compilation path works for a simple class.
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

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);

# Parse Symbol.pm — simplest class
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSCSmokeTest') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Grammar/Symbol.pm') };
ok(defined $ir, 'Symbol.pm parses to IR') or BAIL_OUT("Parse failed: $@");

# Build and load via Target::C
my ($result, $err) = build_and_load($ir, $sa, $ctx, 'Test::XSCSmoke::Symbol');
if (!defined $result) {
    diag "Error: $err";
    BAIL_OUT("Build failed");
}
ok(defined $result, 'build_and_load succeeds');

# Exercise the class
my $sym = eval { Test::XSCSmoke::Symbol->new(type => 'terminal', value => 'foo') };
is($@, '', 'new() succeeds');
ok(defined $sym, 'object created');
is($sym->type(), 'terminal', 'type() reader');
is($sym->value(), 'foo', 'value() reader');

done_testing;

# ABOUTME: Runtime behavioral test for XS field access with feature class objects via Target::C.
# ABOUTME: Builds, loads, and exercises a simple class to verify ObjectFIELDS works.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempfile);

use lib 'lib';
use lib 't/bootstrap/lib';

# Skip guards
my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
unless ($have_compiler) {
    plan skip_all => 'No C compiler available';
}

use TestXSHelpers qw(setup_xs_grammar parse_file_ir build_and_load);

# --- Create a simple test class ---
my ($fh, $source_file) = tempfile(SUFFIX => '.pm', UNLINK => 1);
print $fh <<'PERL';
use 5.42.0;
use utf8;
no warnings 'experimental::class';

class TestFieldAccess {
    field $name :param :reader;
    field $value :param :reader;

    method double_value() {
        return $value + $value;
    }

    method greeting() {
        return "Hello, $name";
    }
}
PERL
close $fh;

# --- Parse to IR ---
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSFieldRuntime') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $source_file) };
ok(defined $ir, 'test class parses to IR') or BAIL_OUT("Parse failed: $@");

# --- Build and load XS module via Target::C ---
my ($result, $build_err) = eval { build_and_load($ir, $sa, $ctx, 'TestFieldAccess') };
ok(defined $result, 'XS module built and loaded') or BAIL_OUT("Build failed: " . ($build_err // $@));

# --- Exercise the class ---
my $obj = eval { TestFieldAccess->new(name => 'world', value => 21) };
is($@, '', 'new() succeeds') or BAIL_OUT("new() failed: $@");

ok(defined $obj, 'object created');

# :reader tests
is($obj->name(), 'world', ':reader returns correct name');
is($obj->value(), 21, ':reader returns correct value');

# method that reads fields
is($obj->double_value(), 42, 'method reads field and computes correctly');

# interpolated string method
is($obj->greeting(), 'Hello, world', 'interpolated string with field variable');

done_testing();

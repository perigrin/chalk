# ABOUTME: Runtime behavioral test for XS field access with feature class objects.
# ABOUTME: Builds, loads, and exercises a simple class to verify ObjectFIELDS works.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir tempfile);
use File::Path qw(make_path);
use File::Basename qw(dirname);

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

eval { require Module::Build; 1 }
    or plan skip_all => 'Module::Build not installed';

use Chalk::Bootstrap::Perl::Target::XS;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);

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

# --- Generate distribution ---
my $xs = Chalk::Bootstrap::Perl::Target::XS->new(module_name => 'Test::FieldAccess');
my $dist = eval { $xs->generate_distribution_with_cfg($ir, $sa, $ctx) };
ok(ref($dist) eq 'HASH', 'XS distribution generated') or BAIL_OUT("XS gen failed: $@");

# --- Write to temp directory ---
my $tmpdir = tempdir(CLEANUP => 1);

for my $path (sort keys $dist->%*) {
    my $full_path = "$tmpdir/$path";
    my $dir = dirname($full_path);
    make_path($dir) unless -d $dir;
    open(my $wfh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
    print $wfh $dist->{$path};
    close $wfh;
}

# --- Build ---
{
    my $output = `cd "$tmpdir" && "$^X" Build.PL 2>&1`;
    my $exit = $? >> 8;
    is($exit, 0, 'perl Build.PL exits cleanly') or BAIL_OUT("Build.PL failed: $output");
}

{
    my $output = `cd "$tmpdir" && "$^X" Build 2>&1`;
    my $exit = $? >> 8;
    is($exit, 0, './Build compiles XS') or BAIL_OUT("Build failed: $output");
}

# --- Load ---
unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";

eval { require Test::FieldAccess };
is($@, '', 'Test::FieldAccess loads without error') or BAIL_OUT("Load failed: $@");

# --- Exercise the class ---
my $obj = eval { Test::FieldAccess->new(name => 'world', value => 21) };
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

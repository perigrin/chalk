# ABOUTME: Tests that XS-compiled methods correctly handle class-scope lexicals.
# ABOUTME: Verifies methods referencing class-level `my $VAR = ...` fall back to Perl.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
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
use Chalk::Bootstrap::Perl::Target::ClassRegistry;
use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Semiring::Boolean;

# --- Step 1: Parse Boolean to IR and generate XS ---
my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSClassScope') };
ok(defined $gen, 'grammar pipeline setup') or BAIL_OUT("Cannot continue: $@");

my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm') };
ok(defined $ir, 'Boolean parses to IR') or BAIL_OUT("Parse failed: $@");

# --- Step 2: Generate single-class XS ---
my $reg = Chalk::Bootstrap::Perl::Target::ClassRegistry->new();
$reg->register('Chalk::Bootstrap::Semiring::Boolean', {
    ir => $ir, sa => $sa, ctx => $ctx, uses => [],
});

my $xs = Chalk::Bootstrap::Perl::Target::XS->new(
    module_name => 'Test::XSClassScope',
    class_registry => $reg,
);

my @entries = ({
    class_name => 'Chalk::Bootstrap::Semiring::Boolean',
    ir => $ir, sa => $sa, ctx => $ctx,
});

my $dist = eval { $xs->generate_distribution_multi_class(\@entries) };
ok(defined $dist, 'distribution generated') or BAIL_OUT("Dist gen failed: $@");

# --- Step 3: Build ---
my $tmpdir = tempdir(CLEANUP => 1);
for my $path (sort keys $dist->%*) {
    my $full_path = "$tmpdir/$path";
    make_path(dirname($full_path)) unless -d dirname($full_path);
    open(my $wfh, '>:encoding(UTF-8)', $full_path) or die "Cannot write $full_path: $!";
    print $wfh $dist->{$path};
    close $wfh;
}

{
    my $output = `cd "$tmpdir" && "$^X" -Ilib Build.PL 2>&1`;
    is($? >> 8, 0, 'Build.PL succeeds') or BAIL_OUT("Build.PL failed: $output");
}
{
    my $libs = join(':', 'lib', $ENV{PERL5LIB} // '');
    my $output = `cd "$tmpdir" && PERL5LIB="$libs" "$^X" Build 2>&1`;
    is($? >> 8, 0, 'Build succeeds') or BAIL_OUT("Build failed: $output");
}

# --- Step 4: Load XS ---
unshift @INC, "$tmpdir/blib/lib", "$tmpdir/blib/arch";
eval { require Test::XSClassScope };
is($@, '', 'XS loads') or BAIL_OUT("Load failed: $@");

# --- Step 5: Test correctness of Boolean methods ---
# Boolean has `my $ZERO = []` at class scope. After XS override,
# zero() must still return an arrayref (not undef), and is_zero()
# must correctly detect it.
my $bool = Chalk::Bootstrap::Semiring::Boolean->new();

my $zero = $bool->zero();
ok(defined $zero, 'Boolean::zero() returns a defined value');
ok(ref($zero), 'Boolean::zero() returns a reference');

my $iz = $bool->is_zero($zero);
ok($iz, 'Boolean::is_zero(zero()) returns true');

my $one = $bool->one();
ok(!$bool->is_zero($one), 'Boolean::is_zero(one()) returns false');

my $mul = $bool->multiply($one, $one);
ok(!$bool->is_zero($mul), 'multiply(one, one) is not zero');

my $mul_z = $bool->multiply($zero, $one);
ok($bool->is_zero($mul_z), 'multiply(zero, one) is zero');

done_testing();

# ABOUTME: End-to-end test for chalk.so + thin XS wrapper build pipeline.
# ABOUTME: Compiles hand-crafted boolean.c into chalk.so, validates loading and calling.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Config;

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
plan skip_all => 'No C compiler available' unless $have_compiler;

my $tmpdir = tempdir(CLEANUP => 1);
my $perl = $^X;
my $archlib = $Config{archlib};
my $ccflags = $Config{ccflags};
my $cc = $Config{cc};
my $so_ext = $Config{dlext};

# Locate c_src relative to this test file using Cwd::abs_path
my $c_src = do {
    use File::Basename qw(dirname);
    use Cwd qw(abs_path);
    my $dir = abs_path(dirname(__FILE__));
    abs_path("$dir/../../c_src");
};

# Test 1: boolean.c compiles
my $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$c_src $c_src/boolean.c -o $tmpdir/boolean.o 2>&1";
my $out = `$cmd`;
is($? >> 8, 0, 'boolean.c compiles to boolean.o') or diag("Compile failed: $out\nCommand: $cmd");

# Test 2: links into chalk.so
$cmd = "$cc -shared -fPIC $tmpdir/boolean.o -o $tmpdir/chalk.$so_ext 2>&1";
$out = `$cmd`;
is($? >> 8, 0, 'boolean.o links into chalk.so') or diag("Link failed: $out\nCommand: $cmd");

# Test 3: chalk.so exists
ok(-f "$tmpdir/chalk.$so_ext", 'chalk.so exists');

# Test 4: chalk.so loads and has our symbol
my $load_script = "$tmpdir/load_test.pl";
open my $lfh, '>', $load_script or die "Cannot write $load_script: $!";
print $lfh <<"END_SCRIPT";
use 5.42.0;
require DynaLoader;
my \$libref = DynaLoader::dl_load_file("$tmpdir/chalk.$so_ext", 0x01);
if (\$libref) {
    print "LOADED\\n";
    my \$sym = DynaLoader::dl_find_symbol(\$libref, "boolean_is_zero");
    print defined \$sym ? "SYMBOL_FOUND\\n" : "SYMBOL_MISSING\\n";
} else {
    print "LOAD_FAILED: " . DynaLoader::dl_error() . "\\n";
}
END_SCRIPT
close $lfh;
$out = `$perl $load_script 2>&1`;
like($out, qr/LOADED/, 'chalk.so loads via DynaLoader');
like($out, qr/SYMBOL_FOUND/, 'boolean_is_zero symbol found in chalk.so');

done_testing;

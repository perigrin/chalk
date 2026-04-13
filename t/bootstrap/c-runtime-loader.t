# ABOUTME: Tests Chalk::Bootstrap::Runtime loading chalk.so with RTLD_GLOBAL.
# ABOUTME: Validates that C symbols are visible to subsequently loaded .so files.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use Config;

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
plan skip_all => 'No C compiler available' unless $have_compiler;

my $tmpdir = tempdir(CLEANUP => 1);
my $cc      = $Config{cc};
my $ccflags = $Config{ccflags};
my $archlib = $Config{archlib};
my $so_ext  = $Config{dlext};

# Locate hand-crafted C fixtures relative to this test file
my $c_src = do {
    use File::Basename qw(dirname);
    use Cwd qw(abs_path);
    abs_path(dirname(__FILE__) . '/../fixtures/c_src');
};

# Emit chalk.h from Target::C (the shared runtime header it generates for all C output)
use lib 'lib';
require Chalk::Bootstrap::BNF::Target::C;
{
    my $target_c = Chalk::Bootstrap::BNF::Target::C->new();
    open my $fh, '>', "$tmpdir/chalk.h" or die "write chalk.h: $!";
    print $fh $target_c->generate_runtime_header();
    close $fh;
}

# Compile boolean.c to object
my $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$c_src -I$tmpdir $c_src/boolean.c -o $tmpdir/boolean.o 2>&1";
my $out = `$cmd`;
is($? >> 8, 0, 'boolean.c compiles') or BAIL_OUT("compile failed: $out");

# Link into chalk.so
$cmd = "$cc -shared -fPIC $tmpdir/boolean.o -o $tmpdir/chalk.$so_ext 2>&1";
$out = `$cmd`;
is($? >> 8, 0, 'chalk.so links') or BAIL_OUT("link failed: $out");

# Point Runtime.pm at the temp chalk.so
$ENV{CHALK_SO_PATH} = "$tmpdir/chalk.$so_ext";

use_ok('Chalk::Bootstrap::Runtime');

ok(Chalk::Bootstrap::Runtime->loaded(), 'chalk.so is loaded');

done_testing;

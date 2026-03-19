# ABOUTME: Tests the build-chalk-so script produces chalk.so and per-class XS wrappers.
# ABOUTME: Validates script output paths, symbol presence, and CHALK_SO_PATH usability.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use Config;

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};
plan skip_all => 'No C compiler available' unless $have_compiler;

my $perl   = $^X;
my $so_ext = $Config{dlext};

# Resolve repo root relative to this test file
my $repo_root = abs_path(dirname(__FILE__) . '/../..');
my $script    = "$repo_root/script/build-chalk-so";

ok(-f $script, 'build-chalk-so script exists');
ok(-x $script, 'build-chalk-so script is executable');

# Use a temporary BUILD_DIR so tests don't pollute the working tree
my $tmpdir   = tempdir(CLEANUP => 1);
my $build_dir = "$tmpdir/build";

# Run the script with BUILD_DIR override pointing at our temp directory
my $cmd = "$perl -I$repo_root/lib $script --build-dir $build_dir 2>&1";
my $out = `$cmd`;
my $exit = $? >> 8;

is($exit, 0, 'build-chalk-so exits cleanly')
    or BAIL_OUT("build-chalk-so failed:\n$out");

diag("build output:\n$out") if $ENV{TEST_VERBOSE};

# chalk.so must exist in build dir
ok(-f "$build_dir/chalk.$so_ext", "chalk.$so_ext built");

# Boolean XS .so must exist at the auto/ path matching the package name
ok(-f "$build_dir/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext",
    "Boolean.$so_ext built at auto/ path");

# chalk.so must export boolean_is_zero
require DynaLoader;
my $libref = DynaLoader::dl_load_file("$build_dir/chalk.$so_ext", 0x01);
ok(defined $libref, "chalk.$so_ext loads via DynaLoader")
    or BAIL_OUT("dl_load_file failed: " . DynaLoader::dl_error());

my $sym = DynaLoader::dl_find_symbol($libref, 'boolean_is_zero');
ok(defined $sym, 'chalk.so exports boolean_is_zero');

# Runtime.pm must be able to use chalk.so built by the script
$ENV{CHALK_SO_PATH} = "$build_dir/chalk.$so_ext";

# Force re-evaluation since module-level code runs at use time;
# we test in a subprocess to avoid the already-loaded Runtime state
my $runtime_script = <<'END_SCRIPT';
use 5.42.0;
require Chalk::Bootstrap::Runtime;
print Chalk::Bootstrap::Runtime->loaded() ? "LOADED\n" : "NOT_LOADED\n";
END_SCRIPT

my $rt_out = `$perl -I$repo_root/lib -e '$runtime_script' 2>&1`;
like($rt_out, qr/LOADED/, 'Runtime.pm loads chalk.so built by script');

done_testing;

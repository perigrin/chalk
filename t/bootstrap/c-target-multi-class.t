# ABOUTME: Tests Target::C emission for all 7 semiring/parser classes.
# ABOUTME: Verifies each class generates compilable C, then links all .o files into a single chalk.so.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use Config;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

use lib 'lib';
use lib 't/bootstrap/lib';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::C;

# All 7 classes to compile, in dependency order (Boolean first, Earley last).
my @classes = (
    ['Chalk::Bootstrap::Semiring::Boolean',         'lib/Chalk/Bootstrap/Semiring/Boolean.pm'],
    ['Chalk::Bootstrap::Semiring::Structural',      'lib/Chalk/Bootstrap/Semiring/Structural.pm'],
    ['Chalk::Bootstrap::Semiring::SemanticAction',  'lib/Chalk/Bootstrap/Semiring/SemanticAction.pm'],
    ['Chalk::Bootstrap::Semiring::FilterComposite', 'lib/Chalk/Bootstrap/Semiring/FilterComposite.pm'],
    ['Chalk::Bootstrap::Semiring::Precedence',      'lib/Chalk/Bootstrap/Semiring/Precedence.pm'],
    ['Chalk::Bootstrap::Semiring::TypeInference',   'lib/Chalk/Bootstrap/Semiring/TypeInference.pm'],
    ['Chalk::Bootstrap::Earley',                    'lib/Chalk/Bootstrap/Earley.pm'],
);

# === Phase 1: Set up grammar pipeline ===

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::CTMulti') };
ok(defined $gen, 'Phase 1: grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

# === Phase 2: Check compiler availability ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};

my $tmpdir = tempdir(CLEANUP => 1);

my $so_ext   = $Config{dlext};
my $cc       = $Config{cc};
my $ccflags  = $Config{ccflags};
my $archlib  = $Config{archlib};

my $repo_root = abs_path(dirname(__FILE__) . '/../..');
my $c_src_dir = "$repo_root/c_src";

# Copy chalk.h to temp directory (needed for all compilations)
copy("$c_src_dir/chalk.h", "$tmpdir/chalk.h")
    or BAIL_OUT("Cannot copy chalk.h: $!");

# Accumulate .o files for final link
my @object_files;

# === Phase 3: For each class: parse → generate C → compile ===

for my $class_spec (@classes) {
    my ($module_name, $source_file) = $class_spec->@*;

    my $slug = lc(($module_name =~ /(?:.*::)?(\w+)$/)[0]);

    # 3a: Parse the source file to IR
    my ($ir, $sa, $ctx) = eval { parse_file_ir($gen, $source_file) };
    ok(defined $ir, "Phase 3a [$slug]: $source_file parsed to IR")
        or do { note "parse_file_ir failed: $@"; next };

    # 3b: Construct Target::C and call generate_c_files
    my $target = eval {
        Chalk::Bootstrap::Perl::Target::C->new(module_name => $module_name)
    };
    ok(defined $target, "Phase 3b [$slug]: Target::C constructed")
        or do { note "constructor failed: $@"; next };

    my $result = eval { $target->generate_c_files($ir, $sa, $ctx) };
    is($@, '', "Phase 3c [$slug]: generate_c_files does not die")
        or do { note "generate_c_files died: $@"; next };
    ok(defined $result, "Phase 3c [$slug]: generate_c_files returns defined value")
        or next;

    # 3d: Verify output structure
    ok(exists $result->{files}{"${slug}.c"}, "Phase 3d [$slug]: files has ${slug}.c");
    ok(exists $result->{files}{"${slug}.h"}, "Phase 3d [$slug]: files has ${slug}.h");

    my $c_src  = $result->{files}{"${slug}.c"} // '';
    my $h_src  = $result->{files}{"${slug}.h"} // '';
    ok(length($c_src) > 0, "Phase 3d [$slug]: ${slug}.c is non-empty");
    ok(length($h_src) > 0, "Phase 3d [$slug]: ${slug}.h is non-empty");

    # 3e: Write generated files to temp dir
    {
        open my $cfh, '>:encoding(UTF-8)', "$tmpdir/${slug}.c"
            or die "Cannot write $tmpdir/${slug}.c: $!";
        print $cfh $c_src;
        close $cfh;

        open my $hfh, '>:encoding(UTF-8)', "$tmpdir/${slug}.h"
            or die "Cannot write $tmpdir/${slug}.h: $!";
        print $hfh $h_src;
        close $hfh;
    }

    SKIP: {
        skip "No C compiler available", 1 unless $have_compiler;

        # 3f: Compile ${slug}.c to ${slug}.o
        # Include tmpdir for chalk.h and all generated .h files
        my $compile_cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
                        . " $tmpdir/${slug}.c -o $tmpdir/${slug}.o 2>&1";
        my $compile_out = `$compile_cmd`;
        my $compile_ok = ($? >> 8) == 0;
        ok($compile_ok, "Phase 3f [$slug]: ${slug}.c compiles to ${slug}.o")
            or diag("Compile failed:\n$compile_out\nCommand: $compile_cmd\n"
                   . "First 60 lines of ${slug}.c:\n"
                   . join("\n", (split /\n/, $c_src)[0..59]));

        push @object_files, "$tmpdir/${slug}.o" if $compile_ok;
    }
}

# === Phase 4: Link all compiled .o files into a single chalk.so ===

SKIP: {
    skip "No C compiler available", 3 unless $have_compiler;

    my $min_objects = 1;
    skip "No .o files were compiled", 3 unless @object_files >= $min_objects;

    my $so_path = "$tmpdir/chalk.$so_ext";
    my $objs = join(' ', @object_files);
    my $link_cmd = "$cc -shared -fPIC $objs -o $so_path 2>&1";
    my $link_out = `$link_cmd`;
    is($? >> 8, 0, "Phase 4: all .o files link into chalk.$so_ext")
        or diag("Link failed:\n$link_out\nCommand: $link_cmd");

    ok(-f $so_path, "Phase 4: chalk.$so_ext exists");

    # Verify the shared library has at least some expected symbols.
    # nm -D lists dynamic symbols; we look for exported function names.
    my $nm_out = `nm -D "$so_path" 2>&1`;
    if ($? >> 8 == 0) {
        my @found = grep { /\bboolean_is_zero\b/ } split /\n/, $nm_out;
        ok(@found > 0, "Phase 4: chalk.so exports boolean_is_zero symbol");
    } else {
        # nm not available — just verify the file was created
        ok(-f $so_path, "Phase 4: chalk.so exists (nm not available for symbol check)");
    }
}

done_testing;

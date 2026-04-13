# ABOUTME: Tests for Target::C emission pipeline using Boolean.pm as the input IR.
# ABOUTME: Verifies generate_c_files structure, emitted C content, compilation, and behavioral correctness.
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use File::Copy qw(copy);
use Cwd qw(abs_path);
use Config;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::C;
use Chalk::Bootstrap::BNF::Target::C;

# === Phase 1: Set up grammar pipeline ===

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::CTBool') };
ok(defined $gen, 'Phase 1: grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

# === Phase 2: Parse Boolean.pm to IR ===

my ($ir, $sa, $ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm')
};
ok(defined $ir, 'Phase 2: Boolean.pm parsed to IR')
    or BAIL_OUT("Cannot continue without IR: $@");

# === Phase 3: Construct Target::C ===

my $target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(module_name => 'Chalk::Bootstrap::Semiring::Boolean')
};
ok(defined $target, 'Phase 3: Target::C constructed')
    or BAIL_OUT("Constructor failed: $@");
isa_ok($target, 'Chalk::Bootstrap::Perl::Target::C');
is($target->module_name(), 'Chalk::Bootstrap::Semiring::Boolean',
    'module_name reader returns correct value');

# === Phase 4: Call generate_c_files ===

my $result = eval { $target->generate_c_files($ir, $sa, $ctx) };
is($@, '', 'Phase 4: generate_c_files does not die')
    or BAIL_OUT("generate_c_files died: $@");
ok(defined $result, 'generate_c_files returns a defined value');

# === Phase 5: Verify result structure ===

is(ref($result), 'HASH', 'result is a hashref');

ok(exists $result->{files},                   'result has "files" key');
ok(exists $result->{exported_functions},      'result has "exported_functions" key');
ok(exists $result->{skipped_methods},         'result has "skipped_methods" key');
ok(exists $result->{anon_sub_registrations},  'result has "anon_sub_registrations" key');

is(ref($result->{files}), 'HASH',              '"files" is a hashref');
is(ref($result->{exported_functions}), 'ARRAY', '"exported_functions" is an arrayref');
is(ref($result->{skipped_methods}), 'ARRAY',    '"skipped_methods" is an arrayref');
is(ref($result->{anon_sub_registrations}), 'ARRAY', '"anon_sub_registrations" is an arrayref');

# The slug for Boolean is "boolean"
ok(exists $result->{files}{'boolean.c'}, '"files" has "boolean.c" key');
ok(exists $result->{files}{'boolean.h'}, '"files" has "boolean.h" key');

# === Phase 6: Verify content ===

my $c_src = $result->{files}{'boolean.c'};
ok(length($c_src) > 0, 'boolean.c is non-empty');
like($c_src, qr/boolean_is_zero/, 'boolean.c contains boolean_is_zero function');
like($c_src, qr/boolean_zero/,    'boolean.c contains boolean_zero function');
like($c_src, qr/boolean_one/,     'boolean.c contains boolean_one function');
like($c_src, qr/boolean_multiply/, 'boolean.c contains boolean_multiply function');
like($c_src, qr/boolean_add/,     'boolean.c contains boolean_add function');
unlike($c_src, qr/_impl_/, 'boolean.c has no _impl_ prefix');
unlike($c_src, qr/\bstatic\b[^*]*\bboolean_\w+\s*\(/, 'exported functions are not static');

my $h_src = $result->{files}{'boolean.h'};
ok(length($h_src) > 0, 'boolean.h is non-empty');
like($h_src, qr/boolean_is_zero/, 'boolean.h declares boolean_is_zero');
like($h_src, qr/#ifndef CHALK_BOOLEAN_H/, 'boolean.h has include guard');

# === Phase 7: Determinism check ===

my $result2 = eval { $target->generate_c_files($ir, $sa, $ctx) };
is($@, '', 'second generate_c_files call does not die');
is($result2->{files}{'boolean.c'}, $result->{files}{'boolean.c'}, 'deterministic .c output');
is($result2->{files}{'boolean.h'}, $result->{files}{'boolean.h'}, 'deterministic .h output');

# === Phase 8: Compile generated C and run behavioral tests ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};

SKIP: {
    skip 'No C compiler available', 20 unless $have_compiler;

    my $so_ext   = $Config{dlext};
    my $cc       = $Config{cc};
    my $ccflags  = $Config{ccflags};
    my $archlib  = $Config{archlib};
    my $privlib  = $Config{privlibexp};
    my $perl     = $^X;
    my $xsubpp   = "$privlib/ExtUtils/xsubpp";
    my $typemap  = "$privlib/ExtUtils/typemap";

    # Locate project root (used for the hand-crafted Boolean.xs fixture
    # and for pointing the subprocess @INC at this checkout's lib/).
    my $repo_root = abs_path(dirname(__FILE__) . '/../..');
    my $fixture_c_src = "$repo_root/t/fixtures/c_src";

    my $tmpdir = tempdir(CLEANUP => 1);

    # Write generated boolean.c and boolean.h to temp directory
    {
        open my $cfh, '>:encoding(UTF-8)', "$tmpdir/boolean.c"
            or die "Cannot write $tmpdir/boolean.c: $!";
        print $cfh $result->{files}{'boolean.c'};
        close $cfh;

        open my $hfh, '>:encoding(UTF-8)', "$tmpdir/boolean.h"
            or die "Cannot write $tmpdir/boolean.h: $!";
        print $hfh $result->{files}{'boolean.h'};
        close $hfh;
    }

    # Emit chalk.h from Target::C (same source as production builds)
    {
        my $target_c = Chalk::Bootstrap::BNF::Target::C->new();
        open my $chfh, '>', "$tmpdir/chalk.h"
            or die "Cannot write $tmpdir/chalk.h: $!";
        print $chfh $target_c->generate_runtime_header();
        close $chfh;
    }

    # Phase 8a: Compile boolean.c to boolean.o
    my $compile_cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir $tmpdir/boolean.c"
                    . " -o $tmpdir/boolean.o 2>&1";
    my $compile_out = `$compile_cmd`;
    is($? >> 8, 0, 'Phase 8a: generated boolean.c compiles to boolean.o')
        or diag("Compile failed:\n$compile_out\nCommand: $compile_cmd");

    # Phase 8b: Link into chalk.so
    my $link_cmd = "$cc -shared -fPIC $tmpdir/boolean.o -o $tmpdir/chalk.$so_ext 2>&1";
    my $link_out = `$link_cmd`;
    is($? >> 8, 0, 'Phase 8b: boolean.o links into chalk.so')
        or diag("Link failed:\n$link_out");

    ok(-f "$tmpdir/chalk.$so_ext", 'Phase 8b: chalk.so exists');

    # Phase 8c: Process Boolean.xs through xsubpp
    # Use a modified BOOT block that calls boolean_init_statics to initialize
    # class-scope static variables (e.g., _csv_boolean_ZERO).
    my $xs_content = do {
        open my $xsfh, '<', "$fixture_c_src/Boolean.xs" or die "Cannot read Boolean.xs: $!";
        local $/; <$xsfh>;
    };
    # Patch the BOOT block to add init_statics call before class setup
    $xs_content =~ s{(BOOT:\n\{)}{$1\n    boolean_init_statics(aTHX);};
    open my $xs_out, '>', "$tmpdir/Boolean.xs" or die "Cannot write Boolean.xs: $!";
    print $xs_out $xs_content;
    close $xs_out;

    my $xsubpp_cmd = "$perl $xsubpp -typemap $typemap $tmpdir/Boolean.xs 2>&1";
    my $xsubpp_out = `$xsubpp_cmd`;
    is($? >> 8, 0, 'Phase 8c: xsubpp processes Boolean.xs without error')
        or diag("xsubpp failed:\n$xsubpp_out");
    open my $bfh, '>', "$tmpdir/Boolean.c" or die "Cannot write Boolean.c: $!";
    print $bfh $xsubpp_out;
    close $bfh;

    # Phase 8d: Compile Boolean.c (xsubpp output)
    my $xs_compile_cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
                       . " $tmpdir/Boolean.c -o $tmpdir/Boolean.o 2>&1";
    my $xs_compile_out = `$xs_compile_cmd`;
    is($? >> 8, 0, 'Phase 8d: Boolean.c (xsubpp output) compiles to Boolean.o')
        or diag("Compile failed:\n$xs_compile_out\nCommand: $xs_compile_cmd");

    # Phase 8e: Link Boolean.so
    # Boolean.so does NOT need explicit -lchalk: chalk.so is loaded with
    # RTLD_GLOBAL in the subprocess, making boolean_* symbols visible.
    my $xs_link_cmd = "$cc -shared -fPIC $tmpdir/Boolean.o -o $tmpdir/Boolean.$so_ext 2>&1";
    my $xs_link_out = `$xs_link_cmd`;
    is($? >> 8, 0, 'Phase 8e: Boolean.o links into Boolean.so')
        or diag("Link failed:\n$xs_link_out");

    ok(-f "$tmpdir/Boolean.$so_ext", 'Phase 8e: Boolean.so exists');

    # Phase 8f: Build blib layout for require
    my $blib_arch = "$tmpdir/blib/arch/auto/Chalk/Bootstrap/Semiring/Boolean";
    my $blib_lib  = "$tmpdir/blib/lib/Chalk/Bootstrap/Semiring";
    make_path($blib_arch);
    make_path($blib_lib);
    copy("$tmpdir/Boolean.$so_ext", "$blib_arch/Boolean.$so_ext")
        or die "copy Boolean.so failed: $!";

    # Write stub .pm (same pattern as c-boolean-integration.t)
    my $stub_pm = "$blib_lib/Boolean.pm";
    open my $sfh, '>', $stub_pm or die "Cannot write $stub_pm: $!";
    print $sfh <<"END_PM";
package Chalk::Bootstrap::Semiring::Boolean;
use strict;
use warnings;
require DynaLoader;

my \$so;
for my \$dir (\@INC) {
    next if ref \$dir;
    my \$path = "\$dir/auto/Chalk/Bootstrap/Semiring/Boolean/Boolean.$so_ext";
    if (-f \$path) { \$so = \$path; last; }
}
die "Cannot locate Boolean.$so_ext in \@INC" unless defined \$so;

my \$libref = DynaLoader::dl_load_file(\$so, 0)
    or die "dl_load_file: " . DynaLoader::dl_error();
my \$boot = DynaLoader::dl_find_symbol(\$libref, "boot_Chalk__Bootstrap__Semiring__Boolean")
    or die "dl_find_symbol: " . DynaLoader::dl_error();
DynaLoader::dl_install_xsub("Chalk::Bootstrap::Semiring::Boolean::_bootstrap", \$boot, \$so);
Chalk::Bootstrap::Semiring::Boolean->_bootstrap();

1;
END_PM
    close $sfh;

    # === Phase 9: Behavioral equivalence via subprocess ===

    my $lib_line    = "use lib '$tmpdir/blib/arch';";
    my $lib_line2   = "use lib '$tmpdir/blib/lib';";
    my $lib_project = "use lib '$repo_root/lib';";
    my $chalk_load  = "require DynaLoader; "
        . "DynaLoader::dl_load_file('$tmpdir/chalk.$so_ext', 0x01) "
        . "or die 'chalk.so: ' . DynaLoader::dl_error();";

    my (undef, $script_file) = File::Temp::tempfile(
        SUFFIX => '.pl', UNLINK => 1, DIR => $tmpdir);
    open my $scfh, '>:utf8', $script_file or die "Cannot write $script_file: $!";
    print $scfh <<"END_SCRIPT";
use 5.42.0;
use utf8;
$lib_line
$lib_line2
$lib_project
$chalk_load
require Chalk::Bootstrap::Semiring::Boolean;

my \$b = Chalk::Bootstrap::Semiring::Boolean->new();
my \$zero = \$b->zero();
my \$one  = \$b->one();
print defined(\$zero) ? 'ZERO_EXISTS\\n'  : 'ZERO_MISSING\\n';
print defined(\$one)  ? 'ONE_EXISTS\\n'   : 'ONE_MISSING\\n';
print \$b->is_zero(\$zero)  ? 'IS_ZERO_OF_ZERO_OK\\n'  : 'IS_ZERO_OF_ZERO_FAIL\\n';
print !\$b->is_zero(\$one)  ? 'IS_ZERO_OF_ONE_OK\\n'   : 'IS_ZERO_OF_ONE_FAIL\\n';
my \$r1 = \$b->multiply(\$zero, \$one);
print \$b->is_zero(\$r1)  ? 'MULT_ZERO_ONE_OK\\n'  : 'MULT_ZERO_ONE_FAIL\\n';
my \$r3 = \$b->multiply(\$one, \$one);
print !\$b->is_zero(\$r3) ? 'MULT_ONE_ONE_OK\\n'   : 'MULT_ONE_ONE_FAIL\\n';
my \$a1 = \$b->add(\$zero, \$zero);
print \$b->is_zero(\$a1)  ? 'ADD_ZERO_ZERO_OK\\n'  : 'ADD_ZERO_ZERO_FAIL\\n';
my \$a2 = \$b->add(\$zero, \$one);
print !\$b->is_zero(\$a2) ? 'ADD_ZERO_ONE_OK\\n'   : 'ADD_ZERO_ONE_FAIL\\n';
print \$b->supports_leo() ? 'SUPPORTS_LEO_OK\\n' : 'SUPPORTS_LEO_FAIL\\n';
print 'BEHAVIORAL_OK\\n';
END_SCRIPT
    close $scfh;

    my $sub_out = `$perl $script_file 2>&1`;
    my $sub_exit = $? >> 8;

    is($sub_exit, 0, 'Phase 9: behavioral subprocess exits cleanly')
        or diag("Subprocess output:\n$sub_out");

    like($sub_out, qr/ZERO_EXISTS/,       'Phase 9: zero() returns defined value');
    like($sub_out, qr/ONE_EXISTS/,        'Phase 9: one() returns defined value');
    like($sub_out, qr/IS_ZERO_OF_ZERO_OK/,'Phase 9: is_zero(zero) is true');
    like($sub_out, qr/IS_ZERO_OF_ONE_OK/, 'Phase 9: is_zero(one) is false');
    like($sub_out, qr/MULT_ZERO_ONE_OK/,  'Phase 9: multiply(zero, one) = zero');
    like($sub_out, qr/MULT_ONE_ONE_OK/,   'Phase 9: multiply(one, one) = one');
    like($sub_out, qr/ADD_ZERO_ZERO_OK/,  'Phase 9: add(zero, zero) = zero');
    like($sub_out, qr/ADD_ZERO_ONE_OK/,   'Phase 9: add(zero, one) = one');
    like($sub_out, qr/SUPPORTS_LEO_OK/,   'Phase 9: supports_leo true');
    like($sub_out, qr/BEHAVIORAL_OK/,     'Phase 9: all behavioral tests pass');
}

done_testing;

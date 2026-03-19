# ABOUTME: Tests for Target::C::generate_xs_wrapper — auto-generates .xs wrappers from IR.
# ABOUTME: Verifies XS text structure for Boolean (no fields) and Precedence (with :param field).
use 5.42.0;
use utf8;
use Test::More;
use File::Temp qw(tempdir);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use Config;

use lib 'lib';
use lib 't/bootstrap/lib';

use TestXSHelpers qw(setup_xs_grammar parse_file_ir);
use Chalk::Bootstrap::Perl::Target::C;

# === Phase 1: Grammar pipeline ===

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::XSWrapGen') };
ok(defined $gen, 'Phase 1: grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

# === Phase 2: Parse Boolean.pm to IR ===

my ($bool_ir, $bool_sa, $bool_ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm')
};
ok(defined $bool_ir, 'Phase 2: Boolean.pm parsed to IR')
    or BAIL_OUT("Cannot continue without IR: $@");

# === Phase 3: generate_c_files + generate_xs_wrapper for Boolean ===

my $bool_target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Semiring::Boolean',
    )
};
ok(defined $bool_target, 'Phase 3: Target::C constructed for Boolean')
    or BAIL_OUT("Constructor failed: $@");

my $bool_c_result = eval { $bool_target->generate_c_files($bool_ir, $bool_sa, $bool_ctx) };
is($@, '', 'Phase 3: generate_c_files for Boolean does not die')
    or BAIL_OUT("generate_c_files died: $@");

can_ok($bool_target, 'generate_xs_wrapper');

my $bool_xs = eval {
    $bool_target->generate_xs_wrapper(
        $bool_ir,
        $bool_c_result->{exported_functions},
        $bool_c_result->{anon_sub_registrations},
    )
};
is($@, '', 'Phase 3: generate_xs_wrapper for Boolean does not die')
    or BAIL_OUT("generate_xs_wrapper died: $@");
ok(defined $bool_xs, 'Phase 3: generate_xs_wrapper returns defined value');
ok(length($bool_xs) > 0, 'Phase 3: generate_xs_wrapper returns non-empty string');

# === Phase 4: Verify Boolean .xs structure (no fields, no ADJUST) ===

like($bool_xs, qr/MODULE\s*=\s*Chalk::Bootstrap::Semiring::Boolean/,
    'Phase 4: Boolean .xs has MODULE line');
like($bool_xs, qr/PACKAGE\s*=\s*Chalk::Bootstrap::Semiring::Boolean/,
    'Phase 4: Boolean .xs has PACKAGE line');
like($bool_xs, qr/PROTOTYPES:\s*DISABLE/,
    'Phase 4: Boolean .xs has PROTOTYPES: DISABLE');
like($bool_xs, qr/BOOT:/,
    'Phase 4: Boolean .xs has BOOT block');
like($bool_xs, qr/Perl_class_setup_stash/,
    'Phase 4: Boolean .xs BOOT calls class_setup_stash');

# XSUBs for the exported boolean functions
like($bool_xs, qr/\bboolean_is_zero\b/,
    'Phase 4: Boolean .xs has XSUB for is_zero');
like($bool_xs, qr/\bboolean_zero\b/,
    'Phase 4: Boolean .xs has XSUB for zero');
like($bool_xs, qr/\bboolean_one\b/,
    'Phase 4: Boolean .xs has XSUB for one');
like($bool_xs, qr/\bboolean_multiply\b/,
    'Phase 4: Boolean .xs has XSUB for multiply');
like($bool_xs, qr/\bboolean_add\b/,
    'Phase 4: Boolean .xs has XSUB for add');

# RETVAL pattern: each XSUB delegates via RETVAL = func(aTHX_ ...)
like($bool_xs, qr/RETVAL\s*=\s*boolean_is_zero\s*\(aTHX_/,
    'Phase 4: is_zero XSUB delegates to boolean_is_zero(aTHX_...)');

# Boolean has no fields — BOOT should NOT call prepare_initfield_parse.
# Note: the extern forward declaration may still appear in the preamble;
# we verify the BOOT block itself does not contain a call to it.
my ($bool_boot) = $bool_xs =~ /^BOOT:\s*\{(.+?)^\}/ms;
unlike($bool_boot // '', qr/prepare_initfield_parse\s*\(/,
    'Phase 4: Boolean .xs BOOT does not call prepare_initfield_parse');

# Boolean has no ADJUST — BOOT should NOT call class_add_ADJUST
unlike($bool_boot // '', qr/class_add_ADJUST\s*\(/,
    'Phase 4: Boolean .xs BOOT does not call class_add_ADJUST');

# init_statics called in BOOT
like($bool_xs, qr/boolean_init_statics\s*\(aTHX\)/,
    'Phase 4: Boolean .xs BOOT calls boolean_init_statics');

# extern declarations for Perl class C API
like($bool_xs, qr/extern void Perl_class_setup_stash/,
    'Phase 4: Boolean .xs has extern declaration for class_setup_stash');

# === Phase 5: Parse Precedence.pm to IR (class WITH a :param field) ===

my ($prec_ir, $prec_sa, $prec_ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Precedence.pm')
};
ok(defined $prec_ir, 'Phase 5: Precedence.pm parsed to IR')
    or BAIL_OUT("Cannot continue without IR: $@");

my $prec_target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Semiring::Precedence',
    )
};
ok(defined $prec_target, 'Phase 5: Target::C constructed for Precedence')
    or BAIL_OUT("Constructor failed: $@");

my $prec_c_result = eval { $prec_target->generate_c_files($prec_ir, $prec_sa, $prec_ctx) };
is($@, '', 'Phase 5: generate_c_files for Precedence does not die')
    or BAIL_OUT("generate_c_files died: $@");

my $prec_xs = eval {
    $prec_target->generate_xs_wrapper(
        $prec_ir,
        $prec_c_result->{exported_functions},
        $prec_c_result->{anon_sub_registrations},
    )
};
is($@, '', 'Phase 5: generate_xs_wrapper for Precedence does not die')
    or BAIL_OUT("generate_xs_wrapper died: $@");
ok(defined $prec_xs, 'Phase 5: generate_xs_wrapper returns defined value for Precedence');

# === Phase 6: Verify Precedence .xs structure (has :param field) ===

like($prec_xs, qr/MODULE\s*=\s*Chalk::Bootstrap::Semiring::Precedence/,
    'Phase 6: Precedence .xs has MODULE line');
like($prec_xs, qr/PROTOTYPES:\s*DISABLE/,
    'Phase 6: Precedence .xs has PROTOTYPES: DISABLE');
like($prec_xs, qr/BOOT:/,
    'Phase 6: Precedence .xs has BOOT block');

# Precedence has a :param field '$lookup' — BOOT must register it
like($prec_xs, qr/prepare_initfield_parse/,
    'Phase 6: Precedence .xs BOOT has field registration');
like($prec_xs, qr/pad_add_name_pvs\s*\(\s*"\$lookup"/,
    'Phase 6: Precedence .xs BOOT registers $lookup field');
like($prec_xs, qr/class_apply_field_attributes/,
    'Phase 6: Precedence .xs BOOT applies field attributes');

# :param attribute applied to $lookup
like($prec_xs, qr/newSVpvs\s*\(\s*"param"\s*\)/,
    'Phase 6: Precedence .xs BOOT applies :param attribute to $lookup');

# init_statics called in BOOT
like($prec_xs, qr/precedence_init_statics\s*\(aTHX\)/,
    'Phase 6: Precedence .xs BOOT calls precedence_init_statics');

# === Phase 7: xsubpp can process the generated Boolean .xs ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};

SKIP: {
    skip 'No C compiler available', 6 unless $have_compiler;

    my $repo_root  = abs_path(dirname(__FILE__) . '/../..');
    my $c_src_dir  = "$repo_root/c_src";
    my $privlib    = $Config{privlibexp};
    my $perl       = $^X;
    my $xsubpp     = "$privlib/ExtUtils/xsubpp";
    my $typemap    = "$privlib/ExtUtils/typemap";
    my $cc         = $Config{cc};
    my $ccflags    = $Config{ccflags};
    my $archlib    = $Config{archlib};
    my $so_ext     = $Config{dlext};

    my $tmpdir = tempdir(CLEANUP => 1);

    # Write the generated Boolean.xs to a temp file
    my $xs_path = "$tmpdir/Boolean.xs";
    open my $xsfh, '>:encoding(UTF-8)', $xs_path
        or die "Cannot write $xs_path: $!";
    print $xsfh $bool_xs;
    close $xsfh;

    # Copy chalk.h and boolean.h (needed for xsubpp → compile pipeline)
    copy("$c_src_dir/chalk.h", "$tmpdir/chalk.h")
        or die "copy chalk.h failed: $!";

    # Write the generated boolean.h (needed by boolean.c, and maybe the .xs)
    open my $hfh, '>:encoding(UTF-8)', "$tmpdir/boolean.h"
        or die "Cannot write $tmpdir/boolean.h: $!";
    print $hfh $bool_c_result->{files}{'boolean.h'};
    close $hfh;

    # Phase 7a: xsubpp processes the generated .xs
    my $xs_c_path = "$tmpdir/Boolean_xs.c";
    my $xsubpp_cmd = "$perl $xsubpp -typemap $typemap $xs_path 2>&1";
    my $xsubpp_out = `$xsubpp_cmd`;
    my $xsubpp_exit = $? >> 8;
    is($xsubpp_exit, 0, 'Phase 7a: xsubpp processes generated Boolean.xs without error')
        or diag("xsubpp output:\n$xsubpp_out");

    open my $cfh, '>', $xs_c_path or die "Cannot write $xs_c_path: $!";
    print $cfh $xsubpp_out;
    close $cfh;

    # Phase 7b: compile generated boolean.c (needed for chalk.so)
    open my $c_out, '>:encoding(UTF-8)', "$tmpdir/boolean.c"
        or die "Cannot write $tmpdir/boolean.c: $!";
    print $c_out $bool_c_result->{files}{'boolean.c'};
    close $c_out;

    my $bool_compile = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
                     . " $tmpdir/boolean.c -o $tmpdir/boolean.o 2>&1";
    my $bool_out = `$bool_compile`;
    is($? >> 8, 0, 'Phase 7b: boolean.c compiles for chalk.so')
        or diag("boolean.c compile failed:\n$bool_out");

    # Phase 7c: link chalk.so
    my $chalk_so = "$tmpdir/chalk.$so_ext";
    my $link_cmd = "$cc -shared -fPIC $tmpdir/boolean.o -o $chalk_so 2>&1";
    my $link_out = `$link_cmd`;
    is($? >> 8, 0, 'Phase 7c: boolean.o links into chalk.so')
        or diag("chalk.so link failed:\n$link_out");

    # Phase 7d: compile the xsubpp-generated C
    my $xs_o_path = "$tmpdir/Boolean_xs.o";
    my $xs_compile = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
                   . " $xs_c_path -o $xs_o_path 2>&1";
    my $xs_compile_out = `$xs_compile`;
    is($? >> 8, 0, 'Phase 7d: generated Boolean.xs compiles after xsubpp')
        or diag("XS compile failed:\n$xs_compile_out\nCommand: $xs_compile");

    # Phase 7e: link Boolean.so
    my $bool_so_dir = "$tmpdir/auto/Chalk/Bootstrap/Semiring/Boolean";
    make_path($bool_so_dir);
    my $bool_so = "$bool_so_dir/Boolean.$so_ext";
    my $xs_link = "$cc -shared -fPIC $xs_o_path $chalk_so -o $bool_so 2>&1";
    my $xs_link_out = `$xs_link`;
    is($? >> 8, 0, 'Phase 7e: generated Boolean XS links into Boolean.so')
        or diag("XS link failed:\n$xs_link_out");

    ok(-f $bool_so, 'Phase 7e: Boolean.so exists');
}

done_testing;

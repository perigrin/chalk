# ABOUTME: Tests that Target::C emits direct C function calls for known-typed fields.
# ABOUTME: Verifies field_types parameter triggers {slug}_{method}(aTHX_ ...) instead of call_method.
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

my $PERL     = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $repo_root = abs_path(dirname(__FILE__) . '/../..');

# === Phase 1: Build grammar pipeline ===

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::CTCrossClass') };
ok(defined $gen, 'Phase 1: grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

# === Phase 2: Parse Earley.pm and Boolean.pm to IR ===

my ($earley_ir, $earley_sa, $earley_ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm')
};
ok(defined $earley_ir, 'Phase 2a: Earley.pm parsed to IR')
    or BAIL_OUT("Cannot parse Earley.pm: $@");

my ($bool_ir, $bool_sa, $bool_ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm')
};
ok(defined $bool_ir, 'Phase 2b: Boolean.pm parsed to IR')
    or BAIL_OUT("Cannot parse Boolean.pm: $@");

# === Phase 3: Generate Boolean.c without field_types (baseline) ===

my $bool_target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Semiring::Boolean',
    )
};
ok(defined $bool_target, 'Phase 3a: Boolean Target::C constructed without field_types');

my $bool_result = eval { $bool_target->generate_c_files($bool_ir, $bool_sa, $bool_ctx) };
is($@, '', 'Phase 3b: Boolean generate_c_files does not die');
ok(defined $bool_result, 'Phase 3c: Boolean generate_c_files returns defined value');

my $bool_c = $bool_result->{files}{'boolean.c'} // '';
ok(length($bool_c) > 0, 'Phase 3d: boolean.c is non-empty');

# === Phase 4: Generate earley.c WITHOUT field_types — uses call_method ===

my $earley_baseline = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Earley',
    )
};
ok(defined $earley_baseline, 'Phase 4a: Earley Target::C constructed without field_types');

my $baseline_result = eval {
    $earley_baseline->generate_c_files($earley_ir, $earley_sa, $earley_ctx)
};
is($@, '', 'Phase 4b: baseline generate_c_files does not die');
ok(defined $baseline_result, 'Phase 4c: baseline generate_c_files returns defined value');

my $baseline_c = $baseline_result->{files}{'earley.c'} // '';
ok(length($baseline_c) > 0, 'Phase 4d: baseline earley.c is non-empty');

# Baseline should use call_method for semiring calls
my $baseline_call_method_count = () = $baseline_c =~ /call_method\("is_zero"/g;
ok($baseline_call_method_count > 0,
    "Phase 4e: baseline earley.c has call_method(\"is_zero\") calls ($baseline_call_method_count found)");

# Baseline should NOT have direct boolean_is_zero calls
my $baseline_direct_count = () = $baseline_c =~ /boolean_is_zero\(/g;
is($baseline_direct_count, 0,
    'Phase 4f: baseline earley.c has no direct boolean_is_zero() calls');

# === Phase 5: Generate earley.c WITH field_types — uses direct C calls ===

my $earley_typed = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Earley',
        field_types => {
            semiring => 'Chalk::Bootstrap::Semiring::Boolean',
        },
    )
};
ok(defined $earley_typed, 'Phase 5a: Earley Target::C constructed with field_types');

my $typed_result = eval {
    $earley_typed->generate_c_files($earley_ir, $earley_sa, $earley_ctx)
};
is($@, '', 'Phase 5b: typed generate_c_files does not die');
ok(defined $typed_result, 'Phase 5c: typed generate_c_files returns defined value');

my $typed_c = $typed_result->{files}{'earley.c'} // '';
ok(length($typed_c) > 0, 'Phase 5d: typed earley.c is non-empty');

# With field_types, is_zero calls on $semiring should be direct C calls
my $typed_direct_count = () = $typed_c =~ /boolean_is_zero\(/g;
ok($typed_direct_count > 0,
    "Phase 5e: typed earley.c has direct boolean_is_zero() calls ($typed_direct_count found)");

# With field_types, the is_zero call_method invocations on semiring should be eliminated
my $typed_call_method_count = () = $typed_c =~ /call_method\("is_zero"/g;
ok($typed_call_method_count < $baseline_call_method_count,
    "Phase 5f: typed earley.c has fewer call_method(\"is_zero\") calls"
    . " ($typed_call_method_count vs $baseline_call_method_count in baseline)");

# The typed .c file should include boolean.h for cross-class function declarations
like($typed_c, qr/#include\s+"boolean\.h"/, 'Phase 5g: typed earley.c includes boolean.h');

# === Phase 6: Compile both .c files together (if compiler available) ===

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
my $c_src_dir = "$repo_root/c_src";

copy("$c_src_dir/chalk.h", "$tmpdir/chalk.h")
    or die "Cannot copy chalk.h: $!";

SKIP: {
    skip "No C compiler available", 7 unless $have_compiler;

    # Write generated files to temp dir
    for my $pair (
        ['boolean.c', $bool_c],
        ['boolean.h', $bool_result->{files}{'boolean.h'} // ''],
        ['earley.c',  $typed_c],
        ['earley.h',  $typed_result->{files}{'earley.h'} // ''],
    ) {
        my ($fname, $content) = $pair->@*;
        open my $fh, '>:encoding(UTF-8)', "$tmpdir/$fname"
            or die "Cannot write $tmpdir/$fname: $!";
        print $fh $content;
        close $fh;
    }

    # Compile boolean.c
    my $bool_cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
                 . " $tmpdir/boolean.c -o $tmpdir/boolean.o 2>&1";
    my $bool_out = `$bool_cmd`;
    my $bool_ok  = ($? >> 8) == 0;
    ok($bool_ok, 'Phase 6a: boolean.c compiles to boolean.o')
        or diag("Compile failed:\n$bool_out\nCommand: $bool_cmd");

    # Compile earley.c (with field_types — references boolean_is_zero)
    my $earley_cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
                   . " $tmpdir/earley.c -o $tmpdir/earley.o 2>&1";
    my $earley_out = `$earley_cmd`;
    my $earley_ok  = ($? >> 8) == 0;
    ok($earley_ok, 'Phase 6b: typed earley.c compiles to earley.o')
        or diag("Compile failed:\n$earley_out\nCommand: $earley_cmd\n"
               . "First 40 lines of earley.c:\n"
               . join("\n", (split /\n/, $typed_c)[0..39]));

    SKIP: {
        skip "boolean.o or earley.o not compiled", 5
            unless $bool_ok && $earley_ok;

        # Link both into chalk.so
        my $so_path  = "$tmpdir/chalk.$so_ext";
        my $link_cmd = "$cc -shared -fPIC $tmpdir/boolean.o $tmpdir/earley.o"
                     . " -o $so_path 2>&1";
        my $link_out = `$link_cmd`;
        my $link_ok  = ($? >> 8) == 0;
        ok($link_ok, "Phase 6c: boolean.o + earley.o link into chalk.$so_ext")
            or diag("Link failed:\n$link_out\nCommand: $link_cmd");

        ok(-f $so_path, "Phase 6d: chalk.$so_ext file exists");

        # Verify symbols: chalk.so should export boolean_is_zero
        my $nm_out = `nm -D "$so_path" 2>&1`;
        if ($? >> 8 == 0) {
            my @bool_fns = grep { /\bboolean_is_zero\b/ } split /\n/, $nm_out;
            ok(@bool_fns > 0, 'Phase 6e: chalk.so exports boolean_is_zero symbol');

            # Verify no unresolved boolean_is_zero (it should be defined, not just referenced)
            my @undef_refs = grep { /\bU\b.*boolean_is_zero/ } split /\n/, $nm_out;
            is(scalar @undef_refs, 0,
                'Phase 6f: no unresolved boolean_is_zero references in chalk.so');

            # Count improvement: report direct vs call_method for is_zero
            my $all_call_method_count = () = $typed_c =~ /call_method\(/g;
            my $all_direct_count      = () = $typed_c =~ /boolean_\w+\(aTHX_/g;
            note("Direct C calls in typed earley.c: $all_direct_count");
            note("Remaining call_method calls in typed earley.c: $all_call_method_count");
            ok(1, "Phase 6g: improvement metrics reported (see notes above)");
        } else {
            ok(-f $so_path, 'Phase 6e: chalk.so exists (nm not available)');
            ok(1, 'Phase 6f: nm not available — symbol check skipped');
            ok(1, 'Phase 6g: nm not available — improvement metrics skipped');
        }
    }
}

done_testing;

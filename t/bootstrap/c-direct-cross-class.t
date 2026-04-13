# ABOUTME: Tests that Target::C emits direct C function calls for known-typed fields.
# ABOUTME: Verifies field_types parameter triggers #include and {slug}_{method}(aTHX_ ...) emission.
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
use Chalk::Bootstrap::BNF::Target::C;

my $PERL      = "$ENV{HOME}/.local/share/pvm/versions/5.42.0/bin/perl";
my $repo_root = abs_path(dirname(__FILE__) . '/../..');

# === Phase 1: Build grammar pipeline (shared by all tests) ===

my $gen = eval { setup_xs_grammar('Chalk::Grammar::Perl::CTCrossClass') };
ok(defined $gen, 'Phase 1: grammar pipeline built')
    or BAIL_OUT("Cannot continue without grammar: $@");

# === Phase 2: Parse Boolean.pm (fast — 68 lines) ===

my ($bool_ir, $bool_sa, $bool_ctx) = eval {
    parse_file_ir($gen, 'lib/Chalk/Bootstrap/Semiring/Boolean.pm')
};
ok(defined $bool_ir, 'Phase 2: Boolean.pm parsed to IR')
    or BAIL_OUT("Cannot parse Boolean.pm: $@");

# === Phase 3: Infrastructure tests using Boolean ===

# 3a: Construct C.pm with field_types
my $typed_target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Semiring::Boolean',
        field_types => {
            semiring => 'Chalk::Bootstrap::Earley',
        },
    )
};
ok(defined $typed_target, 'Phase 3a: Target::C constructed with field_types');

# 3b: Generate .c — should include earley.h
my $typed_result = eval { $typed_target->generate_c_files($bool_ir, $bool_sa, $bool_ctx) };
is($@, '', 'Phase 3b: generate_c_files with field_types does not die');
ok(defined $typed_result, 'Phase 3c: generate_c_files returns defined value');

my $typed_c = $typed_result->{files}{'boolean.c'} // '';
ok(length($typed_c) > 0, 'Phase 3d: boolean.c with field_types is non-empty');

# 3e: Cross-class include present
like($typed_c, qr/#include\s+"earley\.h"/,
    'Phase 3e: boolean.c includes earley.h when field_types has earley');

# 3f: Self-include NOT duplicated
my @earley_includes = $typed_c =~ /(#include\s+"earley\.h")/g;
is(scalar @earley_includes, 1, 'Phase 3f: earley.h included exactly once');

# 3g: Own header still included
like($typed_c, qr/#include\s+"boolean\.h"/,
    'Phase 3g: boolean.c still includes its own boolean.h');

# === Phase 4: Verify no cross-class include without field_types ===

my $plain_target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Semiring::Boolean',
    )
};
ok(defined $plain_target, 'Phase 4a: Target::C constructed without field_types');

my $plain_result = eval { $plain_target->generate_c_files($bool_ir, $bool_sa, $bool_ctx) };
is($@, '', 'Phase 4b: generate_c_files without field_types does not die');

my $plain_c = $plain_result->{files}{'boolean.c'} // '';
unlike($plain_c, qr/#include\s+"earley\.h"/,
    'Phase 4c: boolean.c without field_types does not include earley.h');

# === Phase 5: Multiple field_types — deduplication and sorting ===

my $multi_target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Semiring::Boolean',
        field_types => {
            field_a => 'Chalk::Bootstrap::Earley',
            field_b => 'Chalk::Bootstrap::Semiring::Structural',
            field_c => 'Chalk::Bootstrap::Earley',  # duplicate target
        },
    )
};
ok(defined $multi_target, 'Phase 5a: Target::C with multiple field_types constructed');

my $multi_result = eval { $multi_target->generate_c_files($bool_ir, $bool_sa, $bool_ctx) };
is($@, '', 'Phase 5b: generate_c_files with multiple field_types does not die');

my $multi_c = $multi_result->{files}{'boolean.c'} // '';

# Earley appears only once (deduplicated)
my @earley_multi = $multi_c =~ /(#include\s+"earley\.h")/g;
is(scalar @earley_multi, 1, 'Phase 5c: earley.h included once despite duplicate field_types');

# Structural also included
like($multi_c, qr/#include\s+"structural\.h"/,
    'Phase 5d: structural.h included for second target class');

# Includes are sorted (earley before structural)
$multi_c =~ /(#include\s+"earley\.h".*#include\s+"structural\.h")/s;
ok(defined $1, 'Phase 5e: cross-class includes are sorted alphabetically');

# === Phase 6: Self-referencing field_types — skip self-include ===

my $self_target = eval {
    Chalk::Bootstrap::Perl::Target::C->new(
        module_name => 'Chalk::Bootstrap::Semiring::Boolean',
        field_types => {
            self_ref => 'Chalk::Bootstrap::Semiring::Boolean',
        },
    )
};
ok(defined $self_target, 'Phase 6a: Target::C with self-referencing field_types constructed');

my $self_result = eval { $self_target->generate_c_files($bool_ir, $bool_sa, $bool_ctx) };
is($@, '', 'Phase 6b: generate_c_files with self-referencing field_types does not die');

my $self_c = $self_result->{files}{'boolean.c'} // '';
my @bool_includes = $self_c =~ /(#include\s+"boolean\.h")/g;
is(scalar @bool_includes, 1,
    'Phase 6c: self-referencing field_type does not cause duplicate boolean.h include');

# === Phase 7: Compile with cross-class includes ===

my $have_compiler;
eval {
    require ExtUtils::CBuilder;
    $have_compiler = ExtUtils::CBuilder->new(quiet => 1)->have_compiler;
};

SKIP: {
    skip "No C compiler available", 3 unless $have_compiler;

    my $tmpdir  = tempdir(CLEANUP => 1);
    my $so_ext  = $Config{dlext};
    my $cc      = $Config{cc};
    my $ccflags = $Config{ccflags};
    my $archlib = $Config{archlib};

    # Emit chalk.h from Target::C (same header that's bundled with generated code)
    {
        my $target_c = Chalk::Bootstrap::BNF::Target::C->new();
        open my $fh, '>', "$tmpdir/chalk.h"
            or die "Cannot write $tmpdir/chalk.h: $!";
        print $fh $target_c->generate_runtime_header();
        close $fh;
    }

    # Write boolean files (from plain result — no cross-class refs to worry about)
    for my $pair (
        ['boolean.c', $plain_c],
        ['boolean.h', $plain_result->{files}{'boolean.h'} // ''],
    ) {
        my ($fname, $content) = $pair->@*;
        open my $fh, '>:encoding(UTF-8)', "$tmpdir/$fname"
            or die "Cannot write $tmpdir/$fname: $!";
        print $fh $content;
        close $fh;
    }

    # Compile plain boolean.c (no cross-class)
    my $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
            . " $tmpdir/boolean.c -o $tmpdir/boolean.o 2>&1";
    my $out = `$cmd`;
    my $ok  = ($? >> 8) == 0;
    ok($ok, 'Phase 7a: plain boolean.c compiles')
        or diag("Compile failed:\n$out");

    # Write typed boolean.c (has #include "earley.h" — needs stub)
    open my $fh, '>:encoding(UTF-8)', "$tmpdir/boolean_typed.c"
        or die "write: $!";
    print $fh $typed_c;
    close $fh;

    # Create stub earley.h so the #include resolves
    open $fh, '>:encoding(UTF-8)', "$tmpdir/earley.h"
        or die "write: $!";
    print $fh "/* stub */\n#ifndef CHALK_EARLEY_H\n#define CHALK_EARLEY_H\n#include \"chalk.h\"\n#endif\n";
    close $fh;

    $cmd = "$cc -c -fPIC $ccflags -I$archlib/CORE -I$tmpdir"
         . " $tmpdir/boolean_typed.c -o $tmpdir/boolean_typed.o 2>&1";
    $out = `$cmd`;
    $ok  = ($? >> 8) == 0;
    ok($ok, 'Phase 7b: typed boolean.c (with cross-class includes) compiles')
        or diag("Compile failed:\n$out");

    ok(-f "$tmpdir/boolean_typed.o", 'Phase 7c: boolean_typed.o exists');
}

# === Phase 8: Earley direct-call verification (slow — requires parsing 1092-line file) ===

SKIP: {
    skip "Set CHALK_SLOW_TESTS=1 to run Earley direct-call tests", 8
        unless $ENV{CHALK_SLOW_TESTS};

    my ($earley_ir, $earley_sa, $earley_ctx) = eval {
        parse_file_ir($gen, 'lib/Chalk/Bootstrap/Earley.pm')
    };
    ok(defined $earley_ir, 'Phase 8a: Earley.pm parsed to IR')
        or skip("Cannot parse Earley.pm: $@", 7);

    # Baseline: no field_types
    my $baseline = eval {
        Chalk::Bootstrap::Perl::Target::C->new(
            module_name => 'Chalk::Bootstrap::Earley',
        )
    };
    my $baseline_result = eval {
        $baseline->generate_c_files($earley_ir, $earley_sa, $earley_ctx)
    };
    my $baseline_c = $baseline_result->{files}{'earley.c'} // '';
    ok(length($baseline_c) > 0, 'Phase 8b: baseline earley.c generated');

    my $baseline_call_method_count = () = $baseline_c =~ /call_method\("is_zero"/g;
    ok($baseline_call_method_count > 0,
        "Phase 8c: baseline has call_method(\"is_zero\") ($baseline_call_method_count)");

    # Typed: semiring → Boolean
    my $typed = eval {
        Chalk::Bootstrap::Perl::Target::C->new(
            module_name => 'Chalk::Bootstrap::Earley',
            field_types => {
                semiring => 'Chalk::Bootstrap::Semiring::Boolean',
            },
        )
    };
    my $typed_result = eval {
        $typed->generate_c_files($earley_ir, $earley_sa, $earley_ctx)
    };
    my $typed_c_earley = $typed_result->{files}{'earley.c'} // '';
    ok(length($typed_c_earley) > 0, 'Phase 8d: typed earley.c generated');

    my $typed_direct_count = () = $typed_c_earley =~ /boolean_\w+\(aTHX_/g;
    ok($typed_direct_count > 0,
        "Phase 8e: typed earley.c has direct boolean_* calls ($typed_direct_count)");

    like($typed_c_earley, qr/#include\s+"boolean\.h"/,
        'Phase 8f: typed earley.c includes boolean.h');

    my $typed_call_method_count = () = $typed_c_earley =~ /call_method\("is_zero"/g;
    ok($typed_call_method_count < $baseline_call_method_count,
        "Phase 8g: fewer call_method(\"is_zero\") calls"
        . " ($typed_call_method_count vs $baseline_call_method_count)");

    note("Direct C calls: $typed_direct_count");
    note("Remaining call_method(is_zero): $typed_call_method_count");
    note("Eliminated: " . ($baseline_call_method_count - $typed_call_method_count) . " call_method(is_zero) calls");

    ok(1, 'Phase 8h: Earley direct-call verification complete');
}

done_testing;

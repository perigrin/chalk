#!/usr/bin/env perl
# ABOUTME: Test that generated XS code actually compiles using ExtUtils::MakeMaker
# ABOUTME: Verifies the XS compilation pipeline from .xs to loadable module
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/lib";

# Check if we have ExtUtils::MakeMaker and a C compiler
BEGIN {
    eval { require ExtUtils::MakeMaker; };
    if ($@) {
        plan skip_all => 'ExtUtils::MakeMaker required for XS compilation tests';
    }
}

use_ok('XSTestHelper') or BAILOUT("Cannot load XSTestHelper");

# Test 1: Simple constant return function compiles
subtest 'xs_compiles_constant_return' => sub {
    plan tests => 4;

    my $tempdir = tempdir(CLEANUP => 1);
    my $module_name = 'TestMod';

    # XS code for a simple constant return
    my $xs_code = <<'XS_CODE';
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = TestMod  PACKAGE = TestMod

NV
foo()
CODE:
    RETVAL = 42;
OUTPUT:
    RETVAL
XS_CODE

    # Generate Makefile.PL
    ok(XSTestHelper::generate_makefile_pl($tempdir, $module_name),
       'generate_makefile_pl succeeds');
    ok(-f "$tempdir/Makefile.PL", 'Makefile.PL created');

    # Write XS file
    ok(XSTestHelper::write_xs_file($tempdir, $module_name, $xs_code),
       'write_xs_file succeeds');
    ok(-f "$tempdir/$module_name.xs", 'XS file created');
};

# Test 2: Compilation succeeds
subtest 'xs_compilation_succeeds' => sub {
    plan tests => 1;

    my $tempdir = tempdir(CLEANUP => 1);
    my $module_name = 'TestMod';

    my $xs_code = <<'XS_CODE';
#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

MODULE = TestMod  PACKAGE = TestMod

NV
foo()
CODE:
    RETVAL = 42;
OUTPUT:
    RETVAL
XS_CODE

    XSTestHelper::generate_makefile_pl($tempdir, $module_name);
    XSTestHelper::write_xs_file($tempdir, $module_name, $xs_code);

    # Compile the XS
    my $result = XSTestHelper::compile_xs($tempdir);
    ok($result->{success}, 'XS compilation succeeds')
        or diag("Compilation failed:\n" . $result->{stderr});
};

done_testing();

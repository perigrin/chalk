#!/usr/bin/env perl
# ABOUTME: Tests for PMC module-level code generation
# ABOUTME: Verifies that XS target generates PMC with proper pragmas and imports
use 5.42.0;
use Test::More;
use experimental qw(class);

# Set lib path at compile time
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use_ok('Chalk::Target::XS') or BAIL_OUT("Cannot load Chalk::Target::XS");

# Helper to create an XS target with minimal graph
sub make_xs_target {
    my ($module_name) = @_;
    my $graph = { nodes => {}, start => undef, end => undef };
    return Chalk::Target::XS->new(
        graph => $graph,
        module_name => $module_name
    );
}

# Test that PMC contains use 5.42.0 (not use v5.40)
{
    my $xs = make_xs_target('MyClass');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/use 5\.42\.0;/,
        'PMC uses 5.42.0 version declaration');
    unlike($pmc, qr/use v5\.40;/,
        'PMC does not use old 5.40 version');
}

# Test that PMC contains experimental qw(class)
{
    my $xs = make_xs_target('MyClass');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/use experimental qw\(class\);/,
        'PMC enables experimental class feature');
}

# Test that PMC contains use utf8
{
    my $xs = make_xs_target('MyClass');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/use utf8;/,
        'PMC enables utf8 source encoding');
}

# Test that PMC contains package declaration
{
    my $xs = make_xs_target('Foo::Bar');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/package Foo::Bar;/,
        'PMC has correct package declaration');
}

# Test that PMC contains XSLoader::load
{
    my $xs = make_xs_target('MyClass');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/use XSLoader;/,
        'PMC loads XSLoader');
    like($pmc, qr/XSLoader::load\(__PACKAGE__, \$VERSION\);/,
        'PMC calls XSLoader::load');
}

# Test that PMC contains VERSION variable
{
    my $xs = make_xs_target('MyClass');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/our \$VERSION = '0\.01';/,
        'PMC declares VERSION variable');
}

# Test that PMC ends with 1;
{
    my $xs = make_xs_target('MyClass');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/1;\s*$/,
        'PMC ends with 1;');
}

# Test that PMC has ABOUTME headers
{
    my $xs = make_xs_target('MyClass');
    my $pmc = $xs->generate_pmc();

    like($pmc, qr/^# ABOUTME:/m,
        'PMC has ABOUTME header');
}

# Test complete PMC structure
{
    my $xs = make_xs_target('Test::Module');
    my $pmc = $xs->generate_pmc();

    # Check that all essential elements appear in correct order
    my @lines = split /\n/, $pmc;

    # First two lines should be ABOUTME comments
    like($lines[0], qr/^# ABOUTME:/, 'First line is ABOUTME');
    like($lines[1], qr/^# ABOUTME:/, 'Second line is ABOUTME');

    # Then package declaration
    ok((grep { /^package Test::Module;/ } @lines), 'Has package declaration');

    # Then version and pragmas (order may vary)
    ok((grep { /^use 5\.42\.0;/ } @lines), 'Has version declaration');
    ok((grep { /^use experimental qw\(class\);/ } @lines), 'Has experimental pragma');
    ok((grep { /^use utf8;/ } @lines), 'Has utf8 pragma');

    # Then XSLoader
    ok((grep { /^use XSLoader;/ } @lines), 'Has XSLoader use');
    ok((grep { /^our \$VERSION/ } @lines), 'Has VERSION variable');
    ok((grep { /^XSLoader::load/ } @lines), 'Has XSLoader::load call');

    # Finally ends with 1;
    is($lines[-1], '1;', 'Ends with 1;');
}

done_testing();

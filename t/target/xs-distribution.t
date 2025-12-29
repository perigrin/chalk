#!/usr/bin/env perl
# ABOUTME: Tests for Module::Build::Tiny distribution generation
# ABOUTME: Verifies that XS target generates valid CPAN-ready distributions
use 5.42.0;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
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

# Test that distribution methods exist
{
    my $xs = make_xs_target('Test::Module');
    ok($xs->can('generate_build_pl'), 'XS target has generate_build_pl method');
    ok($xs->can('generate_distribution'), 'XS target has generate_distribution method');
}

# Test Build.PL generation
{
    my $xs = make_xs_target('MyClass');
    my $build_pl = $xs->generate_build_pl();

    like($build_pl, qr/use\s+Module::Build::Tiny/,
        'Build.PL uses Module::Build::Tiny');
    like($build_pl, qr/Build_PL/,
        'Build.PL calls Build_PL');
}

# Test Build.PL with nested module name
{
    my $xs = make_xs_target('Foo::Bar::Baz');
    my $build_pl = $xs->generate_build_pl();

    like($build_pl, qr/Module::Build::Tiny/,
        'Build.PL for nested module uses Module::Build::Tiny');
}

# Test generate_distribution returns all expected files
{
    my $xs = make_xs_target('MyClass');
    my $dist = $xs->generate_distribution();

    ok(ref($dist) eq 'HASH', 'generate_distribution returns hashref');
    ok(exists $dist->{'Build.PL'}, 'Distribution includes Build.PL');
    ok(exists $dist->{'lib/MyClass.pm'}, 'Distribution includes .pm file');
    ok(exists $dist->{'lib/MyClass.xs'}, 'Distribution includes .xs file');
}

# Test distribution file paths for nested module
{
    my $xs = make_xs_target('Foo::Bar');
    my $dist = $xs->generate_distribution();

    ok(exists $dist->{'Build.PL'}, 'Distribution includes Build.PL');
    ok(exists $dist->{'lib/Foo/Bar.pm'}, 'Distribution includes nested .pm path');
    ok(exists $dist->{'lib/Foo/Bar.xs'}, 'Distribution includes nested .xs path');
}

# Test XSLoader stub is in .pm file
{
    my $xs = make_xs_target('MyClass');
    my $dist = $xs->generate_distribution();
    my $pm_content = $dist->{'lib/MyClass.pm'};

    like($pm_content, qr/package\s+MyClass/,
        '.pm file has correct package');
    like($pm_content, qr/use\s+XSLoader/,
        '.pm file uses XSLoader');
    like($pm_content, qr/XSLoader::load/,
        '.pm file calls XSLoader::load');
}

# Test VERSION is set correctly
{
    my $xs = make_xs_target('MyClass');
    my $dist = $xs->generate_distribution();
    my $pm_content = $dist->{'lib/MyClass.pm'};

    like($pm_content, qr/our\s+\$VERSION/,
        '.pm file has VERSION');
}

done_testing();

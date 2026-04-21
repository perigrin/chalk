# ABOUTME: Tests for Chalk::MOP::Import metaobject.
# ABOUTME: Verifies accessors: module, args, class.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Basic import construction via declare_import
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Consumer');
    my $import = $cls->declare_import('strict');

    isa_ok($import, 'Chalk::MOP::Import');
    is($import->module, 'strict', 'module accessor');
    is(refaddr($import->class), refaddr($cls), 'import class points back');
}

# args default to empty
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Plain');
    my $import = $cls->declare_import('warnings');

    is_deeply([$import->args], [], 'args default to empty');
}

# args can be set
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Selective');
    my $import = $cls->declare_import('Scalar::Util', args => ['refaddr', 'blessed']);

    is($import->module, 'Scalar::Util', 'module with args');
    is_deeply([$import->args], ['refaddr', 'blessed'], 'args list');
}

# multiple imports on one class
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Heavy');
    $cls->declare_import('strict');
    $cls->declare_import('warnings');
    $cls->declare_import('Scalar::Util', args => ['refaddr']);

    my @imports = $cls->imports;
    is(scalar @imports, 3, 'three imports declared');
    my @modules = map { $_->module } @imports;
    is_deeply(\@modules, ['strict', 'warnings', 'Scalar::Util'], 'imports in declaration order');
}

# imports on main class
{
    my $mop = Chalk::MOP->new;
    my $main = $mop->for_class('main');
    $main->declare_import('5.42.0');
    $main->declare_import('utf8');

    my @imports = $main->imports;
    is(scalar @imports, 2, 'main has two imports');
}

done_testing();

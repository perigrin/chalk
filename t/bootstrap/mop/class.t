# ABOUTME: Tests for Chalk::MOP::Class declare_* methods and direct-declared enumeration.
# ABOUTME: Verifies that declared metaobjects are returned by the correct list accessors.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Class accessors
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Point');

    is($cls->name, 'Point', 'name accessor');
    ok(!defined $cls->superclass, 'superclass defaults to undef');
    is(refaddr($cls->mop), refaddr($mop), 'mop accessor points back');
}

# Empty class has empty lists
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Empty');

    is(scalar($cls->fields), 0, 'no fields');
    is(scalar($cls->methods), 0, 'no methods');
    is(scalar($cls->subs), 0, 'no subs');
    is(scalar($cls->imports), 0, 'no imports');
    is(scalar($cls->adjust_blocks), 0, 'no adjust blocks');
}

# declare_field adds to fields()
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Fielded');
    my $f = $cls->declare_field('$x', sigil => '$');

    my @fields = $cls->fields;
    is(scalar @fields, 1, 'one field after declare_field');
    is(refaddr($fields[0]), refaddr($f), 'field is the one we declared');
}

# declare_method adds to methods()
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Methoded');
    my $m = $cls->declare_method('run');

    my @methods = $cls->methods;
    is(scalar @methods, 1, 'one method after declare_method');
    is(refaddr($methods[0]), refaddr($m), 'method is the one we declared');
}

# declare_sub adds to subs()
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Subbed');
    my $s = $cls->declare_sub('helper');

    my @subs = $cls->subs;
    is(scalar @subs, 1, 'one sub after declare_sub');
    is(refaddr($subs[0]), refaddr($s), 'sub is the one we declared');
}

# declare_import adds to imports()
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Imported');
    my $i = $cls->declare_import('strict');

    my @imports = $cls->imports;
    is(scalar @imports, 1, 'one import after declare_import');
    is(refaddr($imports[0]), refaddr($i), 'import is the one we declared');
}

# declare_adjust adds to adjust_blocks()
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Adjusted');
    my $a = $cls->declare_adjust();

    my @blocks = $cls->adjust_blocks;
    is(scalar @blocks, 1, 'one adjust block after declare_adjust');
    is(refaddr($blocks[0]), refaddr($a), 'adjust is the one we declared');
}

# Mixed declarations preserve independence
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Kitchen::Sink');

    $cls->declare_field('$x', sigil => '$');
    $cls->declare_field('$y', sigil => '$');
    $cls->declare_method('distance');
    $cls->declare_sub('_helper');
    $cls->declare_import('strict');
    $cls->declare_import('warnings');
    $cls->declare_adjust();

    is(scalar($cls->fields), 2, '2 fields');
    is(scalar($cls->methods), 1, '1 method');
    is(scalar($cls->subs), 1, '1 sub');
    is(scalar($cls->imports), 2, '2 imports');
    is(scalar($cls->adjust_blocks), 1, '1 adjust block');
}

# Direct-declared only — superclass contents not included
{
    my $mop = Chalk::MOP->new;
    my $base = $mop->declare_class('Base');
    $base->declare_method('base_method');
    $base->declare_field('$base_field', sigil => '$');

    my $derived = $mop->declare_class('Derived', superclass => $base);
    $derived->declare_method('derived_method');

    is(scalar($derived->methods), 1, 'derived has only its own method');
    is(scalar($derived->fields), 0, 'derived has no direct fields');
    is(($derived->methods)[0]->name, 'derived_method', 'correct method');
}

done_testing();

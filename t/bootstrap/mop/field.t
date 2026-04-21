# ABOUTME: Tests for Chalk::MOP::Field metaobject.
# ABOUTME: Verifies accessors: name, sigil, fieldix, param_name, has_default, attributes, class.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use Chalk::MOP;

# Basic field construction via declare_field
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Point');
    my $field = $cls->declare_field('$x', sigil => '$');

    isa_ok($field, 'Chalk::MOP::Field');
    is($field->name, '$x', 'field name includes sigil');
    is($field->sigil, '$', 'sigil accessor');
    is(refaddr($field->class), refaddr($cls), 'field class points back');
}

# fieldix tracks declaration order
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Record');
    my $f0 = $cls->declare_field('$a', sigil => '$');
    my $f1 = $cls->declare_field('$b', sigil => '$');
    my $f2 = $cls->declare_field('@items', sigil => '@');

    is($f0->fieldix, 0, 'first field has fieldix 0');
    is($f1->fieldix, 1, 'second field has fieldix 1');
    is($f2->fieldix, 2, 'third field has fieldix 2');
}

# param_name
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Widget');

    my $with_param = $cls->declare_field('$name', sigil => '$', param_name => 'name');
    my $without_param = $cls->declare_field('$cache', sigil => '$');

    is($with_param->param_name, 'name', 'param_name when set');
    ok(!defined $without_param->param_name, 'param_name undef when not set');
}

# has_default
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Config');

    my $with_default = $cls->declare_field('$timeout', sigil => '$', has_default => true);
    my $without_default = $cls->declare_field('$host', sigil => '$');

    is($with_default->has_default, true, 'has_default when set');
    is($without_default->has_default, false, 'has_default defaults to false');
}

# attributes
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Tagged');

    my $with_attrs = $cls->declare_field('$x',
        sigil      => '$',
        attributes => [':param', ':reader'],
    );
    my $without_attrs = $cls->declare_field('$y', sigil => '$');

    is_deeply([$with_attrs->attributes], [':param', ':reader'], 'attributes list');
    is_deeply([$without_attrs->attributes], [], 'attributes default to empty');
}

# different sigils
{
    my $mop = Chalk::MOP->new;
    my $cls = $mop->declare_class('Multi');

    my $scalar = $cls->declare_field('$x', sigil => '$');
    my $array  = $cls->declare_field('@items', sigil => '@');
    my $hash   = $cls->declare_field('%lookup', sigil => '%');

    is($scalar->sigil, '$', 'scalar sigil');
    is($array->sigil, '@', 'array sigil');
    is($hash->sigil, '%', 'hash sigil');
}

done_testing();

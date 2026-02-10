# ABOUTME: Tests FieldDecl and InterpolatedString IR node types for Tier B.
# ABOUTME: Validates constructor creation, hash consing, and input structure.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;

# ============================================================
# 1. Constructor:FieldDecl — name + attributes
# ============================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # Create supporting nodes
    my $name_const = $factory->make('Constant',
        const_type => 'string', value => '$const_type');
    my $attr_param = $factory->make('Constructor',
        class => '_Attribute', name => $name_const, parent => undef, body => undef);
    # Reuse name_const for attr value too — just need a second attribute
    my $reader_name = $factory->make('Constant',
        const_type => 'string', value => 'reader');
    my $attr_reader = $factory->make('Constructor',
        class => '_Attribute',
        name => $factory->make('Constant', const_type => 'string', value => 'reader'),
        parent => undef, body => undef);

    # Create FieldDecl
    my $field = $factory->make('Constructor',
        class      => 'FieldDecl',
        name       => $name_const,
        attributes => [$attr_param, $attr_reader],
    );

    ok(defined $field, 'FieldDecl: created');
    is($field->operation(), 'Constructor', 'FieldDecl: operation is Constructor');
    is($field->class(), 'FieldDecl', 'FieldDecl: class is FieldDecl');

    my $inputs = $field->inputs();
    is(ref $inputs, 'ARRAY', 'FieldDecl: inputs is arrayref');
    is(scalar $inputs->@*, 2, 'FieldDecl: has 2 inputs (name, attributes)');

    is($inputs->[0]->value(), '$const_type', 'FieldDecl: name is $const_type');
    is(ref $inputs->[1], 'ARRAY', 'FieldDecl: attributes is arrayref');
    is(scalar $inputs->[1]->@*, 2, 'FieldDecl: has 2 attributes');

    # Hash consing: same field should return same object
    my $field2 = $factory->make('Constructor',
        class      => 'FieldDecl',
        name       => $name_const,
        attributes => [$attr_param, $attr_reader],
    );
    is($field->id(), $field2->id(), 'FieldDecl: hash consing works');
}

# ============================================================
# 2. Constructor:InterpolatedString — parts array
# ============================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # "    $code\n" → [literal("    "), variable("$code"), literal("\n")]
    my $lit1 = $factory->make('Constant', const_type => 'string', value => '    ');
    my $var1 = $factory->make('Constant', const_type => 'variable', value => '$code');
    my $lit2 = $factory->make('Constant', const_type => 'string', value => "\n");

    my $interp = $factory->make('Constructor',
        class => 'InterpolatedString',
        parts => [$lit1, $var1, $lit2],
    );

    ok(defined $interp, 'InterpolatedString: created');
    is($interp->operation(), 'Constructor', 'InterpolatedString: operation');
    is($interp->class(), 'InterpolatedString', 'InterpolatedString: class');

    my $inputs = $interp->inputs();
    is(ref $inputs, 'ARRAY', 'InterpolatedString: inputs is arrayref');
    is(scalar $inputs->@*, 1, 'InterpolatedString: has 1 input (parts)');
    is(ref $inputs->[0], 'ARRAY', 'InterpolatedString: parts is arrayref');
    is(scalar $inputs->[0]->@*, 3, 'InterpolatedString: 3 parts');

    is($inputs->[0][0]->const_type(), 'string', 'InterpolatedString: part 0 is string');
    is($inputs->[0][0]->value(), '    ', 'InterpolatedString: part 0 value');
    is($inputs->[0][1]->const_type(), 'variable', 'InterpolatedString: part 1 is variable');
    is($inputs->[0][1]->value(), '$code', 'InterpolatedString: part 1 value');
    is($inputs->[0][2]->value(), "\n", 'InterpolatedString: part 2 value');

    # Hash consing
    my $interp2 = $factory->make('Constructor',
        class => 'InterpolatedString',
        parts => [$lit1, $var1, $lit2],
    );
    is($interp->id(), $interp2->id(), 'InterpolatedString: hash consing works');
}

# ============================================================
# 3. Multi-variable InterpolatedString
# ============================================================

{
    Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
    my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

    # "MODULE = $module  PACKAGE = $package\n\n"
    my @parts = (
        $factory->make('Constant', const_type => 'string', value => 'MODULE = '),
        $factory->make('Constant', const_type => 'variable', value => '$module'),
        $factory->make('Constant', const_type => 'string', value => '  PACKAGE = '),
        $factory->make('Constant', const_type => 'variable', value => '$package'),
        $factory->make('Constant', const_type => 'string', value => "\n\n"),
    );

    my $interp = $factory->make('Constructor',
        class => 'InterpolatedString',
        parts => \@parts,
    );

    ok(defined $interp, 'Multi-var InterpolatedString: created');
    is(scalar $interp->inputs()->[0]->@*, 5, 'Multi-var InterpolatedString: 5 parts');
}

done_testing();

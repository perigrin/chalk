# ABOUTME: Tests for Class type system foundation: TypeRegistry, Class, Maybe types
# ABOUTME: Tests forward references, auto-deepening, and nullable references
use 5.042;
use experimental qw(class);

use Test::More;
use lib 'lib';

# Test 1: TypeRegistry singleton
{
    use_ok('Chalk::Grammar::Chalk::TypeRegistry');

    my $registry1 = Chalk::Grammar::Chalk::TypeRegistry->instance();
    my $registry2 = Chalk::Grammar::Chalk::TypeRegistry->instance();

    is($registry1, $registry2, 'TypeRegistry is a singleton');
}

# Test 2: TypeRegistry basic registration and lookup
{
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Int;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();  # Clear for fresh test

    # Register a complete class
    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => { x => $int_type, y => $int_type }
    );

    ok(!$registry->has_class('Point'), 'Point not registered yet');
    $registry->register('Point', $point_class);
    ok($registry->has_class('Point'), 'Point is now registered');
    ok($registry->is_complete('Point'), 'Point is complete');

    my $looked_up = $registry->lookup('Point');
    is($looked_up, $point_class, 'lookup returns registered class');
}

# Test 3: TypeRegistry auto-creates placeholders
{
    use Chalk::Grammar::Chalk::TypeRegistry;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    ok(!$registry->has_class('Node'), 'Node not registered');

    # Lookup non-existent class should auto-create placeholder
    my $placeholder = $registry->lookup('Node');
    ok(defined($placeholder), 'lookup auto-creates placeholder');
    ok($registry->has_class('Node'), 'Node now registered as placeholder');
    ok(!$registry->is_complete('Node'), 'Node placeholder is incomplete');
    is($placeholder->class_name(), 'Node', 'placeholder has correct name');
    ok(!$placeholder->is_complete(), 'placeholder is incomplete');
}

# Test 4: TypeRegistry prevents redefinition of complete classes
{
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Int;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $class1 = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Foo',
        fields => { x => $int_type }
    );

    $registry->register('Foo', $class1);

    # Attempt to redefine complete class should die
    my $class2 = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Foo',
        fields => { y => $int_type }
    );

    eval { $registry->register('Foo', $class2); };
    like($@, qr/Cannot redefine complete class/, 'prevents redefinition of complete class');
}

# Test 5: Class type field access (complete classes)
{
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Int;
    use Chalk::Grammar::Chalk::Type::Str;

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $str_type = Chalk::Grammar::Chalk::Type::Str->new();

    my $person_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Person',
        fields => {
            name => $str_type,
            age => $int_type
        }
    );

    ok($person_class->is_complete(), 'Person class is complete');
    ok($person_class->has_field('name'), 'has_field detects name field');
    ok($person_class->has_field('age'), 'has_field detects age field');
    ok(!$person_class->has_field('address'), 'has_field returns false for missing field');

    is($person_class->field_type('name'), $str_type, 'field_type returns correct type for name');
    is($person_class->field_type('age'), $int_type, 'field_type returns correct type for age');

    eval { $person_class->field_type('address'); };
    like($@, qr/No field address/, 'field_type dies for missing field');
}

# Test 6: Class type placeholders cannot access fields directly
{
    use Chalk::Grammar::Chalk::Type::Class;

    my $placeholder = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => undef
    );

    ok(!$placeholder->is_complete(), 'placeholder is incomplete');
    ok(!$placeholder->has_field('val'), 'placeholder has_field returns false');
}

# Test 7: Auto-deepening resolves forward references
{
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Int;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Step 1: Create forward reference (placeholder)
    my $node_placeholder = $registry->lookup('Node');
    ok(!$node_placeholder->is_complete(), 'Node starts as placeholder');

    # Step 2: Register complete Node definition
    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $node_complete = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => { val => $int_type }
    );
    $registry->register('Node', $node_complete);

    # Step 3: Access field on old placeholder should auto-deepen
    ok($node_placeholder->has_field('val'), 'auto-deepening: has_field works on old placeholder');
    is($node_placeholder->field_type('val'), $int_type, 'auto-deepening: field_type works on old placeholder');
}

# Test 8: Class subtyping relationships
{
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Object;
    use Chalk::Grammar::Chalk::Type::Ref;
    use Chalk::Grammar::Chalk::Type::Scalar;
    use Chalk::Grammar::Chalk::Type::Any;
    use Chalk::Grammar::Chalk::Type::Int;

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $node_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => { val => $int_type }
    );

    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => { x => $int_type, y => $int_type }
    );

    my $object_type = Chalk::Grammar::Chalk::Type::Object->new();
    my $ref_type = Chalk::Grammar::Chalk::Type::Ref->new();
    my $scalar_type = Chalk::Grammar::Chalk::Type::Scalar->new();
    my $any_type = Chalk::Grammar::Chalk::Type::Any->new();

    # Class <: Class (reflexive)
    ok($node_class->is_subtype_of($node_class), 'Class <: Class (reflexive)');

    # Class <: Object <: Ref <: Scalar <: Any
    ok($node_class->is_subtype_of($object_type), 'Class <: Object');
    ok($node_class->is_subtype_of($ref_type), 'Class <: Ref');
    ok($node_class->is_subtype_of($scalar_type), 'Class <: Scalar');
    ok($node_class->is_subtype_of($any_type), 'Class <: Any');

    # Different classes are incompatible (nominal typing)
    ok(!$node_class->is_subtype_of($point_class), 'Node <!: Point (nominal typing)');
    ok(!$point_class->is_subtype_of($node_class), 'Point <!: Node (nominal typing)');
}

# Test 9: Maybe type basic operations
{
    use Chalk::Grammar::Chalk::Type::Maybe;
    use Chalk::Grammar::Chalk::Type::Int;
    use Chalk::Grammar::Chalk::Type::Class;

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $maybe_int = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $int_type);

    is($maybe_int->inner_type(), $int_type, 'Maybe wraps inner type');
    is($maybe_int->unwrap(), $int_type, 'unwrap returns inner type');
    is($maybe_int->name(), 'Maybe[Int]', 'Maybe name includes inner type');

    # Test with Class type
    my $node_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => { val => $int_type }
    );
    my $maybe_node = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $node_class);

    is($maybe_node->inner_type(), $node_class, 'Maybe wraps Class type');
    is($maybe_node->name(), 'Maybe[Class[Node]]', 'Maybe name with Class');
}

# Test 10: Maybe type subtyping
{
    use Chalk::Grammar::Chalk::Type::Maybe;
    use Chalk::Grammar::Chalk::Type::Int;
    use Chalk::Grammar::Chalk::Type::Num;
    use Chalk::Grammar::Chalk::Type::Str;
    use Chalk::Grammar::Chalk::Type::Undef;

    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $num_type = Chalk::Grammar::Chalk::Type::Num->new();
    my $str_type = Chalk::Grammar::Chalk::Type::Str->new();
    my $undef_type = Chalk::Grammar::Chalk::Type::Undef->new();

    my $maybe_int = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $int_type);
    my $maybe_num = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $num_type);
    my $maybe_str = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $str_type);

    # Maybe[T] <: Maybe[T] (reflexive)
    ok($maybe_int->is_subtype_of($maybe_int), 'Maybe[T] <: Maybe[T] reflexive');

    # Maybe[T] <: Maybe[U] if T <: U (covariant)
    # Int <: Num, so Maybe[Int] <: Maybe[Num]
    ok($maybe_int->is_subtype_of($maybe_num), 'Maybe[Int] <: Maybe[Num] covariance');

    # But not the reverse
    ok(!$maybe_num->is_subtype_of($maybe_int), 'Maybe[Num] <!: Maybe[Int]');

    # Incompatible inner types (use Class types which use nominal typing)
    use Chalk::Grammar::Chalk::Type::Class;
    my $node_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Node',
        fields => {}
    );
    my $point_class = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Point',
        fields => {}
    );
    my $maybe_node = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $node_class);
    my $maybe_point = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $point_class);

    ok(!$maybe_node->is_subtype_of($maybe_point), 'Maybe[Node] <!: Maybe[Point] with incompatible classes');

    # Maybe[T] <: Undef (can be undef)
    ok($maybe_int->is_subtype_of($undef_type), 'Maybe[T] <: Undef');
}

# Test 11: Integration - Self-referential linked list
{
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Maybe;
    use Chalk::Grammar::Chalk::Type::Int;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Define LinkedList: { val: Int, next: Maybe(LinkedList) }
    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();

    # Step 1: Forward reference for self-reference
    my $list_ref = $registry->lookup('LinkedList');  # Creates placeholder

    # Step 2: Create Maybe(LinkedList) using placeholder
    my $maybe_list = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $list_ref);

    # Step 3: Register complete LinkedList definition
    my $list_complete = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'LinkedList',
        fields => {
            val => $int_type,
            next => $maybe_list
        }
    );
    $registry->register('LinkedList', $list_complete);

    # Step 4: Verify structure
    ok($registry->is_complete('LinkedList'), 'LinkedList is complete');
    ok($list_ref->has_field('val'), 'LinkedList has val field (auto-deepening)');
    ok($list_ref->has_field('next'), 'LinkedList has next field (auto-deepening)');

    my $next_type = $list_ref->field_type('next');
    is(ref($next_type), 'Chalk::Grammar::Chalk::Type::Maybe', 'next field is Maybe type');
    is($next_type->unwrap()->class_name(), 'LinkedList', 'next wraps LinkedList (self-reference works)');
}

# Test 12: Integration - Self-referential binary tree
{
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Maybe;
    use Chalk::Grammar::Chalk::Type::Int;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Define TreeNode: { val: Int, left: Maybe(TreeNode), right: Maybe(TreeNode) }
    my $int_type = Chalk::Grammar::Chalk::Type::Int->new();
    my $tree_ref = $registry->lookup('TreeNode');

    my $maybe_tree = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $tree_ref);

    my $tree_complete = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'TreeNode',
        fields => {
            val => $int_type,
            left => $maybe_tree,
            right => $maybe_tree
        }
    );
    $registry->register('TreeNode', $tree_complete);

    ok($registry->is_complete('TreeNode'), 'TreeNode is complete');
    ok($tree_ref->has_field('left'), 'TreeNode has left field');
    ok($tree_ref->has_field('right'), 'TreeNode has right field');

    my $left_type = $tree_ref->field_type('left');
    my $right_type = $tree_ref->field_type('right');
    is($left_type->unwrap()->class_name(), 'TreeNode', 'left wraps TreeNode');
    is($right_type->unwrap()->class_name(), 'TreeNode', 'right wraps TreeNode');
}

# Test 13: Integration - Mutually recursive classes
{
    use Chalk::Grammar::Chalk::TypeRegistry;
    use Chalk::Grammar::Chalk::Type::Class;
    use Chalk::Grammar::Chalk::Type::Maybe;
    use Chalk::Grammar::Chalk::Type::Int;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Define mutually recursive: Person -> Company -> Person
    # Person: { name: Str, employer: Maybe(Company) }
    # Company: { name: Str, ceo: Maybe(Person) }

    use Chalk::Grammar::Chalk::Type::Str;
    my $str_type = Chalk::Grammar::Chalk::Type::Str->new();

    # Create forward references
    my $person_ref = $registry->lookup('Person');
    my $company_ref = $registry->lookup('Company');

    # Define Person with Maybe(Company)
    my $maybe_company = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $company_ref);
    my $person_complete = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Person',
        fields => {
            name => $str_type,
            employer => $maybe_company
        }
    );
    $registry->register('Person', $person_complete);

    # Define Company with Maybe(Person)
    my $maybe_person = Chalk::Grammar::Chalk::Type::Maybe->new(inner_type => $person_ref);
    my $company_complete = Chalk::Grammar::Chalk::Type::Class->new(
        class_name => 'Company',
        fields => {
            name => $str_type,
            ceo => $maybe_person
        }
    );
    $registry->register('Company', $company_complete);

    # Verify mutual references work via auto-deepening
    ok($person_ref->has_field('employer'), 'Person has employer field');
    ok($company_ref->has_field('ceo'), 'Company has ceo field');

    my $employer_type = $person_ref->field_type('employer');
    is($employer_type->unwrap()->class_name(), 'Company', 'Person.employer is Company');

    my $ceo_type = $company_ref->field_type('ceo');
    is($ceo_type->unwrap()->class_name(), 'Person', 'Company.ceo is Person');
}

done_testing();

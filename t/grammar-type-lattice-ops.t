#!/usr/bin/env perl
# ABOUTME: Tests for meet() and join() lattice operations on Grammar Type classes
# ABOUTME: Verifies greatest lower bound (meet) and least upper bound (join) for type inference

use 5.42.0;
use utf8;
use Test::More;
use experimental qw(class);

# Load all type classes
use Chalk::Grammar::Chalk::Type;
use Chalk::Grammar::Chalk::Type::Any;
use Chalk::Grammar::Chalk::Type::None;
use Chalk::Grammar::Chalk::Type::Scalar;
use Chalk::Grammar::Chalk::Type::Str;
use Chalk::Grammar::Chalk::Type::Num;
use Chalk::Grammar::Chalk::Type::Int;
use Chalk::Grammar::Chalk::Type::Boolean;
use Chalk::Grammar::Chalk::Type::Undef;
use Chalk::Grammar::Chalk::Type::Array;
use Chalk::Grammar::Chalk::Type::Hash;
use Chalk::Grammar::Chalk::Type::List;
use Chalk::Grammar::Chalk::Type::Ref;

# Create singleton-like instances for testing
my $any     = Chalk::Grammar::Chalk::Type::Any->new();
my $none    = Chalk::Grammar::Chalk::Type::None->new();
my $scalar  = Chalk::Grammar::Chalk::Type::Scalar->new();
my $str     = Chalk::Grammar::Chalk::Type::Str->new();
my $num     = Chalk::Grammar::Chalk::Type::Num->new();
my $int     = Chalk::Grammar::Chalk::Type::Int->new();
my $bool    = Chalk::Grammar::Chalk::Type::Boolean->new();
my $undef   = Chalk::Grammar::Chalk::Type::Undef->new();
my $array   = Chalk::Grammar::Chalk::Type::Array->new(element_type => $any);
my $hash    = Chalk::Grammar::Chalk::Type::Hash->new(value_type => $any);
my $list    = Chalk::Grammar::Chalk::Type::List->new();
my $ref     = Chalk::Grammar::Chalk::Type::Ref->new();

# ============================================================
# meet() tests - Greatest Lower Bound (intersection/infimum)
# ============================================================

subtest 'meet() with Any (top type)' => sub {
    # Any is identity for meet
    is($any->meet($any)->name(), 'Any', 'meet(Any, Any) = Any');
    is($any->meet($int)->name(), 'Int', 'meet(Any, Int) = Int');
    is($any->meet($none)->name(), 'None', 'meet(Any, None) = None');
    is($int->meet($any)->name(), 'Int', 'meet(Int, Any) = Int');
};

subtest 'meet() with None (bottom type)' => sub {
    # None absorbs everything in meet
    is($none->meet($any)->name(), 'None', 'meet(None, Any) = None');
    is($none->meet($int)->name(), 'None', 'meet(None, Int) = None');
    is($none->meet($none)->name(), 'None', 'meet(None, None) = None');
    is($int->meet($none)->name(), 'None', 'meet(Int, None) = None');
};

subtest 'meet() within Scalar hierarchy' => sub {
    # Int <: Num <: Str <: Scalar hierarchy
    # meet finds the most specific common subtype

    # Same type
    is($int->meet($int)->name(), 'Int', 'meet(Int, Int) = Int');
    is($num->meet($num)->name(), 'Num', 'meet(Num, Num) = Num');
    is($str->meet($str)->name(), 'Str', 'meet(Str, Str) = Str');

    # Int and Num: Int is subtype of Num, so meet = Int
    is($int->meet($num)->name(), 'Int', 'meet(Int, Num) = Int');
    is($num->meet($int)->name(), 'Int', 'meet(Num, Int) = Int');

    # Int and Str: Int is subtype of Str, so meet = Int
    is($int->meet($str)->name(), 'Int', 'meet(Int, Str) = Int');
    is($str->meet($int)->name(), 'Int', 'meet(Str, Int) = Int');

    # Num and Str: Num is subtype of Str, so meet = Num
    is($num->meet($str)->name(), 'Num', 'meet(Num, Str) = Num');
    is($str->meet($num)->name(), 'Num', 'meet(Str, Num) = Num');

    # Scalar with subtypes
    is($scalar->meet($int)->name(), 'Int', 'meet(Scalar, Int) = Int');
    is($scalar->meet($str)->name(), 'Str', 'meet(Scalar, Str) = Str');
};

subtest 'meet() across incompatible types' => sub {
    # Boolean and Int are both under Scalar but different branches
    is($int->meet($bool)->name(), 'None', 'meet(Int, Boolean) = None');
    is($bool->meet($int)->name(), 'None', 'meet(Boolean, Int) = None');

    # Undef and Int
    is($undef->meet($int)->name(), 'None', 'meet(Undef, Int) = None');
    is($int->meet($undef)->name(), 'None', 'meet(Int, Undef) = None');

    # Array and Hash
    is($array->meet($hash)->name(), 'None', 'meet(Array, Hash) = None');
    is($hash->meet($array)->name(), 'None', 'meet(Hash, Array) = None');

    # Scalar and List branches
    is($int->meet($array)->name(), 'None', 'meet(Int, Array) = None');
    is($array->meet($int)->name(), 'None', 'meet(Array, Int) = None');
};

subtest 'meet() with parameterized types' => sub {
    my $int_array = Chalk::Grammar::Chalk::Type::Array->new(element_type => $int);
    my $num_array = Chalk::Grammar::Chalk::Type::Array->new(element_type => $num);

    # Same array type
    my $result = $int_array->meet($int_array);
    is($result->name(), 'Array', 'meet(Array[Int], Array[Int]) = Array');
    is($result->element_type->name(), 'Int', 'element type preserved');

    # Covariant element types: Array[Int] and Array[Num]
    # meet should give Array[Int] (more specific element type)
    $result = $int_array->meet($num_array);
    is($result->name(), 'Array', 'meet(Array[Int], Array[Num]) = Array');
    is($result->element_type->name(), 'Int', 'element type is Int (more specific)');
};

# ============================================================
# join() tests - Least Upper Bound (union/supremum)
# ============================================================

subtest 'join() with Any (top type)' => sub {
    # Any absorbs everything in join
    is($any->join($any)->name(), 'Any', 'join(Any, Any) = Any');
    is($any->join($int)->name(), 'Any', 'join(Any, Int) = Any');
    is($any->join($none)->name(), 'Any', 'join(Any, None) = Any');
    is($int->join($any)->name(), 'Any', 'join(Int, Any) = Any');
};

subtest 'join() with None (bottom type)' => sub {
    # None is identity for join
    is($none->join($any)->name(), 'Any', 'join(None, Any) = Any');
    is($none->join($int)->name(), 'Int', 'join(None, Int) = Int');
    is($none->join($none)->name(), 'None', 'join(None, None) = None');
    is($int->join($none)->name(), 'Int', 'join(Int, None) = Int');
};

subtest 'join() within Scalar hierarchy' => sub {
    # Int <: Num <: Str <: Scalar hierarchy
    # join finds the most general common supertype

    # Same type
    is($int->join($int)->name(), 'Int', 'join(Int, Int) = Int');
    is($num->join($num)->name(), 'Num', 'join(Num, Num) = Num');
    is($str->join($str)->name(), 'Str', 'join(Str, Str) = Str');

    # Int and Num: Num is supertype of Int, so join = Num
    is($int->join($num)->name(), 'Num', 'join(Int, Num) = Num');
    is($num->join($int)->name(), 'Num', 'join(Num, Int) = Num');

    # Int and Str: Str is supertype of Int, so join = Str
    is($int->join($str)->name(), 'Str', 'join(Int, Str) = Str');
    is($str->join($int)->name(), 'Str', 'join(Str, Int) = Str');

    # Num and Str: Str is supertype of Num, so join = Str
    is($num->join($str)->name(), 'Str', 'join(Num, Str) = Str');
    is($str->join($num)->name(), 'Str', 'join(Str, Num) = Str');

    # Scalar with subtypes
    is($scalar->join($int)->name(), 'Scalar', 'join(Scalar, Int) = Scalar');
    is($scalar->join($str)->name(), 'Scalar', 'join(Scalar, Str) = Scalar');
};

subtest 'join() across incompatible types' => sub {
    # Boolean and Int are both under Scalar - join is Scalar
    is($int->join($bool)->name(), 'Scalar', 'join(Int, Boolean) = Scalar');
    is($bool->join($int)->name(), 'Scalar', 'join(Boolean, Int) = Scalar');

    # Undef and Int - both under Scalar
    is($undef->join($int)->name(), 'Scalar', 'join(Undef, Int) = Scalar');
    is($int->join($undef)->name(), 'Scalar', 'join(Int, Undef) = Scalar');

    # Array and Hash - both under List
    is($array->join($hash)->name(), 'List', 'join(Array, Hash) = List');
    is($hash->join($array)->name(), 'List', 'join(Hash, Array) = List');

    # Scalar and List branches - join is Any
    is($int->join($array)->name(), 'Any', 'join(Int, Array) = Any');
    is($array->join($int)->name(), 'Any', 'join(Array, Int) = Any');
};

subtest 'join() with parameterized types' => sub {
    my $int_array = Chalk::Grammar::Chalk::Type::Array->new(element_type => $int);
    my $num_array = Chalk::Grammar::Chalk::Type::Array->new(element_type => $num);

    # Same array type
    my $result = $int_array->join($int_array);
    is($result->name(), 'Array', 'join(Array[Int], Array[Int]) = Array');
    is($result->element_type->name(), 'Int', 'element type preserved');

    # Covariant element types: Array[Int] and Array[Num]
    # join should give Array[Num] (less specific element type)
    $result = $int_array->join($num_array);
    is($result->name(), 'Array', 'join(Array[Int], Array[Num]) = Array');
    is($result->element_type->name(), 'Num', 'element type is Num (less specific)');
};

# ============================================================
# Lattice properties tests
# ============================================================

subtest 'meet() commutativity' => sub {
    # meet(A, B) = meet(B, A)
    is($int->meet($num)->name(), $num->meet($int)->name(), 'meet(Int, Num) commutes');
    is($int->meet($bool)->name(), $bool->meet($int)->name(), 'meet(Int, Boolean) commutes');
    is($array->meet($hash)->name(), $hash->meet($array)->name(), 'meet(Array, Hash) commutes');
    is($any->meet($int)->name(), $int->meet($any)->name(), 'meet(Any, Int) commutes');
    is($none->meet($int)->name(), $int->meet($none)->name(), 'meet(None, Int) commutes');
};

subtest 'join() commutativity' => sub {
    # join(A, B) = join(B, A)
    is($int->join($num)->name(), $num->join($int)->name(), 'join(Int, Num) commutes');
    is($int->join($bool)->name(), $bool->join($int)->name(), 'join(Int, Boolean) commutes');
    is($array->join($hash)->name(), $hash->join($array)->name(), 'join(Array, Hash) commutes');
    is($any->join($int)->name(), $int->join($any)->name(), 'join(Any, Int) commutes');
    is($none->join($int)->name(), $int->join($none)->name(), 'join(None, Int) commutes');
};

subtest 'meet() idempotence' => sub {
    # meet(A, A) = A
    is($int->meet($int)->name(), 'Int', 'meet(Int, Int) = Int');
    is($any->meet($any)->name(), 'Any', 'meet(Any, Any) = Any');
    is($none->meet($none)->name(), 'None', 'meet(None, None) = None');
    is($array->meet($array)->name(), 'Array', 'meet(Array, Array) = Array');
};

subtest 'join() idempotence' => sub {
    # join(A, A) = A
    is($int->join($int)->name(), 'Int', 'join(Int, Int) = Int');
    is($any->join($any)->name(), 'Any', 'join(Any, Any) = Any');
    is($none->join($none)->name(), 'None', 'join(None, None) = None');
    is($array->join($array)->name(), 'Array', 'join(Array, Array) = Array');
};

subtest 'meet/join absorption' => sub {
    # meet(A, join(A, B)) = A
    my $join_int_num = $int->join($num);
    is($int->meet($join_int_num)->name(), 'Int', 'meet(Int, join(Int, Num)) = Int');

    # join(A, meet(A, B)) = A
    my $meet_int_num = $int->meet($num);
    is($int->join($meet_int_num)->name(), 'Int', 'join(Int, meet(Int, Num)) = Int');
};

subtest 'meet() associativity' => sub {
    # meet(meet(A, B), C) = meet(A, meet(B, C))
    my $left = $int->meet($num)->meet($str);
    my $right = $int->meet($num->meet($str));
    is($left->name(), $right->name(), 'meet is associative for Int, Num, Str');
};

subtest 'join() associativity' => sub {
    # join(join(A, B), C) = join(A, join(B, C))
    my $left = $int->join($num)->join($str);
    my $right = $int->join($num->join($str));
    is($left->name(), $right->name(), 'join is associative for Int, Num, Str');
};

subtest 'distributivity' => sub {
    # meet(A, join(B, C)) = join(meet(A, B), meet(A, C))
    # Distributivity of meet over join
    my $left_meet_dist = $int->meet($num->join($bool));
    my $right_meet_dist = ($int->meet($num))->join($int->meet($bool));
    is($left_meet_dist->name(), $right_meet_dist->name(),
       'meet(Int, join(Num, Boolean)) = join(meet(Int, Num), meet(Int, Boolean))');

    # join(A, meet(B, C)) = meet(join(A, B), join(A, C))
    # Distributivity of join over meet
    my $left_join_dist = $int->join($num->meet($str));
    my $right_join_dist = ($int->join($num))->meet($int->join($str));
    is($left_join_dist->name(), $right_join_dist->name(),
       'join(Int, meet(Num, Str)) = meet(join(Int, Num), join(Int, Str))');

    # Additional distributivity test with different types
    my $left_dist2 = $scalar->meet($int->join($bool));
    my $right_dist2 = ($scalar->meet($int))->join($scalar->meet($bool));
    is($left_dist2->name(), $right_dist2->name(),
       'meet(Scalar, join(Int, Boolean)) = join(meet(Scalar, Int), meet(Scalar, Boolean))');
};

# ============================================================
# TypeLattice helper method tests
# ============================================================

subtest 'TypeLattice helper methods' => sub {
    use Chalk::Grammar::Chalk::TypeLattice;
    my $lattice = Chalk::Grammar::Chalk::TypeLattice->new();

    # Test meet() helper
    is($lattice->meet($int, $num)->name(), 'Int', 'TypeLattice->meet(Int, Num) = Int');

    # Test join() helper
    is($lattice->join($int, $num)->name(), 'Num', 'TypeLattice->join(Int, Num) = Num');

    # Test meet_all() helper
    my $meet_result = $lattice->meet_all($int, $num, $str);
    is($meet_result->name(), 'Int', 'TypeLattice->meet_all(Int, Num, Str) = Int');

    # Test join_all() helper
    my $join_result = $lattice->join_all($int, $num, $str);
    is($join_result->name(), 'Str', 'TypeLattice->join_all(Int, Num, Str) = Str');

    # Test are_compatible() helper
    ok($lattice->are_compatible($int, $num), 'Int and Num are compatible');
    ok(!$lattice->are_compatible($int, $bool), 'Int and Boolean are not compatible');

    # Test top_type() and bottom_type() helpers
    ok($lattice->top_type()->is_top(), 'top_type() returns top');
    ok($lattice->bottom_type()->is_bottom(), 'bottom_type() returns bottom');

    # Test empty arrays
    ok($lattice->meet_all()->is_top(), 'meet_all() with no args returns Any');
    ok($lattice->join_all()->is_bottom(), 'join_all() with no args returns None');
};

done_testing();

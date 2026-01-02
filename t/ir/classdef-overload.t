# ABOUTME: Tests for ClassDef IR node overload_mappings field
# ABOUTME: Verifies ClassDef accepts and stores operator-to-method mappings for XS generation

use v5.42;
use Test::More;
use FindBin qw($RealBin);

use lib "$RealBin/../../lib";
use Scalar::Util 'blessed', 'refaddr';

subtest 'ClassDef with overload_mappings' => sub {
    require Chalk::IR::Node::ClassDef;

    my $overload_map = {
        '""'  => 'value',
        'eq'  => '_string_eq',
        'cmp' => '_string_cmp',
    };

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name        => 'Token',
        overload_mappings => $overload_map,
    );

    ok(defined($classdef), 'ClassDef with overload_mappings is defined');
    is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings returns hash');
    is_deeply($classdef->overload_mappings, $overload_map, 'overload_mappings accessor works');
};

subtest 'ClassDef overload_mappings defaults to empty hash' => sub {
    require Chalk::IR::Node::ClassDef;

    my $classdef = Chalk::IR::Node::ClassDef->new(
        class_name => 'Simple',
    );

    is(ref($classdef->overload_mappings), 'HASH', 'overload_mappings defaults to hash');
    is(scalar(keys %{$classdef->overload_mappings}), 0, 'default overload_mappings is empty');
};

done_testing();

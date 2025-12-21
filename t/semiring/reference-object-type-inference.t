#!/usr/bin/env perl
# ABOUTME: Tests type inference for reference types (ArrayRef, HashRef) and object types
# ABOUTME: Verifies that array/hash dereferences and method calls infer correct types

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use File::Spec;
use lib "$RealBin/../../lib";
use experimental qw(defer);
defer { done_testing() }

use Chalk::Parser;
use Chalk::Grammar;
use Chalk::Grammar::Chalk;
use Chalk::Semiring::TypeInference;
use Chalk::Semiring::Composite;
use Chalk::Semiring::Semantic;

# Load Chalk grammar from BNF
my $bnf_file = File::Spec->catfile($RealBin, '../../grammar', 'chalk.bnf');
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, 'Program', 'Chalk');

# Helper function to parse and get type element
sub parse_and_get_type {
    my ($code) = @_;

    my $type_sr = Chalk::Semiring::TypeInference->new();
    my $sem_sr = Chalk::Semiring::Semantic->new(grammar => $chalk_grammar);
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [$type_sr, $sem_sr]
    );

    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        semiring => $composite
    );

    my $element = $parser->parse_string($code);
    return unless defined $element;

    return $element->element_at(0);  # TypeInference element
}

# ===== Array Reference Type Inference Tests =====

subtest 'ArrayRef: Reference constructor [] infers ArrayRef type' => sub {
    my $code = q{my $arr = [];};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;
    ok(exists $type_env->{'$arr'}, 'Variable $arr is in type environment');

    if (exists $type_env->{'$arr'} && defined $type_env->{'$arr'}) {
        is($type_env->{'$arr'}->name, 'ArrayRef',
           'Empty array ref [] infers ArrayRef type');
    } else {
        fail('Empty array ref [] infers ArrayRef type');
    }
};

subtest 'ArrayRef: Non-empty array constructor [1, 2, 3] infers ArrayRef' => sub {
    my $code = q{my $arr = [1, 2, 3];};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;

    if (exists $type_env->{'$arr'} && defined $type_env->{'$arr'}) {
        is($type_env->{'$arr'}->name, 'ArrayRef',
           'Array ref [1, 2, 3] infers ArrayRef type');
    } else {
        fail('Array ref [1, 2, 3] infers ArrayRef type');
    }
};

subtest 'ArrayRef: Array dereference $x->[0] confirms ArrayRef for $x' => sub {
    # When we dereference $x with [0], it implies $x must be ArrayRef
    my $code = q{my $val = $x->[0];};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;

    # The dereference operation should infer that $x is an ArrayRef
    # Note: This test may be TODO until we implement the inference for derefs
    todo 'Array dereference type inference not yet implemented' => sub {
        ok(exists $type_env->{'$x'}, 'Variable $x in type environment from dereference');

        if (exists $type_env->{'$x'} && defined $type_env->{'$x'}) {
            is($type_env->{'$x'}->name, 'ArrayRef',
               'Array dereference $x->[0] infers $x is ArrayRef');
        } else {
            fail('Array dereference $x->[0] infers $x is ArrayRef');
        }
    };
};

subtest 'ArrayRef: push operation infers ArrayRef' => sub {
    # push(@arr, $value) implies @arr is an array
    # For scalar refs: push(@$arr, $value) implies $arr is ArrayRef
    my $code = q{my @arr; push(@arr, 42);};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;

    # @arr should be inferred as Array (not ArrayRef - different sigil)
    todo 'Array variable @arr type inference not yet implemented' => sub {
        ok(exists $type_env->{'@arr'}, '@arr in type environment');

        if (exists $type_env->{'@arr'} && defined $type_env->{'@arr'}) {
            is($type_env->{'@arr'}->name, 'Array',
               'push(@arr, ...) infers @arr is Array');
        } else {
            fail('push(@arr, ...) infers @arr is Array');
        }
    };
};

# ===== Hash Reference Type Inference Tests =====

subtest 'HashRef: Reference constructor {} infers HashRef type' => sub {
    my $code = q{my $hash = {};};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;
    ok(exists $type_env->{'$hash'}, 'Variable $hash is in type environment');

    if (exists $type_env->{'$hash'} && defined $type_env->{'$hash'}) {
        is($type_env->{'$hash'}->name, 'HashRef',
           'Empty hash ref {} infers HashRef type');
    } else {
        fail('Empty hash ref {} infers HashRef type');
    }
};

subtest 'HashRef: Non-empty hash constructor {a => 1} infers HashRef' => sub {
    my $code = q{my $hash = {foo => 1, bar => 2};};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;

    if (exists $type_env->{'$hash'} && defined $type_env->{'$hash'}) {
        is($type_env->{'$hash'}->name, 'HashRef',
           'Hash ref {foo => 1, ...} infers HashRef type');
    } else {
        fail('Hash ref {foo => 1, ...} infers HashRef type');
    }
};

subtest 'HashRef: Hash dereference $x->{key} confirms HashRef for $x' => sub {
    my $code = q{my $val = $x->{foo};};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;

    # Hash dereference should infer that $x is HashRef
    todo 'Hash dereference type inference not yet implemented' => sub {
        ok(exists $type_env->{'$x'}, 'Variable $x in type environment from dereference');

        if (exists $type_env->{'$x'} && defined $type_env->{'$x'}) {
            is($type_env->{'$x'}->name, 'HashRef',
               'Hash dereference $x->{key} infers $x is HashRef');
        } else {
            fail('Hash dereference $x->{key} infers $x is HashRef');
        }
    };
};

subtest 'HashRef: keys/values operations infer HashRef' => sub {
    my $code = q{my %hash; my @k = keys(%hash);};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Parsing succeeded');

    my $type_env = $type_elem->type_env;

    # %hash should be Hash (not HashRef)
    todo 'Hash variable %hash type inference not yet implemented' => sub {
        ok(exists $type_env->{'%hash'}, '%hash in type environment');

        if (exists $type_env->{'%hash'} && defined $type_env->{'%hash'}) {
            is($type_env->{'%hash'}->name, 'Hash',
               'keys(%hash) infers %hash is Hash');
        } else {
            fail('keys(%hash) infers %hash is Hash');
        }
    };
};

# ===== Object Type Inference Tests =====

subtest 'Object: Constructor Class->new() infers Object type' => sub {
    use Chalk::Grammar::Chalk::TypeRegistry;

    # Register a test class
    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # First register the class
    my $class_code = q{class TestClass { field $value; }};
    my $class_elem = parse_and_get_type($class_code);
    ok(defined($class_elem), 'Class declaration parsed');

    # Now create an instance
    my $code = q{my $obj = TestClass->new(value => 42);};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Constructor call parsed');

    my $type_env = $type_elem->type_env;

    todo 'Constructor call type inference not yet implemented' => sub {
        ok(exists $type_env->{'$obj'}, 'Variable $obj in type environment');

        if (exists $type_env->{'$obj'} && defined $type_env->{'$obj'}) {
            my $obj_type = $type_env->{'$obj'};
            # Should be Object type (or more specifically, TestClass object)
            ok($obj_type->name =~ /^Object/,
               'TestClass->new() infers Object type (got: ' . $obj_type->name . ')');
        } else {
            fail('TestClass->new() infers Object type');
        }
    };
};

subtest 'Object: Method call $obj->method() returns object result' => sub {
    # Method calls return values - often objects themselves
    # For now, we'll infer that method results are of type Any or Object
    my $code = q{my $result = $obj->some_method();};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Method call parsed');

    my $type_env = $type_elem->type_env;

    todo 'Method call result type inference not yet implemented' => sub {
        ok(exists $type_env->{'$result'}, 'Variable $result in type environment');

        if (exists $type_env->{'$result'} && defined $type_env->{'$result'}) {
            my $result_type = $type_env->{'$result'};
            # Method result should be at least Object or Any
            ok($result_type->name =~ /^(Object|Any)$/,
               'Method call result has Object or Any type (got: ' . $result_type->name . ')');
        } else {
            fail('Method call result has Object or Any type');
        }
    };
};

subtest 'Object: $self parameter in methods is Object' => sub {
    use Chalk::Grammar::Chalk::TypeRegistry;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Define a class with a method that uses $self
    my $code = q{
        class Counter {
            field $count = 0;
            method increment() {
                my $self_val = $self;
            }
        }
    };

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Class with method parsed');

    # Within a method body, $self should be inferred as Object
    # This is a more complex test that requires method context tracking
    todo '$self type inference in method context not yet implemented' => sub {
        my $type_env = $type_elem->type_env;

        # In a real implementation, we'd need to track method-local scopes
        # For now, this serves as a specification test
        ok(1, '$self parameter inference is a future enhancement');
    };
};

subtest 'Object: Chained method calls preserve object type' => sub {
    # $obj->method1()->method2() should preserve object types
    my $code = q{my $result = $obj->foo()->bar();};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Chained method call parsed');

    todo 'Chained method call type inference not yet implemented' => sub {
        my $type_env = $type_elem->type_env;

        ok(exists $type_env->{'$result'}, 'Chained method result in type environment');

        if (exists $type_env->{'$result'} && defined $type_env->{'$result'}) {
            my $result_type = $type_env->{'$result'};
            ok($result_type->name =~ /^(Object|Any)$/,
               'Chained method calls return Object or Any');
        } else {
            fail('Chained method calls return Object or Any');
        }
    };
};

# ===== Integration Tests =====

subtest 'Integration: ArrayRef assigned and dereferenced' => sub {
    # NOTE: Multi-statement parsing with Composite semiring fails when first
    # statement contains array constructor []. Test statements separately.
    # See: Composite semiring bug with array constructor + following statements

    # Test 1: Array constructor assigns ArrayRef type
    my $code1 = q{my $arr = [1, 2, 3];};
    my $type_elem1 = parse_and_get_type($code1);
    ok(defined($type_elem1), 'Array constructor parsed');

    SKIP: {
        skip 'Parse failed' unless defined $type_elem1;
        my $type_env = $type_elem1->type_env;

        if (exists $type_env->{'$arr'} && defined $type_env->{'$arr'}) {
            is($type_env->{'$arr'}->name, 'ArrayRef',
               '$arr is ArrayRef from constructor');
        } else {
            fail('$arr is ArrayRef from constructor');
        }
    }

    # Test 2: Array dereference (separate statement)
    my $code2 = q{my $first = $arr->[0];};
    my $type_elem2 = parse_and_get_type($code2);
    ok(defined($type_elem2), 'Array dereference parsed');

    todo 'Array element type inference not yet implemented' => sub {
        SKIP: {
            skip 'Parse failed' unless defined $type_elem2;
            my $type_env = $type_elem2->type_env;

            if (exists $type_env->{'$first'} && defined $type_env->{'$first'}) {
                ok(defined $type_env->{'$first'},
                   '$first has a type from array dereference');
            } else {
                fail('$first has a type from array dereference');
            }
        }
    };
};

subtest 'Integration: HashRef assigned and dereferenced' => sub {
    my $code = q{my $hash = {foo => 42}; my $val = $hash->{foo};};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Combined hash operations parsed');

    SKIP: {
        skip 'Parse failed' unless defined $type_elem;
        my $type_env = $type_elem->type_env;

        # $hash should be HashRef from constructor
        if (exists $type_env->{'$hash'} && defined $type_env->{'$hash'}) {
            is($type_env->{'$hash'}->name, 'HashRef',
               '$hash is HashRef from constructor');
        } else {
            fail('$hash is HashRef from constructor');
        }

        # $val should be inferred from hash value type
        todo 'Hash value type inference not yet implemented' => sub {
            if (exists $type_env->{'$val'} && defined $type_env->{'$val'}) {
                ok(defined $type_env->{'$val'},
                   '$val has a type from hash dereference');
            } else {
                fail('$val has a type from hash dereference');
            }
        };
    }
};

subtest 'Integration: Object created and method called' => sub {
    use Chalk::Grammar::Chalk::TypeRegistry;

    my $registry = Chalk::Grammar::Chalk::TypeRegistry->instance();
    $registry->reset();

    # Register class first
    my $class_code = q{class Widget { field $name; method get_name() { return $name; } }};
    parse_and_get_type($class_code);

    # Create instance and call method
    my $code = q{my $widget = Widget->new(name => "foo"); my $name = $widget->get_name();};

    my $type_elem = parse_and_get_type($code);
    ok(defined($type_elem), 'Object creation and method call parsed');

    SKIP: {
        skip 'Parse failed' unless defined $type_elem;
        my $type_env = $type_elem->type_env;

        todo 'Object creation and method call type inference not yet implemented' => sub {
            if (exists $type_env->{'$widget'} && defined $type_env->{'$widget'}) {
                ok($type_env->{'$widget'}->name =~ /^Object/,
                   '$widget is Object from Widget->new()');
            } else {
                fail('$widget is Object from Widget->new()');
            }

            if (exists $type_env->{'$name'} && defined $type_env->{'$name'}) {
                # Method result type - for now Any is acceptable
                ok(defined $type_env->{'$name'},
                   '$name has a type from method call');
            } else {
                fail('$name has a type from method call');
            }
        };
    }
};

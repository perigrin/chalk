# ABOUTME: Unit tests for the Target base class (code generation abstraction).
# ABOUTME: Verifies Target loads, constructs, and enforces abstract generate() contract.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

# Test 1: Module loads
use_ok('Chalk::Bootstrap::Target');

# Test 2: Can construct
my $target = Chalk::Bootstrap::Target->new();
isa_ok($target, 'Chalk::Bootstrap::Target');

# Test 3: generate() is abstract - dies when called on base class
eval { $target->generate([]) };
like($@, qr/Subclass must implement generate/, 'generate() dies on base class');

# Test 4: generate() requires IR argument
eval { $target->generate() };
ok($@, 'generate() with no arguments dies');

# Test 5: generate_distribution() is abstract - dies when called on base class
eval { $target->generate_distribution([]) };
like($@, qr/Subclass must implement generate_distribution/,
    'generate_distribution() dies on base class');

# Test 6: generate_distribution() requires IR argument
eval { $target->generate_distribution() };
ok($@, 'generate_distribution() with no arguments dies');

done_testing();

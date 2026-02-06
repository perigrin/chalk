# ABOUTME: Unit tests for Target::Perl code emitter.
# ABOUTME: Tests symbol/expression/rule emission and full generate() output.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';

use Chalk::Bootstrap::IR::NodeFactory;

# Reset factory for clean test state
Chalk::Bootstrap::IR::NodeFactory->reset_for_testing();
my $factory = Chalk::Bootstrap::IR::NodeFactory->instance();

# === Step 2: Scaffold ===

# Test 1: Module loads
use_ok('Chalk::Bootstrap::Target::Perl');

# Test 2: isa Target
my $target = Chalk::Bootstrap::Target::Perl->new();
isa_ok($target, 'Chalk::Bootstrap::Target');
isa_ok($target, 'Chalk::Bootstrap::Target::Perl');

# Test 3: generate([]) returns string with preamble
{
    my $output = $target->generate([]);
    like($output, qr/use 5\.42\.0/, 'output contains use 5.42.0');
    like($output, qr/use utf8/, 'output contains use utf8');
    like($output, qr/class Chalk::Grammar::BNF::Generated/, 'output contains class declaration');
    like($output, qr/sub grammar/, 'output contains grammar sub');
    like($output, qr/return \\/, 'output contains return statement');
}

done_testing();

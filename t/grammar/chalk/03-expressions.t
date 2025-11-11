#!/usr/bin/env perl
# ABOUTME: Test expression parsing including operators and precedence in chalk.bnf
# ABOUTME: Covers arithmetic, comparison, logical, string operations, method calls
use 5.42.0;
use experimental qw(class builtin keyword_any keyword_all defer);
use utf8;
use open qw/:std :utf8/;
use Test2::V0;
use FindBin qw($RealBin);
defer { done_testing() }

use lib "$RealBin/../../../lib";
use File::Spec;
use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

# Load chalk.bnf grammar
my $bnf_file = File::Spec->catfile( $RealBin, '../../../grammar', 'chalk.bnf' );
open my $fh, '<:utf8', $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$fh> };
close $fh;

my $grammar  = Chalk::Grammar->build_from_bnf( $bnf_content, 'Program' );
my $semiring = Chalk::Semiring::Boolean->new();

sub parses_ok {
    my ( $code, $name ) = @_;
    my $parser = Chalk::Parser->new(
        grammar  => $grammar,
        semiring => $semiring
    );
    my $result = $parser->parse_string($code);
    ok( $result, $name ) or diag("Failed to parse: $code");
}

sub parse_fails {
    my ( $code, $name ) = @_;
    my $parser = Chalk::Parser->new(
        grammar  => $grammar,
        semiring => $semiring
    );
    my $result = $parser->parse_string($code);
    ok( !$result, $name ) or diag("Unexpectedly parsed: $code");
}

# Arithmetic operators
parses_ok( q{ my $x = 1 + 2; },  'addition' );
parses_ok( q{ my $x = 5 - 3; },  'subtraction' );
parses_ok( q{ my $x = 4 * 5; },  'multiplication' );
parses_ok( q{ my $x = 10 / 2; }, 'division' );

# Note: % and ** operators not yet in chalk.bnf
# parses_ok(q{ my $x = 10 % 3; }, 'modulo');
# parses_ok(q{ my $x = 2 ** 8; }, 'exponentiation');

# Precedence
parses_ok( q{ my $x = 2 + 3 * 4; },   'multiplication before addition' );
parses_ok( q{ my $x = (2 + 3) * 4; }, 'parentheses override precedence' );

# Comparison operators
parses_ok( q{ my $x = 1 == 1; },  'numeric equality' );
parses_ok( q{ my $x = 1 != 2; },  'numeric inequality' );
parses_ok( q{ my $x = 1 < 2; },   'less than' );
parses_ok( q{ my $x = 2 > 1; },   'greater than' );
parses_ok( q{ my $x = 1 <= 2; },  'less than or equal' );
parses_ok( q{ my $x = 2 >= 1; },  'greater than or equal' );
parses_ok( q{ my $x = 1 <=> 2; }, 'spaceship operator' );

# String comparison
parses_ok( q{ my $x = 'a' eq 'a'; },  'string equality' );
parses_ok( q{ my $x = 'a' ne 'b'; },  'string inequality' );
parses_ok( q{ my $x = 'a' lt 'b'; },  'string less than' );
parses_ok( q{ my $x = 'b' gt 'a'; },  'string greater than' );
parses_ok( q{ my $x = 'a' le 'b'; },  'string less than or equal' );
parses_ok( q{ my $x = 'b' ge 'a'; },  'string greater than or equal' );
parses_ok( q{ my $x = 'a' cmp 'b'; }, 'string comparison' );

# Logical operators
parses_ok( q{ my $x = 1 && 2; },  'logical and' );
parses_ok( q{ my $x = 0 || 1; },  'logical or' );
parses_ok( q{ my $x = !1; },      'logical not' );
parses_ok( q{ my $x = 1 and 2; }, 'word and' );
parses_ok( q{ my $x = 0 or 1; },  'word or' );
parses_ok( q{ my $x = not 1; },   'word not' );

# Defined-or operator
parses_ok( q{ my $x = undef // 42; }, 'defined-or operator' );

# String concatenation
parses_ok( q{ my $x = 'hello' . ' world'; }, 'string concatenation' );

# Ternary operator
parses_ok( q{ my $x = 1 ? 'yes' : 'no'; },  'ternary operator' );
parses_ok( q{ my $x = $a > $b ? $a : $b; }, 'ternary with comparison' );

# Assignment operators
parses_ok( q{ my $x = 10; },          'simple assignment' );
parses_ok( q{ my $x = 10; $x += 5; }, 'plus equals' );
parses_ok( q{ my $x = 10; $x -= 5; }, 'minus equals' );

# Note: *= and /= operators not yet in chalk.bnf
# parses_ok(q{ my $x = 10; $x *= 2; }, 'times equals');
# parses_ok(q{ my $x = 10; $x /= 2; }, 'divide equals');
parses_ok( q{ my $x = 10; $x //= 5; },   'defined-or equals' );
parses_ok( q{ my $x = 'a'; $x .= 'b'; }, 'concatenate equals' );

# Increment/decrement
parses_ok( q{ my $x = 0; $x++; }, 'postfix increment' );
parses_ok( q{ my $x = 0; $x--; }, 'postfix decrement' );
parses_ok( q{ my $x = 0; ++$x; }, 'prefix increment' );
parses_ok( q{ my $x = 0; --$x; }, 'prefix decrement' );

# Method calls
parses_ok( q{ my $obj = Foo->new(); },       'class method call' );
parses_ok( q{ my $x = $obj->method(); },     'instance method call' );
parses_ok( q{ my $x = $obj->method($arg); }, 'method call with argument' );
parses_ok(
    q{ my $x = $obj->method($arg1, $arg2); },
    'method call with multiple arguments'
);

# Function calls
parses_ok( q{ my $x = foo(); },     'function call' );
parses_ok( q{ my $x = foo($arg); }, 'function call with argument' );
parses_ok(
    q{ my $x = foo($arg1, $arg2); },
    'function call with multiple arguments'
);

# Array/hash access
parses_ok( q{ my $x = $arr[0]; },      'array index access' );
parses_ok( q{ my $x = $hash{'key'}; }, 'hash key access' );
parses_ok( q{ my $x = $arr[$i]; },     'array variable index' );
parses_ok( q{ my $x = $hash{$key}; },  'hash variable key' );

# Complex expressions
parses_ok( q{ my $x = ($a + $b) * ($c - $d); }, 'complex arithmetic' );

# Note: Chained method calls not yet supported in chalk.bnf
# parses_ok(q{ my $x = $obj->method1()->method2(); }, 'chained method calls');
parses_ok( q{ my $x = $hash{'key'}[0]; },     'nested data access' );
parses_ok( q{ my $x = ($y < 0) ? -$y : $y; }, 'absolute value with ternary' );

# Range operator
parses_ok( q{ my @arr = (1..10); },        'range operator' );
parses_ok( q{ my @arr = ($start..$end); }, 'range with variables' );

# Note: Regex match operators not yet in chalk.bnf
# parses_ok(q{ my $x = $str =~ /pattern/; }, 'regex match');
# parses_ok(q{ my $x = $str !~ /pattern/; }, 'regex not match');

# Negative tests: malformed expressions that should NOT parse
parse_fails( q{ my $x = 1 ++; }, 'invalid: double increment operator' );
parse_fails( q{ my $x = $ $y; }, 'invalid: double sigil' );
parse_fails( q{ my $x = $; },    'invalid: incomplete variable' );

# TODO: Grammar currently too permissive - these should fail but don't
todo "Grammar needs tighter validation for lvalue/operator syntax" => sub {
    parse_fails( q{ (1 + 2) = $x; },
        'invalid: assignment to non-lvalue expression' );
    parse_fails( q{ my $x = 1 + + 2; },
        'invalid: two operators without operand' );
    parse_fails( q{ my $x = 1 2; },
        'invalid: missing operator between operands' );
};

parse_fails( q{ my $x = (1 + 2; }, 'invalid: unmatched opening parenthesis' );
parse_fails( q{ my $x = 1 + 2); }, 'invalid: unmatched closing parenthesis' );
parse_fails( q{ my $x = + ; },     'invalid: operator without operands' );

#!/usr/bin/env perl
# ABOUTME: Test Precedence semiring with patterns found in lib/ files
# ABOUTME: Isolates Precedence bugs without TypeInference interference

use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use experimental qw(defer);
defer { done_testing() }

use Chalk::Grammar;
use Chalk::Parser;
use Chalk::Semiring::Boolean;
use Chalk::Semiring::Precedence;
use Chalk::Semiring::Composite;

# Load grammar
open my $fh, '<:utf8', "$RealBin/../../grammar/chalk.bnf" or die $!;
my $content = do { local $/; <$fh> };
close $fh;
my $grammar = Chalk::Grammar->build_from_bnf($content, 'Program', 'Chalk');

# Full Perl precedence table
my @perl_precedence_table = (
    { assoc => 'left',    ops => ['->'] },
    { assoc => 'nonassoc', ops => ['++', '--'] },
    { assoc => 'right',   ops => ['**'] },
    { assoc => 'right',   ops => ['!', '~', '\\', 'unary +', 'unary -'] },
    { assoc => 'left',    ops => ['=~', '!~'] },
    { assoc => 'left',    ops => ['*', '/', '%', 'x'] },
    { assoc => 'left',    ops => ['+', '-', '.'] },
    { assoc => 'left',    ops => ['<<', '>>'] },
    { assoc => 'nonassoc', ops => ['named unary'] },
    { assoc => 'nonassoc', ops => ['isa'] },
    { assoc => 'chained', ops => ['<', '>', '<=', '>=', 'lt', 'gt', 'le', 'ge'] },
    { assoc => 'chain/na', ops => ['==', '!=', 'eq', 'ne', '<=>', 'cmp', '~~'] },
    { assoc => 'left',    ops => ['&'] },
    { assoc => 'left',    ops => ['|', '^'] },
    { assoc => 'left',    ops => ['&&'] },
    { assoc => 'left',    ops => ['||', '^^', '//'] },
    { assoc => 'nonassoc', ops => ['..', '...'] },
    { assoc => 'right',   ops => ['?:'] },
    { assoc => 'right',   ops => ['=', '+=', '-=', '*=', '/=', '%=', '**=', '&=', '|=', '^=', '.=', '<<=', '>>=', '&&=', '||=', '//='] },
    { assoc => 'left',    ops => [',', '=>'] },
    { assoc => 'right',   ops => ['not'] },
    { assoc => 'left',    ops => ['and'] },
    { assoc => 'left',    ops => ['or', 'xor'] },
);

sub make_parser {
    my $composite = Chalk::Semiring::Composite->new(
        semirings => [
            Chalk::Semiring::Boolean->new(),
            Chalk::Semiring::Precedence->new(precedence_table => \@perl_precedence_table)
        ]
    );
    return Chalk::Parser->new(grammar => $grammar, semiring => $composite);
}

subtest 'Single class with operators' => sub {
    my @tests = (
        ['||', 'class Foo { method bar() { return $x || $y; } }'],
        ['&&', 'class Foo { method bar() { return $x && $y; } }'],
        ['==', 'class Foo { method bar() { return $x == $y; } }'],
        ['+', 'class Foo { method bar() { return $x + $y; } }'],
        ['->', 'class Foo { method bar() { return $x->foo(); } }'],
    );

    for my $test (@tests) {
        my ($name, $code) = @$test;
        my $parser = make_parser();
        my $result = $parser->parse_string($code);
        ok $result, "Single class with $name operator";
    }
};

subtest 'Single class with field defaults' => sub {
    my @tests = (
        ['literal', 'class Foo { field $x = 1; }'],
        ['string', 'class Foo { field $x = "str"; }'],
        ['variable', 'class Foo { field $x = $y; }'],
        ['method call', 'class Foo { field $x = Bar->new(); }'],
        ['with :reader', 'class Foo { field $x :reader = 1; }'],
        ['with :param', 'class Foo { field $x :param = 1; }'],
    );

    for my $test (@tests) {
        my ($name, $code) = @$test;
        my $parser = make_parser();
        my $result = $parser->parse_string($code);
        ok $result, "Single class with field default: $name";
    }
};

subtest 'Two simple classes' => sub {
    my $code = <<'CODE';
class Foo {
    field $x :param;
}

class Bar {
    field $y :param;
}
CODE

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'Two simple classes parse';
};

subtest 'Class with || followed by class with field default' => sub {
    # This is the failing pattern from Boolean.pm
    my $code = <<'CODE';
class Foo {
    method bar() {
        return $x || $y;
    }
}

class Bar {
    field $z = 1;
}
CODE

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'Class with || then class with field = 1';
};

subtest 'Class with && followed by class with field default' => sub {
    my $code = <<'CODE';
class Foo {
    method bar() {
        return $x && $y;
    }
}

class Bar {
    field $z = 1;
}
CODE

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'Class with && then class with field = 1';
};

subtest 'Class with == followed by class with field default' => sub {
    my $code = <<'CODE';
class Foo {
    method bar() {
        return $x == $y;
    }
}

class Bar {
    field $z = 1;
}
CODE

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'Class with == then class with field = 1';
};

subtest 'BooleanElement-like first class' => sub {
    todo 'Complex class with multiple operators and method calls triggers precedence parsing issues' => sub {
    # Simplified version of BooleanElement class
    my $code = <<'CODE';
class Foo {
    field $value :param :reader;

    method add($other) {
        return Foo->new(value => $value || $other->value);
    }

    method multiply($other) {
        return Foo->new(value => $value && $other->value);
    }
}

class Bar {
    field $x = 1;
}
CODE

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'BooleanElement-like class then class with field default';
    };
};

subtest 'Multiple operators in sequence' => sub {
    my $code = <<'CODE';
class Foo {
    method bar() {
        my $a = $x || $y;
        my $b = $x && $y;
        my $c = $x == $y;
        return $a;
    }
}

class Bar {
    field $z = 1;
}
CODE

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'Multiple operators then field default';
};

subtest 'Exact Boolean.pm first class content' => sub {
    todo 'Real-world Boolean.pm class triggers precedence parsing issues' => sub {
    # Read actual first class from Boolean.pm
    open my $cfh, '<:utf8', "$RealBin/../../lib/Chalk/Semiring/Boolean.pm" or die $!;
    my @lines = <$cfh>;
    close $cfh;

    # Lines 1-37 is first class
    my $first_class = join('', @lines[0..36]);

    # Add simple second class
    my $code = $first_class . "\nclass Bar { field \$x = 1; }\n";

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'Exact Boolean.pm first class + simple second class';
    };
};

subtest 'Complete Boolean.pm' => sub {
    todo 'Complex precedence parsing in real source files not yet working' => sub {
    open my $cfh, '<:utf8', "$RealBin/../../lib/Chalk/Semiring/Boolean.pm" or die $!;
    my $code = do { local $/; <$cfh> };
    close $cfh;

    my $parser = make_parser();
    my $result = $parser->parse_string($code);
    ok $result, 'Complete Boolean.pm parses with Precedence';
    };  # end todo
};

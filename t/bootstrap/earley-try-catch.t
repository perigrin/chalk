# ABOUTME: Tests for try/catch statement parsing in the Earley parser.
# ABOUTME: Verifies the grammar correctly handles Perl 5.42's try/catch syntax.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(perl_pipeline build_perl_recognizer);
use Chalk::IR::NodeFactory;
use Chalk::Bootstrap::BNF::Target::Perl;

# Build the grammar pipeline
my $ir = perl_pipeline();
ok(defined $ir, 'Perl grammar pipeline builds');

my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
my $generated = $target->generate($ir);
$generated =~ s/Chalk::Grammar::BNF::Generated/Chalk::Grammar::Perl::TryCatchTest/g;
eval $generated;
ok(!$@, 'Generated grammar compiles') or diag $@;

my $grammar = Chalk::Grammar::Perl::TryCatchTest::grammar();
my $parser = build_perl_recognizer($grammar, start => 'Program');
ok(defined $parser, 'Parser built');

# Basic try/catch
ok($parser->parse("use 5.42.0;\nuse utf8;\ntry { 1; } catch (\$e) { 2; }\n"),
   'basic try/catch');

# try/catch as compound statement (no semicolon needed after)
ok($parser->parse("use 5.42.0;\nuse utf8;\ntry { 1; } catch (\$e) { die \$e; }\n"),
   'try/catch with die in catch');

# try/catch inside method
ok($parser->parse(<<'END'), 'try/catch inside method');
use 5.42.0;
use utf8;
class Foo {
    method bar() {
        try {
            my $x = 1;
        } catch ($e) {
            die "Failed: $e";
        }
    }
}
END

# try/catch with assignment before
ok($parser->parse(<<'END'), 'try/catch after assignment');
use 5.42.0;
use utf8;
my $result;
try {
    $result = risky_operation();
} catch ($e) {
    warn $e;
}
END

# Multiple try/catch blocks
ok($parser->parse(<<'END'), 'multiple try/catch blocks');
use 5.42.0;
use utf8;
try {
    first_thing();
} catch ($e) {
    warn $e;
}
try {
    second_thing();
} catch ($e) {
    die $e;
}
END

# try/catch in ADJUST block
ok($parser->parse(<<'END'), 'try/catch in ADJUST');
use 5.42.0;
use utf8;
class Foo {
    field $x :param;
    ADJUST {
        try {
            $x = process($x);
        } catch ($e) {
            die "Invalid: $e";
        }
    }
}
END

# Nested try/catch
ok($parser->parse(<<'END'), 'nested try/catch');
use 5.42.0;
use utf8;
try {
    try {
        inner();
    } catch ($inner_e) {
        warn $inner_e;
    }
} catch ($outer_e) {
    die $outer_e;
}
END

# try/catch with complex catch body
ok($parser->parse(<<'END'), 'try/catch with if in catch');
use 5.42.0;
use utf8;
try {
    something();
} catch ($e) {
    if ($e =~ /not found/) {
        handle_not_found();
    } else {
        die $e;
    }
}
END

# Verify try/catch rejects malformed variants
ok(!$parser->parse("use 5.42.0;\nuse utf8;\ntry { 1; }\n"),
   'try without catch rejects');

ok(!$parser->parse("use 5.42.0;\nuse utf8;\ncatch (\$e) { 1; }\n"),
   'catch without try rejects');

done_testing;

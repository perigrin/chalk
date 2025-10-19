# ABOUTME: Tests for circular grammar allowing print/die/warn in expression context
# ABOUTME: Verifies that valid Perl like 'print print 2' now parses correctly
use 5.42.0;
use experimental qw(class builtin);
use Test::More;
use Chalk::BNF;
use FindBin qw($RealBin);
use Chalk::Parser;

my $parser = Chalk::Parser->new(
    grammar => $chalk_grammar,
);

# Test that we now accept valid Perl that was previously rejected by NonBrace* hierarchy

subtest 'Nested print statements' => sub {
    ok( $parser->parse_string('print print 2'),
        'print print 2' );
    ok( $parser->parse_string('print print print 2'),
        'print print print 2' );
};

subtest 'print with grep/map expressions' => sub {
    ok( $parser->parse_string('print grep { $_ > 5 } @list'),
        'print grep {...} @list' );
    ok( $parser->parse_string('print map { $_ * 2 } @list'),
        'print map {...} @list' );
};

subtest 'die with expressions' => sub {
    ok( $parser->parse_string('die "error"'),
        'die with string' );
    ok( $parser->parse_string('die grep { $_ > 5 } @list'),
        'die grep {...} @list' );
    ok( $parser->parse_string('die print "message"'),
        'die print ...' );
};

subtest 'warn with expressions' => sub {
    ok( $parser->parse_string('warn "warning"'),
        'warn with string' );
    ok( $parser->parse_string('warn map { $_ * 2 } @list'),
        'warn map {...} @list' );
    ok( $parser->parse_string('warn print "message"'),
        'warn print ...' );
};

subtest 'Baseline cases still work' => sub {
    ok( $parser->parse_string('print "hello"'),
        'Simple print' );
    ok( $parser->parse_string('die "error"'),
        'Simple die' );
    ok( $parser->parse_string('$x = 1'),
        'Simple assignment' );
    ok( $parser->parse_string('print $x'),
        'Print variable' );
};

done_testing();

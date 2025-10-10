#!/usr/bin/env perl
# ABOUTME: Test for issue #40 - support for BEGIN/END blocks
# ABOUTME: Tests parsing of BEGIN and END blocks which are fundamental Perl constructs
use 5.42.0;
use experimental qw(class);
use utf8;
use Test::More;
use lib 'lib';
use Chalk::Parser;
use Chalk::Grammar::Perl;
use Chalk::Semiring::Boolean;

# Create parser
my $parser = Chalk::Parser->new(
    grammar => $Chalk::Grammar::Perl::chalk_grammar,
    semiring => Chalk::Semiring::Boolean->new(),
);

# Test basic BEGIN blocks
subtest 'basic BEGIN blocks' => sub {
    my @cases = (
        "BEGIN { }",                                    # Empty BEGIN block
        "BEGIN { 1; }",                                 # Simple statement
        "BEGIN { \$x = 1; }",                           # Variable assignment
        "BEGIN { chdir 't'; }",                         # Function call
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test") or diag("Failed to parse: $test");
    }
};

# Test BEGIN blocks with statement modifiers (from term.t)
subtest 'BEGIN blocks with statement modifiers' => sub {
    my @cases = (
        "BEGIN { chdir 't' if -d 't'; }",               # if modifier
        "BEGIN { chdir 't' unless \$done; }",           # unless modifier
        "BEGIN { 1 while unlink 'foo'; }",              # while modifier
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test") or diag("Failed to parse: $test");
    }
};

# Test END blocks
subtest 'basic END blocks' => sub {
    my @cases = (
        "END { }",                                      # Empty END block
        "END { print 'cleanup'; }",                     # Print in END
        "END { close \$fh; }",                          # Close filehandle
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test") or diag("Failed to parse: $test");
    }
};

# Test the exact construct from term.t (issue #40)
subtest 'issue #40 - term.t BEGIN block' => sub {
    # The exact code that was failing
    my $term_snippet = <<'EOF';
#!./perl

BEGIN {
    chdir 't' if -d 't';
}
EOF

    ok($parser->parse_string($term_snippet), "Should parse term.t BEGIN block snippet")
        or diag("Failed to parse term.t snippet");
};

# Test BEGIN/END blocks in program context
subtest 'BEGIN/END in full programs' => sub {
    my @cases = (
        "BEGIN { \$x = 1; }\n\$x++;",                   # BEGIN then statement
        "\$x = 1;\nEND { print \$x; }",                 # Statement then END
        "BEGIN { \$x = 1; }\n\$y = 2;\nEND { }",        # BEGIN, statement, END
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: " . substr($test, 0, 30) . "...")
            or diag("Failed to parse: $test");
    }
};

# Test multiple BEGIN/END blocks
subtest 'multiple BEGIN/END blocks' => sub {
    my @cases = (
        "BEGIN { \$x = 1; }\nBEGIN { \$y = 2; }",       # Multiple BEGINs
        "END { }\nEND { }",                             # Multiple ENDs
    );

    for my $test (@cases) {
        ok($parser->parse_string($test), "Should parse: $test") or diag("Failed to parse: $test");
    }
};

done_testing();

#!/usr/bin/env perl
# ABOUTME: Integration test for Parser with heredoc preprocessor
# ABOUTME: Verify full heredoc->q{}/qq{} transformation and parsing pipeline
use 5.42.0;
use Test2::V0;
use experimental qw(defer);
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use File::Spec;

# Load grammar from BNF file
my $bnf_file = File::Spec->catfile($RealBin, "..", "..", "grammar", "perl.bnf");
open my $grammar_fh, "<:utf8", $bnf_file or die "Cannot open $bnf_file: $!";
my $bnf_content = do { local $/; <$grammar_fh> };
close $grammar_fh;
my $chalk_grammar = Chalk::Grammar->build_from_bnf($bnf_content, "Program");

use Chalk::Grammar::BNF;
use Chalk::Parser;
use Chalk::Semiring::Boolean;

defer { done_testing() }

subtest 'Parse simple heredoc with preprocessing' => sub {
    my $code = q{my $text = <<'EOF';
Hello World
EOF
};

    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        preprocess => ['Chalk::Preprocessor::Heredoc'],
        semiring => Chalk::Semiring::Boolean->new(),
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Parse single-quoted heredoc';
    isa_ok $result, 'Chalk::Semiring::Element', 'Result is a semiring element';

    # Verify the code contains my declaration and assignment
    like $code, qr/my\s+\$text/, 'Code contains variable declaration';
};

subtest 'Parse double-quoted heredoc with preprocessing' => sub {
    my $code = q{my $text = <<EOF;
Hello World
EOF
};

    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        preprocess => ['Chalk::Preprocessor::Heredoc'],
        semiring => Chalk::Semiring::Boolean->new(),
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Parse double-quoted heredoc';
    isa_ok $result, 'Chalk::Semiring::Element', 'Result is a semiring element';
};

subtest 'Parse indented heredoc with preprocessing' => sub {
    my $code = q{my $text = <<~'EOF';
    Indented content
    More content
EOF
};

    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        preprocess => ['Chalk::Preprocessor::Heredoc'],
        semiring => Chalk::Semiring::Boolean->new(),
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Parse indented heredoc';
    isa_ok $result, 'Chalk::Semiring::Element', 'Result is a semiring element';
};

subtest 'Parse multiple heredocs with preprocessing' => sub {
    my $code = q{my ($a, $b) = (<<'EOF1', <<'EOF2');
First heredoc
EOF1
Second heredoc
EOF2
};

    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        preprocess => ['Chalk::Preprocessor::Heredoc'],
        semiring => Chalk::Semiring::Boolean->new(),
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Parse multiple heredocs';
    isa_ok $result, 'Chalk::Semiring::Element', 'Result is a semiring element';

    # Verify code contains both EOF markers
    like $code, qr/EOF1/, 'Code contains first EOF marker';
    like $code, qr/EOF2/, 'Code contains second EOF marker';
};

subtest 'Parse mixed code and heredoc' => sub {
    my $code = q{my $x = 42;
my $text = <<'EOF';
Some heredoc content
EOF
my $y = $x + 10;};

    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        preprocess => ['Chalk::Preprocessor::Heredoc'],
        semiring => Chalk::Semiring::Boolean->new(),
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Parse mixed code with heredoc';
    isa_ok $result, 'Chalk::Semiring::Element', 'Result is a semiring element';

    # Verify all parts of the code are present
    like $code, qr/\$x = 42/, 'Code contains first assignment';
    like $code, qr/\$y = \$x \+ 10/, 'Code contains second assignment';
};

subtest 'Preprocessing disabled should not transform' => sub {
    my $code = q{my $text = q{Hello World};};

    # Without preprocessing
    my $parser = Chalk::Parser->new(
        grammar => $chalk_grammar,
        preprocess => [],
        semiring => Chalk::Semiring::Boolean->new(),
    );

    my $result = $parser->parse_string($code);
    ok $result, 'Parse q{} without preprocessing';
    isa_ok $result, 'Chalk::Semiring::Element', 'Result is a semiring element';

    # Verify q{} syntax is in the code (not transformed to heredoc)
    like $code, qr/q\{/, 'Code still contains q{} syntax (not transformed)';
};

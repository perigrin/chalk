#!/usr/bin/env perl
# ABOUTME: Integration test for Parser with heredoc preprocessor
# ABOUTME: Verify full heredoc->q{}/qq{} transformation and parsing pipeline
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use lib "$RealBin/../../lib";
use experimental qw(defer);
defer { done_testing() }

use Chalk::Grammar::Perl qw($chalk_grammar);
use Chalk::Parser;
use Chalk::Semiring::Boolean;

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
};

#!/usr/bin/env perl
# ABOUTME: Test Chalk::Preprocessor::Heredoc transformation to q{}/qq{}
# ABOUTME: Verify single-quoted, double-quoted, and indented heredoc support
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Preprocessor::Heredoc;

subtest 'Single-quoted heredoc transformation' => sub {
    my $input = q{my $text = <<'EOF';
Hello World
This is a test
EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    # Should transform to q{...}
    like $output, qr/q\{/, 'Transformed to q{}';
    like $output, qr/Hello World/, 'Contains heredoc content';
    like $output, qr/This is a test/, 'Contains all heredoc lines';
    unlike $output, qr/<<'EOF'/, 'Removed heredoc syntax';
    unlike $output, qr/^EOF$/m, 'Removed terminator';
};

subtest 'Empty single-quoted heredoc' => sub {
    my $input = q{my $text = <<'EOF';
EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/q\{\}/, 'Transformed to empty q{}';
    unlike $output, qr/<<'EOF'/, 'Removed heredoc syntax';
};

subtest 'Single-quoted heredoc with special characters' => sub {
    my $input = q{my $text = <<'END';
Line with $variables that shouldn't expand
Line with @arrays
Line with %hashes
Line with \n escapes
END
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/q\{/, 'Transformed to q{}';
    like $output, qr/\$variables/, 'Contains dollar signs';
    like $output, qr/\@arrays/, 'Contains at signs';
    like $output, qr/%hashes/, 'Contains percent signs';
    like $output, qr/\\n/, 'Contains backslash-n literally';
};

subtest 'Double-quoted heredoc transformation (bare)' => sub {
    my $input = q{my $text = <<EOF;
Hello World
This is a test
EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    # Should transform to qq{...}
    like $output, qr/qq\{/, 'Transformed to qq{}';
    like $output, qr/Hello World/, 'Contains heredoc content';
    like $output, qr/This is a test/, 'Contains all heredoc lines';
    unlike $output, qr/<<EOF/, 'Removed heredoc syntax';
    unlike $output, qr/^EOF$/m, 'Removed terminator';
};

subtest 'Double-quoted heredoc transformation (quoted)' => sub {
    my $input = q{my $text = <<"EOF";
Hello World
This is a test
EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    # Should transform to qq{...}
    like $output, qr/qq\{/, 'Transformed to qq{}';
    like $output, qr/Hello World/, 'Contains heredoc content';
    like $output, qr/This is a test/, 'Contains all heredoc lines';
    unlike $output, qr/<<"EOF"/, 'Removed heredoc syntax';
    unlike $output, qr/^EOF$/m, 'Removed terminator';
};

subtest 'Empty double-quoted heredoc' => sub {
    my $input = q{my $text = <<EOF;
EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/qq\{\}/, 'Transformed to empty qq{}';
    unlike $output, qr/<<EOF/, 'Removed heredoc syntax';
};

subtest 'Indented heredoc with single quotes' => sub {
    my $input = q{    my $text = <<~'EOF';
        Hello World
        This is indented
        Another line
    EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/q\{/, 'Transformed to q{}';
    like $output, qr/Hello World/, 'Contains heredoc content';
    unlike $output, qr/<<~'EOF'/, 'Removed heredoc syntax';
    unlike $output, qr/^    EOF$/m, 'Removed terminator';

    # Check that leading indentation is stripped
    unlike $output, qr/\n        Hello/, 'Indentation stripped from content';
    like $output, qr/Hello World\nThis is indented\nAnother line/, 'Content properly dedented';
};

subtest 'Indented heredoc with double quotes' => sub {
    my $input = q{    my $text = <<~"EOF";
        Hello World
        This is indented
    EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/qq\{/, 'Transformed to qq{}';
    like $output, qr/Hello World/, 'Contains heredoc content';
    unlike $output, qr/<<~"EOF"/, 'Removed heredoc syntax';

    # Check that leading indentation is stripped
    unlike $output, qr/\n        Hello/, 'Indentation stripped from content';
};

subtest 'Indented heredoc bare' => sub {
    my $input = q{    my $text = <<~EOF;
        Hello World
        This is indented
    EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/qq\{/, 'Transformed to qq{}';
    like $output, qr/Hello World/, 'Contains heredoc content';
    unlike $output, qr/<<~EOF/, 'Removed heredoc syntax';

    # Check that leading indentation is stripped
    unlike $output, qr/\n        Hello/, 'Indentation stripped from content';
};

subtest 'Indented heredoc with mixed indentation' => sub {
    my $input = q{    my $text = <<~'EOF';
        First line
            More indented
        Back to normal
    EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/q\{/, 'Transformed to q{}';

    # First line should have no leading spaces (stripped)
    like $output, qr/First line/, 'First line dedented';

    # More indented line should retain relative indentation (4 extra spaces)
    like $output, qr/\n    More indented/, 'Relative indentation preserved';

    # Third line back to baseline
    like $output, qr/\nBack to normal/, 'Back to baseline dedented';
};

subtest 'Multiple heredocs on same line' => sub {
    my $input = q{my ($a, $b) = (<<'EOF1', <<'EOF2');
First heredoc
EOF1
Second heredoc
EOF2
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/q\{First heredoc\}/, 'First heredoc transformed';
    like $output, qr/q\{Second heredoc\}/, 'Second heredoc transformed';
    unlike $output, qr/<<'EOF1'/, 'First heredoc syntax removed';
    unlike $output, qr/<<'EOF2'/, 'Second heredoc syntax removed';
};

subtest 'Edge case: Empty lines in heredoc' => sub {
    my $input = q{my $text = <<'EOF';
First line

Third line (blank in between)
EOF
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/First line\n\nThird line/, 'Empty line preserved';
};

subtest 'Edge case: Heredoc delimiter appears in content' => sub {
    my $input = q{my $text = <<'DELIM';
This line mentions DELIM but not at start
  DELIM with leading space
Still going
DELIM
};

    my $preprocessor = Chalk::Preprocessor::Heredoc->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/mentions DELIM/, 'DELIM in content preserved';
    like $output, qr/DELIM with leading space/, 'DELIM with space preserved';
    unlike $output, qr/^DELIM$/m, 'Only terminator DELIM removed';
};

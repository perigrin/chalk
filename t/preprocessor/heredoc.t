#!/usr/bin/env perl
# ABOUTME: Test Chalk::Preprocessor heredoc transformation to q{}/qq{}
# ABOUTME: Verify single-quoted, double-quoted, and indented heredoc support
use 5.42.0;
use Test2::V0;
use FindBin qw($RealBin);
use experimental qw(defer);
defer { done_testing() }

use lib "$RealBin/../../lib";
use Chalk::Preprocessor;

subtest 'Single-quoted heredoc transformation' => sub {
    my $input = q{my $text = <<'EOF';
Hello World
This is a test
EOF
};

    my $preprocessor = Chalk::Preprocessor->new(input => $input);
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

    my $preprocessor = Chalk::Preprocessor->new(input => $input);
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

    my $preprocessor = Chalk::Preprocessor->new(input => $input);
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

    my $preprocessor = Chalk::Preprocessor->new(input => $input);
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

    my $preprocessor = Chalk::Preprocessor->new(input => $input);
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

    my $preprocessor = Chalk::Preprocessor->new(input => $input);
    $preprocessor->transform();
    my $output = $preprocessor->output;

    like $output, qr/qq\{\}/, 'Transformed to empty qq{}';
    unlike $output, qr/<<EOF/, 'Removed heredoc syntax';
};

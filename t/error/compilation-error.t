#!/usr/bin/env perl
# ABOUTME: Test CompilationError class for formatted error reporting with source location
# ABOUTME: Verify error creation, formatting, context display, and recovery hints
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More;
use Chalk::Error::CompilationError;
use Chalk::IR::SourceInfo;

# Test 1: Create basic compilation error
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 5,
        start_col  => 10,
        end_line   => 5,
        end_col    => 15,
        start_pos  => 50,
        end_pos    => 55,
    );

    my $error = Chalk::Error::CompilationError->new(
        message     => 'Undefined variable',
        source_info => $source_info,
    );

    isa_ok($error, 'Chalk::Error::CompilationError', 'Basic error created');
    is($error->message, 'Undefined variable', 'Error has message');
    is($error->source_info, $source_info, 'Error has source_info');
}

# Test 2: Error without source_info
{
    my $error = Chalk::Error::CompilationError->new(
        message => 'Generic compiler error',
    );

    isa_ok($error, 'Chalk::Error::CompilationError', 'Error without source_info created');
    is($error->message, 'Generic compiler error', 'Error has message');
    is($error->source_info, undef, 'Error has no source_info');
}

# Test 3: Error with hints
{
    my $error = Chalk::Error::CompilationError->new(
        message => 'Type mismatch',
        hints   => ['Did you mean to use a string?', 'Check the function signature'],
    );

    isa_ok($error, 'Chalk::Error::CompilationError', 'Error with hints created');
    is(ref($error->hints), 'ARRAY', 'hints is an arrayref');
    is(scalar($error->hints->@*), 2, 'Error has two hints');
    is($error->hints->[0], 'Did you mean to use a string?', 'First hint correct');
}

# Test 4: Formatted error output with source location
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'example.chalk',
        start_line => 10,
        start_col  => 5,
        end_line   => 10,
        end_col    => 12,
        start_pos  => 100,
        end_pos    => 107,
    );

    my $error = Chalk::Error::CompilationError->new(
        message     => 'Undefined variable "foo"',
        source_info => $source_info,
    );

    my $formatted = $error->format();
    isnt($formatted, undef, 'Error can be formatted');
    like($formatted, qr/example\.chalk/, 'Formatted error includes filename');
    like($formatted, qr/10/, 'Formatted error includes line number');
    like($formatted, qr/Undefined variable/, 'Formatted error includes message');
}

# Test 5: Formatted error with hints
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 5,
        start_col  => 1,
        end_line   => 5,
        end_col    => 5,
        start_pos  => 50,
        end_pos    => 54,
    );

    my $error = Chalk::Error::CompilationError->new(
        message     => 'Invalid syntax',
        source_info => $source_info,
        hints       => ['Missing semicolon?', 'Check bracket matching'],
    );

    my $formatted = $error->format();
    like($formatted, qr/Invalid syntax/, 'Formatted error includes message');
    like($formatted, qr/Missing semicolon/, 'Formatted error includes first hint');
    like($formatted, qr/Check bracket/, 'Formatted error includes second hint');
}

# Test 6: Error with source context (if source text available)
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'context.chalk',
        start_line => 3,
        start_col  => 8,
        end_line   => 3,
        end_col    => 13,
        start_pos  => 30,
        end_pos    => 35,
    );

    my $error = Chalk::Error::CompilationError->new(
        message      => 'Unknown identifier',
        source_info  => $source_info,
        source_lines => ['line 1', 'line 2', 'let x = unknown + 5;', 'line 4'],
    );

    my $formatted = $error->format();
    like($formatted, qr/let x = unknown/, 'Formatted error shows source context');
    like($formatted, qr/\^+/, 'Formatted error shows caret indicator');
}

# Test 7: Error stringification
{
    my $error = Chalk::Error::CompilationError->new(
        message => 'Test error',
    );

    my $str = $error->to_string();
    like($str, qr/Test error/, 'Error stringifies to message');
}

# Test 8: Error with severity level
{
    my $error = Chalk::Error::CompilationError->new(
        message  => 'Deprecated feature',
        severity => 'warning',
    );

    is($error->severity, 'warning', 'Error has severity level');
}

# Test 9: Format error without source info
{
    my $error = Chalk::Error::CompilationError->new(
        message => 'Internal compiler error',
    );

    my $formatted = $error->format();
    like($formatted, qr/Internal compiler error/, 'Error without source_info formats correctly');
}

# Test 10: Multi-line error span
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'multiline.chalk',
        start_line => 5,
        start_col  => 10,
        end_line   => 7,
        end_col    => 5,
        start_pos  => 50,
        end_pos    => 75,
    );

    my $error = Chalk::Error::CompilationError->new(
        message     => 'Unterminated block',
        source_info => $source_info,
    );

    my $formatted = $error->format();
    like($formatted, qr/5.*7/s, 'Multi-line error shows range');
}

done_testing();

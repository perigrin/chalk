#!/usr/bin/env perl
# ABOUTME: Test SourceInfo class for tracking source location metadata in IR nodes
# ABOUTME: Verify construction, accessors, and formatting methods work correctly
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 18;
use Chalk::IR::SourceInfo;

# Test 1: Construction with all fields
{
    my $info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 10,
        start_col  => 5,
        end_line   => 10,
        end_col    => 15,
        start_pos  => 100,
        end_pos    => 110,
    );

    isa_ok($info, 'Chalk::IR::SourceInfo', 'SourceInfo object created');
    is($info->file_path, 'test.chalk', 'file_path accessor works');
    is($info->start_line, 10, 'start_line accessor works');
    is($info->start_col, 5, 'start_col accessor works');
    is($info->end_line, 10, 'end_line accessor works');
    is($info->end_col, 15, 'end_col accessor works');
    is($info->start_pos, 100, 'start_pos accessor works');
    is($info->end_pos, 110, 'end_pos accessor works');
}

# Test 2: to_string formatting
{
    my $info = Chalk::IR::SourceInfo->new(
        file_path  => 'example.chalk',
        start_line => 5,
        start_col  => 10,
        end_line   => 5,
        end_col    => 20,
        start_pos  => 50,
        end_pos    => 60,
    );

    my $str = $info->to_string();
    like($str, qr/example\.chalk/, 'to_string includes file path');
    like($str, qr/5/, 'to_string includes line number');
    like($str, qr/10/, 'to_string includes start column');
}

# Test 3: Construction with minimal fields (optional end position)
{
    my $info = Chalk::IR::SourceInfo->new(
        file_path  => 'minimal.chalk',
        start_line => 1,
        start_col  => 1,
        end_line   => 1,
        end_col    => 1,
        start_pos  => 0,
        end_pos    => 0,
    );

    isa_ok($info, 'Chalk::IR::SourceInfo', 'Minimal SourceInfo object created');
    is($info->start_pos, 0, 'Zero start position works');
    is($info->end_pos, 0, 'Zero end position works');
}

# Test 4: span_length method
{
    my $info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 1,
        start_col  => 1,
        end_line   => 1,
        end_col    => 10,
        start_pos  => 0,
        end_pos    => 9,
    );

    is($info->span_length(), 9, 'span_length returns correct length');
}

# Test 5: Single-character span
{
    my $info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 1,
        start_col  => 5,
        end_line   => 1,
        end_col    => 6,
        start_pos  => 5,
        end_pos    => 6,
    );

    is($info->span_length(), 1, 'single character span length');
}

# Test 6: Multi-line span
{
    my $info = Chalk::IR::SourceInfo->new(
        file_path  => 'multiline.chalk',
        start_line => 10,
        start_col  => 5,
        end_line   => 12,
        end_col    => 10,
        start_pos  => 100,
        end_pos    => 150,
    );

    is($info->start_line, 10, 'multi-line span start line');
    is($info->end_line, 12, 'multi-line span end line');
}

done_testing();

#!/usr/bin/env perl
# ABOUTME: Test IR::Node integration with SourceInfo for tracking source locations
# ABOUTME: Verify nodes can store and retrieve source information for error reporting
use 5.42.0;
use utf8;
use lib 'lib';
use Test::More tests => 10;
use Chalk::IR::Node;
use Chalk::IR::SourceInfo;

# Test 1: Node without source_info
{
    my $node = Chalk::IR::Node->new(
        id => 1,
        op => 'Add',
        inputs => [2, 3],
        attributes => {},
    );

    isa_ok($node, 'Chalk::IR::Node', 'Node without source_info created');
    is($node->source_info, undef, 'source_info is undef when not provided');
    is($node->source_location, undef, 'source_location returns undef when no source_info');
}

# Test 2: Node with source_info
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'test.chalk',
        start_line => 10,
        start_col  => 5,
        end_line   => 10,
        end_col    => 15,
        start_pos  => 100,
        end_pos    => 110,
    );

    my $node = Chalk::IR::Node->new(
        id => 2,
        op => 'Constant',
        inputs => [],
        attributes => {value => 42},
        source_info => $source_info,
    );

    isa_ok($node, 'Chalk::IR::Node', 'Node with source_info created');
    isa_ok($node->source_info, 'Chalk::IR::SourceInfo', 'source_info field contains SourceInfo object');
    is($node->source_info->file_path, 'test.chalk', 'source_info file_path accessible');

    my $loc = $node->source_location();
    isnt($loc, undef, 'source_location returns value when source_info present');
    like($loc, qr/test\.chalk/, 'source_location includes file path');
}

# Test 3: to_hash preserves source_info
{
    my $source_info = Chalk::IR::SourceInfo->new(
        file_path  => 'example.chalk',
        start_line => 5,
        start_col  => 1,
        end_line   => 5,
        end_col    => 10,
        start_pos  => 50,
        end_pos    => 59,
    );

    my $node = Chalk::IR::Node->new(
        id => 3,
        op => 'Return',
        inputs => [4],
        attributes => {},
        source_info => $source_info,
    );

    my $hash = $node->to_hash();
    isnt($hash->{source_info}, undef, 'to_hash includes source_info');
    is(ref($hash->{source_info}), 'Chalk::IR::SourceInfo', 'to_hash preserves SourceInfo object');
}

done_testing();

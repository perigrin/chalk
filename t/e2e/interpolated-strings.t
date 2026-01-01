# ABOUTME: E2E test for interpolated string compilation to XS
# ABOUTME: Verifies that string literals generate correct IR and XS code

use 5.42.0;
use Test::More;

# Set lib path at compile time using abs_path on $0 for worktree compatibility
BEGIN {
    use Cwd qw(abs_path);
    use File::Spec;
    my $test_file = abs_path($0);
    my ($vol, $dir, $file) = File::Spec->splitpath($test_file);
    my $lib_dir = abs_path(File::Spec->catdir($vol, $dir, '..', '..', 'lib'));
    unshift @INC, $lib_dir;
}

use Chalk::Target::XS;
use Chalk::IR::Node::Constant;
use Chalk::IR::Node::InterpolatedString;
use Chalk::IR::Type::String;

# Test 1: Simple Constant generates SV* declaration with string value
subtest 'Constant string generates XS declaration' => sub {
    my $constant = Chalk::IR::Node::Constant->new(
        value => "hello world",
        type  => Chalk::IR::Type::String->new(),
    );

    my $target = Chalk::Target::XS->new(
        graph       => undef,
        module_name => 'TestModule',
    );

    my $result = $target->visit_Constant($constant);
    ok(defined $result, 'visit_Constant returns result');

    my $emitted = $result->emit();
    like($emitted, qr/SV\*/, 'Constant emits SV* type');
    like($emitted, qr/hello world/, 'Constant contains string value');
};

# Test 2: Constant with escape sequences has them processed
subtest 'Escape sequences are processed in Constant' => sub {
    # The escape processing happens in the semantic action,
    # so by the time we have a Constant, \n is already a real newline
    my $constant = Chalk::IR::Node::Constant->new(
        value => "line1\nline2",  # actual newline
        type  => Chalk::IR::Type::String->new(),
    );

    my $target = Chalk::Target::XS->new(
        graph       => undef,
        module_name => 'TestModule',
    );

    my $result = $target->visit_Constant($constant);
    my $emitted = $result->emit();

    # The XS should contain SV* declaration with the string
    ok(defined $emitted, 'Escape string generates XS');
    like($emitted, qr/SV\*/, 'Escape string emits SV* type');
    # The newline should be present (either literal or escaped)
    like($emitted, qr/line1.*line2/s, 'String contains both line parts');
};

# Test 3: InterpolatedString generates concatenation
subtest 'InterpolatedString generates concatenation' => sub {
    my $part1 = Chalk::IR::Node::Constant->new(
        value => "Hello ",
        type  => Chalk::IR::Type::String->new(),
    );

    my $part2 = Chalk::IR::Node::Constant->new(
        value => "World",
        type  => Chalk::IR::Type::String->new(),
    );

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part1, $part2],
    );

    my $target = Chalk::Target::XS->new(
        graph       => undef,
        module_name => 'TestModule',
    );

    # Pre-bind the part variables
    $target->bind_var($part1->id, 'tmp_part1');
    $target->bind_var($part2->id, 'tmp_part2');

    my $result = $target->visit_InterpolatedString($interp);
    ok(defined $result, 'visit_InterpolatedString returns result');

    my $emitted = $result->emit();
    ok(defined $emitted, 'InterpolatedString generates XS');
    # Should use sv_catsv for concatenation
    like($emitted, qr/sv_catsv|sv_catpv|newSVsv/, 'InterpolatedString uses string concatenation');
};

# Test 4: Empty InterpolatedString generates empty string
subtest 'Empty InterpolatedString generates empty string' => sub {
    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [],
    );

    my $target = Chalk::Target::XS->new(
        graph       => undef,
        module_name => 'TestModule',
    );

    my $result = $target->visit_InterpolatedString($interp);
    ok(defined $result, 'Empty InterpolatedString returns result');

    my $emitted = $result->emit();
    like($emitted, qr/newSVpvn\s*\(\s*""\s*,\s*0\s*\)/, 'Empty string uses newSVpvn("", 0)');
};

# Test 5: Single part InterpolatedString optimizes to copy
subtest 'Single part InterpolatedString optimizes' => sub {
    my $part = Chalk::IR::Node::Constant->new(
        value => "solo",
        type  => Chalk::IR::Type::String->new(),
    );

    my $interp = Chalk::IR::Node::InterpolatedString->new(
        parts => [$part],
    );

    my $target = Chalk::Target::XS->new(
        graph       => undef,
        module_name => 'TestModule',
    );

    $target->bind_var($part->id, 'tmp_solo');

    my $result = $target->visit_InterpolatedString($interp);
    ok(defined $result, 'Single part InterpolatedString returns result');

    my $emitted = $result->emit();
    # Single part should just copy the value
    like($emitted, qr/newSVsv/, 'Single part uses newSVsv copy');
};

done_testing();

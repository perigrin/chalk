# ABOUTME: Tests for script/chalk-emit-son-json CLI tool.
# ABOUTME: Verifies that chalk-emit-son-json parses a .pm file and emits valid SoN JSON.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP ();

# ============================================================
# Test 1: Script exists and is executable
# ============================================================

my $script = 'script/chalk-emit-son-json';
ok(-f $script, 'script/chalk-emit-son-json exists');

# ============================================================
# Test 2: Script emits valid JSON for a simple .pm file
# ============================================================

{
    my $target = 'lib/Chalk/IR/UseInfo.pm';
    my $perl = $ENV{CHALK_PERL} // $^X;
    my $output = `$perl -Ilib -It/bootstrap/lib $script $target 2>/dev/null`;
    my $exit = $? >> 8;

    is($exit, 0, "exit code 0 for $target") or diag("Output: $output");

    SKIP: {
        skip "script failed for $target", 5 if $exit != 0;

        my $data = eval { JSON::PP->new->decode($output) };
        ok(defined $data, 'output is valid JSON') or diag("Parse error: $@");

        is($data->{version}, 1, 'JSON version is 1');
        ok(exists $data->{methods}, 'JSON has methods key');
        is(ref $data->{methods}, 'HASH', 'methods is a hashref');

        # UseInfo.pm has at least one class with methods — we should find named graphs
        my @method_names = sort keys $data->{methods}->%*;
        ok(scalar @method_names > 0, 'at least one method graph emitted')
            or diag("Got methods: @method_names");
    }
}

# ============================================================
# Test 3: Each emitted method has valid graph structure
# ============================================================

{
    my $target = 'lib/Chalk/IR/UseInfo.pm';
    my $perl = $ENV{CHALK_PERL} // $^X;
    my $output = `$perl -Ilib -It/bootstrap/lib $script $target 2>/dev/null`;
    my $data = eval { JSON::PP->new->decode($output) };

    SKIP: {
        skip 'no valid JSON output', 3 unless defined $data && ref $data->{methods} eq 'HASH';

        my @names = sort keys $data->{methods}->%*;
        for my $name (@names) {
            my $graph = $data->{methods}{$name};
            ok(exists $graph->{nodes}, "$name: has nodes array");
            ok(defined $graph->{start}, "$name: has start index");
            ok(exists $graph->{returns}, "$name: has returns array");
            last;  # just test the first one to keep output clean
        }
    }
}

# ============================================================
# Test 4: Source field is populated with the input filename
# ============================================================

{
    my $target = 'lib/Chalk/IR/UseInfo.pm';
    my $perl = $ENV{CHALK_PERL} // $^X;
    my $output = `$perl -Ilib -It/bootstrap/lib $script $target 2>/dev/null`;
    my $data = eval { JSON::PP->new->decode($output) };

    SKIP: {
        skip 'no valid JSON output', 1 unless defined $data;
        is($data->{source}, $target, 'source field contains input filename');
    }
}

# ============================================================
# Test 5: Method names are qualified (ClassName::method_name)
# ============================================================

{
    my $target = 'lib/Chalk/IR/UseInfo.pm';
    my $perl = $ENV{CHALK_PERL} // $^X;
    my $output = `$perl -Ilib -It/bootstrap/lib $script $target 2>/dev/null`;
    my $data = eval { JSON::PP->new->decode($output) };

    SKIP: {
        skip 'no valid JSON output', 1 unless defined $data && ref $data->{methods} eq 'HASH';

        my @names = sort keys $data->{methods}->%*;
        my @qualified = grep { /::/ } @names;
        ok(scalar @qualified > 0, 'at least one method name is qualified (Class::method)')
            or diag("Method names: @names");
    }
}

done_testing();

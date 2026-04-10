# ABOUTME: Per-file SoN IR comparison between Chalk and perl5-son (B::SoN).
# ABOUTME: Runs both pipelines on each .pm file, diffs JSON, reports divergences.
use 5.42.0;
use utf8;
use Test::More;
use JSON::PP ();

# -----------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------

my $perl     = $ENV{CHALK_PERL} // $^X;
my $son_lib  = $ENV{PERL5_SON_LIB} // "$ENV{HOME}/dev/perl5-son/lib";
my $chalk_script = 'script/chalk-emit-son-json';

# Verify perl5-son is available
unless (-d $son_lib && -f "$son_lib/B/SoN.pm") {
    plan skip_all => "perl5-son not found at $son_lib (set PERL5_SON_LIB)";
}

unless (-f $chalk_script) {
    plan skip_all => "chalk-emit-son-json not found";
}

# -----------------------------------------------------------------------
# Helper: run B::SoN on a file with package filter
# -----------------------------------------------------------------------

sub run_bson ($file, $package) {
    my $cmd = "$perl -Ilib -I$son_lib -MO=SoN,json,package=$package $file 2>/dev/null";
    my $output = `$cmd`;
    my $exit = $? >> 8;
    return ($exit, $output);
}

# -----------------------------------------------------------------------
# Helper: run chalk-emit-son-json on a file
# -----------------------------------------------------------------------

sub run_chalk ($file) {
    my $cmd = "$perl -Ilib -It/bootstrap/lib $chalk_script $file 2>/dev/null";
    my $output = `$cmd`;
    my $exit = $? >> 8;
    return ($exit, $output);
}

# -----------------------------------------------------------------------
# Helper: extract method names from SoN JSON
# -----------------------------------------------------------------------

sub method_names ($json_str) {
    my $data = eval { JSON::PP->new->decode($json_str) };
    return () unless defined $data && ref $data->{methods} eq 'HASH';
    return sort keys $data->{methods}->%*;
}

# -----------------------------------------------------------------------
# Helper: compare node ops for a single method between two JSON outputs
# Returns hashref with match status and details
# -----------------------------------------------------------------------

sub compare_method ($bson_data, $chalk_data, $method_name) {
    my $bson_method  = $bson_data->{methods}{$method_name};
    my $chalk_method = $chalk_data->{methods}{$method_name};

    return { match => false, reason => 'missing from B::SoN' }
        unless defined $bson_method;
    return { match => false, reason => 'missing from Chalk' }
        unless defined $chalk_method;

    # Compare node operation sequences (structural comparison)
    my @bson_ops  = map { $_->{op} } $bson_method->{nodes}->@*;
    my @chalk_ops = map { $_->{op} } $chalk_method->{nodes}->@*;

    my $bson_ops_str  = join(',', @bson_ops);
    my $chalk_ops_str = join(',', @chalk_ops);

    if ($bson_ops_str eq $chalk_ops_str) {
        return { match => true, node_count => scalar @bson_ops };
    }

    return {
        match      => false,
        reason     => 'op sequence differs',
        bson_ops   => \@bson_ops,
        chalk_ops  => \@chalk_ops,
        bson_count  => scalar @bson_ops,
        chalk_count => scalar @chalk_ops,
    };
}

# =======================================================================
# Test 1: UseInfo.pm — both pipelines produce JSON
# =======================================================================

my $test_file = 'lib/Chalk/IR/UseInfo.pm';
my $test_pkg  = 'Chalk::IR::UseInfo';

{
    my ($bson_exit, $bson_json) = run_bson($test_file, $test_pkg);
    is($bson_exit, 0, "B::SoN exits 0 for $test_file");

    my ($chalk_exit, $chalk_json) = run_chalk($test_file);
    is($chalk_exit, 0, "Chalk exits 0 for $test_file");

    SKIP: {
        skip "one or both pipelines failed", 4 if $bson_exit != 0 || $chalk_exit != 0;

        my $bson_data  = eval { JSON::PP->new->decode($bson_json) };
        my $chalk_data = eval { JSON::PP->new->decode($chalk_json) };

        ok(defined $bson_data, 'B::SoN output is valid JSON');
        ok(defined $chalk_data, 'Chalk output is valid JSON');

        # Both should have methods
        my @bson_methods  = method_names($bson_json);
        my @chalk_methods = method_names($chalk_json);
        ok(scalar @bson_methods > 0, 'B::SoN found methods');
        ok(scalar @chalk_methods > 0, 'Chalk found methods');

        # Report which methods are in common
        my %bson_set  = map { $_ => 1 } @bson_methods;
        my %chalk_set = map { $_ => 1 } @chalk_methods;
        my @common = grep { $bson_set{$_} } @chalk_methods;
        my @bson_only  = grep { !$chalk_set{$_} } @bson_methods;
        my @chalk_only = grep { !$bson_set{$_} } @chalk_methods;

        diag("Common methods: " . join(', ', @common)) if @common;
        diag("B::SoN only: " . join(', ', @bson_only)) if @bson_only;
        diag("Chalk only: " . join(', ', @chalk_only)) if @chalk_only;

        # Report method set overlap
        ok(scalar @common > 0 || scalar @bson_only + scalar @chalk_only > 0,
            'at least one method found in either pipeline');

        # For common methods, compare op sequences
        for my $method (@common) {
            my $result = compare_method($bson_data, $chalk_data, $method);
            if ($result->{match}) {
                pass("$method: op sequences match ($result->{node_count} nodes)");
            } else {
                # Report as TODO — divergences are expected at this stage
                TODO: {
                    local $TODO = "IR divergences expected: $result->{reason}";
                    fail("$method: $result->{reason}");
                    if ($result->{reason} eq 'op sequence differs') {
                        diag("  B::SoN ($result->{bson_count} nodes): "
                            . join(', ', $result->{bson_ops}->@*));
                        diag("  Chalk  ($result->{chalk_count} nodes): "
                            . join(', ', $result->{chalk_ops}->@*));
                    }
                }
            }
        }
    }
}

# =======================================================================
# Test 2: Run comparison on a second file to verify harness works broadly
# =======================================================================

{
    my $file2 = 'lib/Chalk/IR/FieldInfo.pm';
    my $pkg2  = 'Chalk::IR::FieldInfo';

    SKIP: {
        skip "FieldInfo.pm not found", 2 unless -f $file2;

        my ($bson_exit, $bson_json) = run_bson($file2, $pkg2);
        my ($chalk_exit, $chalk_json) = run_chalk($file2);

        is($bson_exit, 0, "B::SoN exits 0 for $file2");

        TODO: {
            local $TODO = "not all files parse cleanly yet" if $chalk_exit != 0;
            is($chalk_exit, 0, "Chalk exits 0 for $file2");
        }

        if ($bson_exit == 0 && $chalk_exit == 0) {
            my $bson_data  = eval { JSON::PP->new->decode($bson_json) };
            my $chalk_data = eval { JSON::PP->new->decode($chalk_json) };

            my @bson_methods  = method_names($bson_json);
            my @chalk_methods = method_names($chalk_json);
            my %bson_set = map { $_ => 1 } @bson_methods;
            my @common = grep { $bson_set{$_} } @chalk_methods;

            for my $method (@common) {
                my $result = compare_method($bson_data, $chalk_data, $method);
                if ($result->{match}) {
                    pass("$method: op sequences match");
                } else {
                    TODO: {
                        local $TODO = "IR divergences expected: $result->{reason}";
                        fail("$method: $result->{reason}");
                    }
                }
            }
        }
    }
}

done_testing();

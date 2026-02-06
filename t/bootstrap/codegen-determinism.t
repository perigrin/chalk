# ABOUTME: Verifies that code generation produces byte-identical output across runs.
# ABOUTME: Tests determinism by generating the same IR twice and comparing results.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(full_pipeline);
use Chalk::Bootstrap::Target::Perl;

sub build_and_generate {
    my $ir = full_pipeline();
    return undef unless defined $ir;

    my $target = Chalk::Bootstrap::Target::Perl->new();
    return $target->generate($ir);
}

# Generate twice and compare
my $output1 = build_and_generate();
ok(defined $output1, 'first generation succeeds');

my $output2 = build_and_generate();
ok(defined $output2, 'second generation succeeds');

is($output1, $output2, 'two generations produce byte-identical output');

# Verify non-empty
ok(length($output1) > 100, 'generated output is non-trivial');

# Verify it contains expected content
like($output1, qr/10.*rule|Grammar.*InlineRegex/s, 'output contains expected rules');

done_testing();

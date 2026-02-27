# ABOUTME: Verifies that code generation produces byte-identical output across runs.
# ABOUTME: Tests determinism by generating the same IR twice and comparing results.
use 5.42.0;
use utf8;
use Test::More;

use lib 'lib';
use lib 't/bootstrap/lib';
use TestPipeline qw(full_pipeline);
use Chalk::Bootstrap::BNF::Target::Perl;

sub build_and_generate {
    my $ir = full_pipeline();
    return undef unless defined $ir;

    my $target = Chalk::Bootstrap::BNF::Target::Perl->new();
    return $target->generate($ir);
}

# Generate 5 times and compare all against the first
my @outputs;
for my $i (1..5) {
    my $output = build_and_generate();
    push @outputs, $output;
    ok(defined $output, "generation $i succeeds");
}

# Compare all against the first
for my $i (1..$#outputs) {
    is($outputs[$i], $outputs[0], "generation " . ($i+1) . " matches generation 1");
}

# Verify non-empty
ok(length($outputs[0]) > 100, 'generated output is non-trivial');

# Verify it contains expected content
like($outputs[0], qr/10.*rule|Grammar.*InlineRegex/s, 'output contains expected rules');

done_testing();

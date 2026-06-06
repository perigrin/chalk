use 5.42.0;
use JSON::PP;

open my $fh, '<', 't/fixtures/codegen-harness/gap-map.json' or die $!;
local $/;
my $j = <$fh>;
close $fh;

my $d = JSON::PP->new->decode($j);
my $s = $d->{summary};

print "=== SUMMARY ===\n";
print "Denominator: $s->{denominator}\n";

print "\nBy Verdict:\n";
my $bv = $s->{by_verdict};
for my $v (sort keys %$bv) {
    printf "  %-22s %d\n", $v, $bv->{$v};
}

print "\nBy Group:\n";
my $bg = $s->{by_group};
for my $g (sort keys %$bg) {
    my $bgr = $bg->{$g};
    printf "  %s (count=%d): ", $g, $bgr->{count};
    my $bvr = $bgr->{verdicts};
    for my $v (sort keys %$bvr) {
        printf "%s=%d ", $v, $bvr->{$v};
    }
    print "\n";
}

print "\n=== PASS and MISCOMPILE ENTRIES ===\n";
my $entries = $d->{entries};
for my $entry (@$entries) {
    my $v = $entry->{verdict};
    if ($v eq 'PASS' || $v eq 'MISCOMPILE') {
        printf "  %-6s  %s  (%s)\n", $entry->{tag}, $v, ($entry->{extra}{graph_source} // 'unknown');
    }
}

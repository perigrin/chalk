# (the module's directory from the probe's own, this repository's root, or chalk's)
use lib 'w1lib', 'docs/research/son-ir-audit-2026-11-19/probes/p/w1lib', 't/data/audit-probes/w1lib';
use w1step;
my $o = w1step->new;
my $x = $w1step::n;
for my $i (1..3) { print "$w1step::n\n"; $o->bump; }
print "$w1step::n\n";

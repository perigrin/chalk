# (the module's directory from the probe's own, this repository's root, or chalk's)
use lib 'w1lib', 'docs/research/son-ir-audit-2026-11-19/probes/p/w1lib', 't/data/audit-probes/w1lib';
use w1counter;
my $o = w1counter->new;
my $r = $o->run;
print "$r\n";

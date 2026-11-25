use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; my $s=""; for my $i (1..3) { $s .= $YInit::n; YInit::bump() } print "$s\n";

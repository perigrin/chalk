use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; my %c = %YInit::h; $c{a} = 9; print "$YInit::h{a} ", scalar(keys %c), "\n";

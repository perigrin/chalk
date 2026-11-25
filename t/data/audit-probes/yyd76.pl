use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; print "$YInit::l[-1] $#YInit::l ", defined $YInit::l[2] ? "d" : "u", "\n";

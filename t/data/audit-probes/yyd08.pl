use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; print scalar(@YInit::l), " ", join(",", map { defined $_ ? $_ : "u" } @YInit::l), "\n";

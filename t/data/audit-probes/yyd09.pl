use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; print join(",", map { "$_=$YInit::h{$_}" } sort keys %YInit::h), " $YInit::t\n";

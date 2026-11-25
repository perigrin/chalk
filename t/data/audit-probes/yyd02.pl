use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; print defined $YInit::e ? "d" : "u", defined $YInit::u ? "d" : "u", "[$YInit::e]\n";

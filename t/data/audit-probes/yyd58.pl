use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YKid; print YKid->can("hello") ? 1 : 0, YKid->isa("YBase") ? 1 : 0, "@YKid::ISA\n";

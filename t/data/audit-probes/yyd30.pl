use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; sub t { local $YInit::n = 4; YInit::get() } print t(), YInit::get(), "\n";

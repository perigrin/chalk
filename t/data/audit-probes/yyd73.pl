use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; sub t { my $b = $YInit::n; YInit::bump(); $b . $YInit::n } print t(), t(), "\n";

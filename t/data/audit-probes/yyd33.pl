use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; my $r = \$YInit::n; $$r = 8; print YInit::get(), "\n";

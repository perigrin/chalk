use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; if ($YInit::n == 1) { YInit::bump() } else { $YInit::n = 0 } print "$YInit::n\n";

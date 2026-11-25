use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use ZUp; my $s=""; for (1..3) { $s.=$ZUp::n; ZUp::bump(); } print "$s$ZUp::n\n";

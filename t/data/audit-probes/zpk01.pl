use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; my $s=""; for (1..3) { $s.=$zlow::n; zlow::bump(); } print "$s$zlow::n\n";

use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; my $s=""; my $i=0; while ($zlow::n<4) { zlow::bump(); $s.=$zlow::n } print "$s\n";

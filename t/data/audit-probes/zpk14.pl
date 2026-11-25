use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; sub rd { $zlow::n } my $a1=rd(); zlow::bump(); print $a1, rd(), "\n";

use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; my $m="bump"; my $b=$zlow::n; zlow->$m; print "$b$zlow::n\n";

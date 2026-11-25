use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; my $f=\&zlow::bump; my $b=$zlow::n; $f->(); print "$b$zlow::n\n";

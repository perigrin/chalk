use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; our $g=1; sub rd { $g } my $a1=rd(); zlow::poke(8); print $a1, rd(), "\n";

use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; $ZQ::v=1; my $a1=$ZQ::v; zlow::pokeq(3); print "$a1$ZQ::v\n";

use lib 'zlib', 'docs/research/son-ir-audit-2026-11-19/probes/z/zlib', 't/data/audit-probes/zlib'; use zlow; my @c=@zlow::l; zlow::addl(2); print scalar(@c), scalar(@zlow::l), "\n";

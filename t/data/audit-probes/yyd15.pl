use lib 'ylib', 'docs/research/son-ir-audit-2026-11-19/probes/y/ylib', 't/data/audit-probes/ylib'; use YInit; push @YInit::l, 7; $YInit::h{c} = 3; print YInit::lcount(), YInit::geth("c"), "\n";

our @g=(1); my $r=\$g[0]; sub t { local $g[0]=5; $$r } print t(), "\n";

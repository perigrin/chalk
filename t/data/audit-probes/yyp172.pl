our %g=(k=>1); my $r=\$g{k}; sub t { local $g{k}=5; $$r=7; $g{k} } print t(), "$g{k}\n";

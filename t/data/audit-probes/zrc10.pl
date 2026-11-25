sub h { my ($n,$f,$t,$v,$c)=@_; return 0 unless $n; h($n-1,$f,$v,$t)+1+h($n-1,$v,$t,$f) } print h(4,"a","c","b"), "\n";

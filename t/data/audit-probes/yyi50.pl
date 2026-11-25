sub perm { my ($done,@rest)=@_; return ($done) unless @rest; map { my @r=@rest; my ($p)=splice(@r,$_,1); perm($done.$p, @r) } 0..$#rest } print join(",", perm("", 1,2,3)), "\n";

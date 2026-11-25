my $x=1; sub f { my $s=""; my $i=0; while ($i++ < 2) { my ($p)=@_; $s.=$p; $x++ } $s } print f($x), "$x\n";

my $x=1; sub f { my $s=""; for my $i (1..2) { my @l=@_; $s.="@l"; $x++ } $s } print f($x), "$x\n";

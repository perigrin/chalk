my $x=1; sub f { my $p; if ($_[1]) { ($p)=@_ } $_[0]=9; $p } print f($x,1), "$x\n";

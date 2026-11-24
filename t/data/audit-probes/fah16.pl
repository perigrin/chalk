our $x=1; sub f { $x=2; return ($_[0], $_[0]+1) } my @r=f($x); print "@r\n";

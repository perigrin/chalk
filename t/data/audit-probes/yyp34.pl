my $x="ab"; sub f { my ($p)=@_; substr($_[0],0,1)="z"; $p } print f($x), "$x\n";

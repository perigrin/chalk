my $x=1; sub f { my $p=shift; my $q=shift; "$p$q" } print f($x++, $x), "\n";

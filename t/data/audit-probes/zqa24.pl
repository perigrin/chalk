my @a=(1,2); sub f { my $c=$_[0]+$_[1]; $a[0]=9; $c } print f(@a), "\n";

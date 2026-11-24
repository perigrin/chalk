my ($p,$q)=("a","b"); my $c=0; ($c ? $p : $q)++; ++($c ? $q : $p); print "$p $q\n";

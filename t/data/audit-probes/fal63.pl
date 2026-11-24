our ($p,$q)=(0,1); for (1..5) { my $t=$p+$q; $p=$q; $q=$t } print "$p $q\n";

my ($a1,$b1)=(1,2); my $ra=\$a1; ($a1,$b1)=($b1,$$ra); print "$a1 $b1\n";

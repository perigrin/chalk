my @a=(1,2); my ($p,$q)=(\@a,\@a); $p->[0]=5; my $x=$q->[0]; push @$q,7; my $n=@$p; print "$x$n\n";

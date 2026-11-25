my @a=(1,2); my ($p,$q)=(\@a,\@a); push @$p,3; my $n=@$q; pop @$q; print $n, scalar(@a), "\n";

my @a=(1,2); my @b=(\@a,\@a); push @{$b[0]},3; print scalar(@{$b[1]}),"\n";

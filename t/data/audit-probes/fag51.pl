my @a=(1,2); my @r=(\@a); my @c=@a; push @{$r[0]},3; print scalar(@c),"\n";

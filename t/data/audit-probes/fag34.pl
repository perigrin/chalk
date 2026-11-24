my @a=(1,2); my %h=(k=>\@a); my @c=@{$h{k}}; $a[0]=9; print "@c\n";

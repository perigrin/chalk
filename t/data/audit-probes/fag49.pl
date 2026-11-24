my @a=(1,2); my %h=(k=>\@a); my @c=@{$h{k}}; push @{$h{k}},3; print scalar(@c),"\n";

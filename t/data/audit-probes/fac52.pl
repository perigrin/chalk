my @a=(1,2); my %h=(k=>\@a); my @c=@{$h{k}}; push @a,3; print scalar(@c), scalar(@{$h{k}}),"\n";

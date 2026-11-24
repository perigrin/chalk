my @a=(1,2); my %h=(k=>[@a]); push @a,3; print scalar(@{$h{k}}),"\n";

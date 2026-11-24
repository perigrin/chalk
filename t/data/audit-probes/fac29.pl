my %h=(l=>[1,2]); my @c=@{$h{l}}; push @c,3; print scalar @{$h{l}},"\n";

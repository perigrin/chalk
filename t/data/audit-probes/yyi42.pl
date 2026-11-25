sub f { my @c = @{$_[0]}; $c[0] = 9; my %d = %{$_[1]}; $d{k} = 9; scalar(@c) . scalar(keys %d) } my @a=(1); my %h=(k=>1); print f(\@a,\%h), "$a[0]$h{k}\n";

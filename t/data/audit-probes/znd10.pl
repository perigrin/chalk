my @a=(1,2,3); my %idx; @idx{@a}=(0..$#a); my @inv; $inv[$idx{$_}]=$_ for keys %idx; print "@inv $idx{3}\n";

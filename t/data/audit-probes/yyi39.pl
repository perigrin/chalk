sub clr { @{$_[0]} = (); %{$_[1]} = () } my @a=(1,2); my %h=(a=>1); clr(\@a, \%h); print scalar(@a), scalar(keys %h), "\n";

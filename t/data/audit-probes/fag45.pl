my $l=[1]; sub ap { push @{$_[0]},2 } my $k=[@$l]; ap($l); print scalar(@$k),"\n";

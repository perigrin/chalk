my $l=[1]; sub ap { push @{$_[0]},2 } my $s="@$l"; ap($l); print "$s\n";

my $l=[1]; sub ap { push @{$_[0]},2 } my $n=scalar(@$l); ap($l); print "$n\n";

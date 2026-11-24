my $l=[1]; sub ap { push @{$_[0]},2 } my ($f)=@$l; my @c=@$l; ap($l); print "$f", scalar(@c), "\n";
